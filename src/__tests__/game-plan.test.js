import { describe, it, expect } from 'vitest'
import { generatePlan, defaultMatchCount, winnerStaysInit, winnerStaysAdvance } from '../utils/game-plan'

// Seeded RNG so tie-breaks are deterministic in tests.
function seeded(seed = 1) {
  let s = seed >>> 0
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296 }
}

const mkPlayers = (n, baseElo = 1000) =>
  Array.from({ length: n }, (_, i) => ({ id: `p${i + 1}`, elo: baseElo + i * 10 }))

function tally(matches) {
  const gp = {}
  for (const m of matches) for (const id of [...m.sideA, ...m.sideB]) gp[id] = (gp[id] || 0) + 1
  return gp
}

describe('generatePlan — friendly fair rotation', () => {
  it('needs at least 4 players', () => {
    const { matches, error } = generatePlan({ players: mkPlayers(3), courts: 1, matchCount: 5 })
    expect(error).toBeTruthy()
    expect(matches).toHaveLength(0)
  })

  it('produces exactly matchCount matches', () => {
    const { matches } = generatePlan({ players: mkPlayers(7), courts: 1, matchCount: 6, rng: seeded() })
    expect(matches).toHaveLength(6)
  })

  it('every match has 4 distinct players in two teams of two', () => {
    const { matches } = generatePlan({ players: mkPlayers(7), courts: 1, matchCount: 6, rng: seeded() })
    for (const m of matches) {
      expect(m.sideA).toHaveLength(2)
      expect(m.sideB).toHaveLength(2)
      const ids = [...m.sideA, ...m.sideB]
      expect(new Set(ids).size).toBe(4)
    }
  })

  it('7 players / 1 court / 7 matches → games differ by at most 1 (fairness)', () => {
    const { matches } = generatePlan({ players: mkPlayers(7), courts: 1, matchCount: 7, rng: seeded(42) })
    const gp = tally(matches)
    const counts = mkPlayers(7).map(p => gp[p.id] || 0)
    expect(Math.max(...counts) - Math.min(...counts)).toBeLessThanOrEqual(1)
  })

  it('8 players / 2 courts / 6 matches → 2 matches per round, everyone plays 3', () => {
    const { matches } = generatePlan({ players: mkPlayers(8), courts: 2, matchCount: 6, rng: seeded(7) })
    expect(matches).toHaveLength(6)
    // 3 rounds, each with 2 courts
    const rounds = new Set(matches.map(m => m.round))
    expect(rounds.size).toBe(3)
    const gp = tally(matches)
    for (const p of mkPlayers(8)) expect(gp[p.id]).toBe(3)
  })

  it('never seats the same player on both courts in one round', () => {
    const { matches } = generatePlan({ players: mkPlayers(8), courts: 2, matchCount: 6, rng: seeded(9) })
    const byRound = {}
    for (const m of matches) (byRound[m.round] ||= []).push(...m.sideA, ...m.sideB)
    for (const ids of Object.values(byRound)) expect(new Set(ids).size).toBe(ids.length)
  })

  it('carries fairness forward on regeneration (gamesPlayed)', () => {
    const players = mkPlayers(5)
    // p1 already played a lot; regeneration should favour the others first.
    const gamesPlayed = { p1: 5, p2: 0, p3: 0, p4: 0, p5: 0 }
    const { matches } = generatePlan({ players, courts: 1, matchCount: 1, gamesPlayed, rng: seeded(3) })
    const ids = [...matches[0].sideA, ...matches[0].sideB]
    expect(ids).not.toContain('p1') // the already-busy player sits out first
  })

  it('returns updated gamesPlayed totals', () => {
    const { matches, gamesPlayed } = generatePlan({ players: mkPlayers(4), courts: 1, matchCount: 3, rng: seeded() })
    const total = Object.values(gamesPlayed).reduce((a, b) => a + b, 0)
    expect(total).toBe(matches.length * 4)
  })

  it('defaultMatchCount maps hours → games (any duration)', () => {
    expect(defaultMatchCount(1)).toBe(6)
    expect(defaultMatchCount(2)).toBe(12)
    expect(defaultMatchCount(3)).toBe(18)
    expect(defaultMatchCount(1.5)).toBe(9)
  })

  it('is deterministic — same attendees always give the identical plan', () => {
    const players = mkPlayers(7)
    const a = generatePlan({ players, courts: 1, matchCount: 8 })
    const b = generatePlan({ players, courts: 1, matchCount: 8 })
    expect(JSON.stringify(a.matches)).toBe(JSON.stringify(b.matches))
    // First match is the 4 highest-Elo (all tied on games=0) → stable, not random.
    const first = [...a.matches[0].sideA, ...a.matches[0].sideB]
    expect(new Set(first)).toEqual(new Set(['p7', 'p6', 'p5', 'p4']))
  })

  it('6 players / 1 court: clean rotation — never 3 in a row, never rests twice in a row', () => {
    const players = mkPlayers(6)
    const { matches } = generatePlan({ players, courts: 1, matchCount: 9, rng: seeded(11) })
    // Build a per-round play/rest map.
    const byRound = {}
    for (const m of matches) { (byRound[m.round] ||= new Set()); for (const id of [...m.sideA, ...m.sideB]) byRound[m.round].add(id) }
    const roundNums = Object.keys(byRound).map(Number).sort((a, b) => a - b)
    for (const p of players) {
      let playStreak = 0, restStreak = 0, maxPlay = 0, maxRest = 0
      for (const r of roundNums) {
        if (byRound[r].has(p.id)) { playStreak++; restStreak = 0 }
        else { restStreak++; playStreak = 0 }
        maxPlay = Math.max(maxPlay, playStreak)
        maxRest = Math.max(maxRest, restStreak)
      }
      expect(maxPlay).toBeLessThanOrEqual(2)   // at most "2 stay", then rest
      expect(maxRest).toBeLessThanOrEqual(1)   // never benched two rounds running
    }
    // …and games are perfectly even over 9 rounds.
    const gp = tally(matches)
    const counts = players.map(p => gp[p.id] || 0)
    expect(Math.max(...counts) - Math.min(...counts)).toBeLessThanOrEqual(1)
  })
})

