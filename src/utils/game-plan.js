// ─────────────────────────────────────────────────────────────────────────
// Friendly fair-rotation game-plan engine (Phase 1).
//
// Pure, deterministic (given an rng) so it can be unit-tested and re-run in the
// browser. Produces a doubles rotation across one or more courts where the
// PRIORITY is that everyone plays a roughly equal number of games with fairly
// spread-out rest — while still making each individual match balanced by Elo.
//
// Regeneration (mid-session): pass `gamesPlayed` (carried-forward counts) so a
// re-generated plan keeps fairness continuous after some matches are already
// done or a new player shows up.
// ─────────────────────────────────────────────────────────────────────────

// Deterministic-friendly RNG hook (default Math.random; tests inject a seeded one)
function defaultRng() { return Math.random() }

/**
 * @param {Object}   opts
 * @param {Array<{id:string, elo:number}>} opts.players  active pool (present, not resting)
 * @param {number}   opts.courts       courts available (>=1)
 * @param {number}   opts.matchCount   total matches to schedule (>=1)
 * @param {Object}   [opts.gamesPlayed] { [playerId]: number } carried-forward games (regeneration)
 * @param {number}   [opts.startSeq]   first seq number (default 1) — for appending after done matches
 * @param {number}   [opts.startRound] first round number (default 1)
 * @param {Function} [opts.rng]        () => number in [0,1)
 * @returns {{ matches: Array, gamesPlayed: Object, error?: string }}
 */
export function generatePlan({
  players, courts = 1, matchCount = 6, gamesPlayed = null,
  startSeq = 1, startRound = 1, rng = defaultRng,
}) {
  const pool = (players || []).filter(p => p && p.id)
  if (pool.length < 4) {
    return { matches: [], gamesPlayed: { ...(gamesPlayed || {}) }, error: 'Need at least 4 attendees to build a game plan.' }
  }
  courts     = Math.max(1, Math.floor(courts))
  matchCount = Math.max(1, Math.floor(matchCount))

  const elo = Object.fromEntries(pool.map(p => [p.id, Number(p.elo) || 1000]))
  const gp  = {}
  const rest = {}
  for (const p of pool) { gp[p.id] = (gamesPlayed && gamesPlayed[p.id]) || 0; rest[p.id] = 0 }

  // How many players can actually sit on courts in one round.
  const maxSeats = Math.min(4 * courts, Math.floor(pool.length / 4) * 4)

  const matches = []
  let seq = startSeq
  let round = startRound

  while (matches.length < matchCount) {
    const remaining = matchCount - matches.length
    const seatsThisRound = Math.min(maxSeats, remaining * 4)
    const courtsThisRound = seatsThisRound / 4

    // Rank the pool: fewest games first, then longest rest, then random.
    const ranked = [...pool].sort((a, b) =>
      (gp[a.id] - gp[b.id]) ||
      (rest[b.id] - rest[a.id]) ||
      (rng() - 0.5)
    )
    const playing = ranked.slice(0, seatsThisRound)
    const sitting = ranked.slice(seatsThisRound)
    for (const p of sitting) rest[p.id]++

    // Distribute the playing players across courts by Elo using serpentine
    // seeding so each court gets a balanced spread (e.g. 8 → C1:{1,4,5,8}, C2:{2,3,6,7}).
    const byElo = [...playing].sort((a, b) => elo[b.id] - elo[a.id])
    const groups = Array.from({ length: courtsThisRound }, () => [])
    let dir = 1, ci = 0
    for (const p of byElo) {
      groups[ci].push(p)
      if (dir === 1) { if (ci === courtsThisRound - 1) dir = -1; else ci++ }
      else           { if (ci === 0) dir = 1;          else ci-- }
    }

    for (let c = 0; c < courtsThisRound && matches.length < matchCount; c++) {
      // Within a court, split 4 by Elo into balanced teams: (strong+weak) vs (mid+mid).
      const g = [...groups[c]].sort((a, b) => elo[b.id] - elo[a.id]) // r0>=r1>=r2>=r3
      const sideA = [g[0].id, g[3].id]
      const sideB = [g[1].id, g[2].id]
      matches.push({ round, court: c + 1, seq, sideA, sideB })
      seq++
      for (const p of g) { gp[p.id]++; rest[p.id] = 0 }
    }
    round++
  }

  return { matches, gamesPlayed: gp }
}

