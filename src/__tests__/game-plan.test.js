import { describe, it, expect } from 'vitest'
import { generatePlan, defaultMatchCount } from '../utils/game-plan'

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

  it('defaultMatchCount maps hours → games', () => {
    expect(defaultMatchCount(1)).toBe(6)
    expect(defaultMatchCount(2)).toBe(12)
  })
})