describe('winnerStaysInit', () => {
  it('needs at least 4 players', () => {
    const { error } = winnerStaysInit({ players: mkPlayers(3), courts: 1 })
    expect(error).toBeTruthy()
  })

  it('8 players / 2 courts → 2 matches, empty queue', () => {
    const { matches, state } = winnerStaysInit({ players: mkPlayers(8), courts: 2, rng: seeded() })
    expect(matches).toHaveLength(2)
    expect(state.queue).toHaveLength(0)
    expect(state.streak).toEqual({ 1: 0, 2: 0 })
    for (const m of matches) expect(new Set([...m.sideA, ...m.sideB]).size).toBe(4)
  })

  it('6 players / 1 court → 1 match, 2 waiting', () => {
    const { matches, state } = winnerStaysInit({ players: mkPlayers(6), courts: 1, rng: seeded() })
    expect(matches).toHaveLength(1)
    expect(state.queue).toHaveLength(2)
  })
})

describe('winnerStaysAdvance', () => {
  const players = mkPlayers(6)  // p1..p6
  const init = () => winnerStaysInit({ players, courts: 1, cap: 2, rng: seeded(5) })

  it('winners stay and two from the queue challenge (streak < cap)', () => {
    const { matches, state } = init()
    const m = matches[0]
    const winners = m.sideA
    const { nextMatch, state: s2 } = winnerStaysAdvance({
      court: 1, winnerIds: winners, loserIds: m.sideB, state, players, seq: 2, round: 1,
    })
    // winners are still on Side A
    expect(nextMatch.sideA).toEqual(winners)
    // challengers came from the original queue (the 2 who were waiting)
    expect(new Set([...nextMatch.sideA, ...nextMatch.sideB]).size).toBe(4)
    // losers went to the back of the queue
    expect(s2.queue).toEqual(expect.arrayContaining(m.sideB))
    expect(s2.streak[1]).toBe(1)
  })

  it('rotates everyone out after reaching the win cap', () => {
    let { matches, state } = init()
    let m = matches[0]
    let winners = m.sideA
    // win #1
    let r = winnerStaysAdvance({ court: 1, winnerIds: winners, loserIds: m.sideB, state, players, seq: 2, round: 1 })
    // win #2 (reaches cap=2) — same winners win again
    const nm = r.nextMatch
    r = winnerStaysAdvance({ court: 1, winnerIds: nm.sideA, loserIds: nm.sideB, state: r.state, players, seq: 3, round: 2 })
    expect(r.state.streak[1]).toBe(0)                 // streak reset after rotation
    // the twice-winning pair is now waiting in the queue
    expect(r.state.queue).toEqual(expect.arrayContaining(nm.sideA))
  })

  it('conserves all players across an advance', () => {
    const { matches, state } = init()
    const m = matches[0]
    const before = new Set([...m.sideA, ...m.sideB, ...state.queue])
    const { nextMatch, state: s2 } = winnerStaysAdvance({
      court: 1, winnerIds: m.sideA, loserIds: m.sideB, state, players, seq: 2, round: 1,
    })
    const after = new Set([...nextMatch.sideA, ...nextMatch.sideB, ...s2.queue])
    expect(after).toEqual(before)
  })
})