/**
 * Convenience default for the "1 hr = 6 games, 2 hr = 12 games" rule.
 */
export function defaultMatchCount(hours) {
  return hours === 2 ? 12 : 6
}

// ─────────────────────────────────────────────────────────────────────────
// Winner-stays ("King of the Court") — DYNAMIC: the next match depends on who
// won, so it's generated one match ahead per court, with a waiting queue.
// A fairness cap rotates a pair out after N wins in a row so the bench still
// gets a full game (default 2).
// ─────────────────────────────────────────────────────────────────────────

function balanceFour(ids, elo) {
  const s = [...ids].sort((a, b) => (elo[b] || 1000) - (elo[a] || 1000))
  return { sideA: [s[0], s[3]], sideB: [s[1], s[2]] }   // strong+weak vs mid+mid
}

/**
 * Start a winner-stays session.
 * @returns {{ matches: Array, state: Object, error?: string }}
 *   matches: one starting match per court ({round,court,seq,sideA,sideB})
 *   state:   { queue: string[], streak: {court:number}, cap: number }
 */
export function winnerStaysInit({ players, courts = 1, cap = 2, rng = defaultRng }) {
  const pool = (players || []).filter(p => p && p.id)
  if (pool.length < 4) {
    return { matches: [], state: { queue: [], streak: {}, cap }, error: 'Need at least 4 attendees to start.' }
  }
  courts = Math.max(1, Math.floor(courts))
  const elo = Object.fromEntries(pool.map(p => [p.id, Number(p.elo) || 1000]))
  const maxCourts = Math.min(courts, Math.floor(pool.length / 4))
  const shuffled = [...pool].sort(() => rng() - 0.5)

  const matches = []
  const state = { queue: [], streak: {}, cap: Math.max(1, cap) }
  let idx = 0
  for (let c = 0; c < maxCourts; c++) {
    const four = shuffled.slice(idx, idx + 4).map(p => p.id); idx += 4
    const b = balanceFour(four, elo)
    matches.push({ round: 1, court: c + 1, seq: c + 1, sideA: b.sideA, sideB: b.sideB })
    state.streak[c + 1] = 0
  }
  state.queue = shuffled.slice(idx).map(p => p.id)
  return { matches, state }
}

/**
 * Advance one court after a result.
 * @returns {{ nextMatch: Object, state: Object }}
 */
export function winnerStaysAdvance({ court, winnerIds, loserIds, state, players, seq, round }) {
  const elo = Object.fromEntries((players || []).map(p => [p.id, Number(p.elo) || 1000]))
  let queue = [...(state.queue || [])]
  const cap = state.cap || 2
  const streak = (state.streak?.[court] || 0) + 1

  queue.push(...loserIds)                          // losers rejoin the back
  const rotateWinners = streak >= cap && queue.length >= 2

  let sideA, sideB, newStreak
  if (rotateWinners) {
    queue.push(...winnerIds)                        // winners rest too — fair to the bench
    const four = queue.splice(0, 4)
    const b = balanceFour(four, elo)
    sideA = b.sideA; sideB = b.sideB
    newStreak = 0
  } else {
    const challengers = queue.splice(0, 2)          // winners stay vs next two up
    if (challengers.length < 2) {                   // tiny group / no bench → rematch losers
      const need = 2 - challengers.length
      const fill = loserIds.slice(0, need)
      for (const id of fill) { const i = queue.lastIndexOf(id); if (i >= 0) queue.splice(i, 1) }
      challengers.push(...fill)
    }
    sideA = winnerIds; sideB = challengers
    newStreak = streak
  }

  return {
    nextMatch: { round: (round || 1) + 1, court, seq, sideA, sideB },
    state: { ...state, queue, streak: { ...(state.streak || {}), [court]: newStreak }, cap },
  }
}
