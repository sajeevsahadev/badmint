// ─────────────────────────────────────────────────────────────────────────
// Tournament draw engine (pure + deterministic given an rng), so it can be
// unit-tested and previewed in the browser before anything is saved.
//
// A "team" is { id, seed }. seed 1 = unseeded (the default). When ALL teams are
// unseeded the order is a deterministic shuffle; when seeds vary, teams are
// ordered by seed ascending (1 = top seed). Match objects carry client-generated
// ids so the save RPC can insert them verbatim with next-match linkage intact.
// ─────────────────────────────────────────────────────────────────────────

const uuid = () =>
  (globalThis.crypto?.randomUUID?.() ??
   'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
     const r = Math.random() * 16 | 0
     return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16)
   }))

function shuffle(arr, rng) {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

// Order teams for the draw. Unseeded (all equal) → deterministic shuffle;
// otherwise by seed ascending, id as a stable tie-break.
export function orderTeams(teams, rng = Math.random) {
  const list = (teams || []).filter(t => t && t.id)
  if (!list.length) return []
  const seeds = list.map(t => t.seed ?? 1)
  const allSame = seeds.every(s => s === seeds[0])
  if (allSame) return shuffle(list, rng)
  return [...list].sort((a, b) =>
    (a.seed ?? 9999) - (b.seed ?? 9999) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}

function nextPow2(n) { let p = 1; while (p < n) p *= 2; return p }

// Standard bracket seed positions for a bracket of `size` (power of 2).
// e.g. size 8 → [1,8,5,4,3,6,7,2] so top seeds are spread apart.
function seedOrder(size) {
  let rounds = [1, 2]
  while (rounds.length < size) {
    const n = rounds.length * 2
    const next = []
    for (const r of rounds) { next.push(r); next.push(n + 1 - r) }
    rounds = next
  }
  return rounds
}

const isTeam = x => x && typeof x === 'object'

// ── Single elimination (knock-out) with byes + seeded placement ──
export function buildKnockout(orderedTeams, opts = {}) {
  const teams = (orderedTeams || []).filter(isTeam)
  if (teams.length < 2) return []
  const stage = opts.stage || 'knockout'
  const size = nextPow2(teams.length)
  const slots = seedOrder(size)                 // seed rank at each bracket position
  const bracket = slots.map(rank => rank <= teams.length ? teams[rank - 1] : null) // null = bye

  const byRound = []
  let roundTeams = bracket
  let roundNum = opts.startRound || 1
  while (roundTeams.length > 1) {
    const rm = []
    for (let i = 0; i < roundTeams.length; i += 2) {
      const a = roundTeams[i], b = roundTeams[i + 1]
      rm.push({
        id: uuid(), round: roundNum, position: i / 2, stage,
        team_a_id: a ? a.id : null, team_b_id: b ? b.id : null,
        winner_id: null, status: 'pending', next_match_id: null, next_match_slot: null,
        group_label: opts.group_label || null,
      })
    }
    byRound.push(rm)
    // A bye (one side empty) auto-advances its team to the next round.
    roundTeams = rm.map(m => {
      if (m.team_a_id && !m.team_b_id) return teams.find(t => t.id === m.team_a_id)
      if (!m.team_a_id && m.team_b_id) return teams.find(t => t.id === m.team_b_id)
      return null
    })
    roundNum++
  }

  const matches = byRound.flat()

  // Link each match to its parent (round r pos p → round r+1 pos floor(p/2)).
  for (let r = 0; r < byRound.length - 1; r++) {
    for (const m of byRound[r]) {
      const parent = byRound[r + 1][Math.floor(m.position / 2)]
      m.next_match_id = parent.id
      m.next_match_slot = m.position % 2 === 0 ? 'A' : 'B'
    }
  }

  // Resolve byes: ONLY first-round matches can be byes (a round-2 slot that is
  // still empty is TBD — fed by a real match — not a bye). Mark done, set the
  // winner, and pre-fill the parent slot.
  const byId = Object.fromEntries(matches.map(m => [m.id, m]))
  for (const m of byRound[0]) {
    const bye = (m.team_a_id && !m.team_b_id) || (!m.team_a_id && m.team_b_id)
    if (bye) {
      m.winner_id = m.team_a_id || m.team_b_id
      m.status = 'bye'
      if (m.next_match_id) {
        const p = byId[m.next_match_id]
        if (m.next_match_slot === 'A') p.team_a_id = m.winner_id
        else p.team_b_id = m.winner_id
      }
    }
  }
  return matches
}

// ── Round robin (circle method); optionally scoped to a group ──
export function buildRoundRobin(orderedTeams, opts = {}) {
  const base = (orderedTeams || []).filter(isTeam)
  if (base.length < 2) return []
  const stage = opts.stage || 'round_robin'
  const teams = [...base]
  if (teams.length % 2 === 1) teams.push(null)  // odd → phantom bye
  const n = teams.length, half = n / 2, rounds = n - 1
  const matches = []
  let arr = teams.slice()
  for (let r = 0; r < rounds; r++) {
    let pos = 0
    for (let i = 0; i < half; i++) {
      const a = arr[i], b = arr[n - 1 - i]
      if (a && b) {
        matches.push({
          id: uuid(), round: r + 1, position: pos++, stage,
          team_a_id: a.id, team_b_id: b.id, winner_id: null, status: 'pending',
          next_match_id: null, next_match_slot: null, group_label: opts.group_label || null,
        })
      }
    }
    arr = [arr[0], arr[n - 1], ...arr.slice(1, n - 1)]  // rotate, first fixed
  }
  return matches
}

// ── Groups: snake-seed into N groups, round robin within each ──
export function buildGroups(orderedTeams, groupsCount) {
  const teams = (orderedTeams || []).filter(isTeam)
  const g = Math.max(1, Math.min(groupsCount || 2, Math.floor(teams.length / 2) || 1))
  const groups = Array.from({ length: g }, () => [])
  let dir = 1, gi = 0
  for (const t of teams) {
    groups[gi].push(t)
    if (dir === 1) { if (gi === g - 1) dir = -1; else gi++ }
    else           { if (gi === 0) dir = 1; else gi-- }
  }
  const matches = []
  groups.forEach((grp, idx) => {
    const label = String.fromCharCode(65 + idx)
    matches.push(...buildRoundRobin(grp, { stage: 'group', group_label: label }))
  })
  return {
    groups: groups.map((grp, idx) => ({ label: String.fromCharCode(65 + idx), teamIds: grp.map(t => t.id) })),
    matches,
  }
}

// Assign courts within each round so simultaneous matches get different courts.
export function assignCourts(matches, courts = 1) {
  const c = Math.max(1, courts | 0)
  const byKey = {}
  for (const m of matches) {
    const key = `${m.stage}|${m.group_label || ''}|${m.round}`
    ;(byKey[key] ||= []).push(m)
  }
  for (const list of Object.values(byKey)) {
    list.sort((a, b) => a.position - b.position)
    list.forEach((m, i) => { m.court = String((i % c) + 1) })
  }
  return matches
}

// Top-level: build the full initial draw for a tournament.
// groups_knockout builds ONLY the group stage here — the knockout is generated
// later from the group standings (once results are in).
export function generateDraw({ teams, drawType, groupsCount = 2, courts = 1, rng = Math.random }) {
  const ordered = orderTeams(teams, rng)
  if (ordered.length < 2) return { matches: [], groups: [], error: 'Need at least 2 confirmed teams.' }
  let matches = [], groups = []
  if (drawType === 'round_robin') {
    matches = buildRoundRobin(ordered, { stage: 'round_robin' })
  } else if (drawType === 'groups_knockout') {
    const r = buildGroups(ordered, groupsCount)
    matches = r.matches; groups = r.groups
  } else {
    matches = buildKnockout(ordered, { stage: 'knockout' })
  }
  assignCourts(matches, courts)
  return { matches, groups }
}
