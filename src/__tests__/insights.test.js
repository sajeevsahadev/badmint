import { describe, it, expect } from 'vitest'
import { computeStreaks, computePointsDiff, computePartnerships, computeHeadToHead } from '../utils/insights'
import { tierFor, nextTier } from '../utils/tiers'
import { evaluateAchievements, earnedCount, ACHIEVEMENTS } from '../utils/achievements'

// ── Streaks ────────────────────────────────────────────────────────────────
describe('computeStreaks', () => {
  it('handles an empty history', () => {
    expect(computeStreaks([])).toEqual({ current: 0, type: null, longestWin: 0, longestLoss: 0 })
  })
  it('finds the trailing current streak', () => {
    // chronological: L W W W  → currently on a 3-win streak
    const s = computeStreaks([false, true, true, true])
    expect(s.current).toBe(3)
    expect(s.type).toBe('win')
    expect(s.longestWin).toBe(3)
    expect(s.longestLoss).toBe(1)
  })
  it('reports a current loss streak', () => {
    const s = computeStreaks([true, true, false, false])
    expect(s.current).toBe(2)
    expect(s.type).toBe('loss')
    expect(s.longestWin).toBe(2)
    expect(s.longestLoss).toBe(2)
  })
  it('tracks the longest win streak even when it is not current', () => {
    // W W W W L  → longestWin 4, but currently on a 1-loss streak
    const s = computeStreaks([true, true, true, true, false])
    expect(s.longestWin).toBe(4)
    expect(s.current).toBe(1)
    expect(s.type).toBe('loss')
  })
})

// ── Points differential ──────────────────────────────────────────────────
describe('computePointsDiff', () => {
  it('sums the score gaps', () => {
    const matches = [
      { myScore: 21, oppScore: 15 },  // +6
      { myScore: 18, oppScore: 21 },  // -3
      { myScore: 21, oppScore: 19 },  // +2
    ]
    expect(computePointsDiff(matches)).toBe(5)
  })
  it('is zero for no matches', () => {
    expect(computePointsDiff([])).toBe(0)
  })
})

// ── Partnerships & head-to-head ────────────────────────────────────────────
const matches = [
  { won: true,  eloDelta: 12, partners: [{ id: 'p1', name: 'Alex' }], opponents: [{ id: 'o1', name: 'Mike' }, { id: 'o2', name: 'Lisa' }] },
  { won: true,  eloDelta: 8,  partners: [{ id: 'p1', name: 'Alex' }], opponents: [{ id: 'o1', name: 'Mike' }, { id: 'o3', name: 'Sam' }] },
  { won: false, eloDelta: -10, partners: [{ id: 'p2', name: 'Emma' }], opponents: [{ id: 'o1', name: 'Mike' }, { id: 'o2', name: 'Lisa' }] },
]

describe('computePartnerships', () => {
  it('aggregates games, win% and avg Elo per partner, best first', () => {
    const parts = computePartnerships(matches)
    expect(parts).toHaveLength(2)
    const alex = parts.find(p => p.id === 'p1')
    expect(alex).toMatchObject({ games: 2, wins: 2, winPct: 100, avgElo: 10 }) // (12+8)/2
    const emma = parts.find(p => p.id === 'p2')
    expect(emma).toMatchObject({ games: 1, wins: 0, winPct: 0, avgElo: -10 })
    expect(parts[0].id).toBe('p1') // sorted best win% first
  })
})

describe('computeHeadToHead', () => {
  it('aggregates per opponent, most-played first', () => {
    const h2h = computeHeadToHead(matches)
    const mike = h2h.find(o => o.id === 'o1')
    expect(mike).toMatchObject({ games: 3, wins: 2, winPct: 67 })
    expect(h2h[0].id).toBe('o1') // Mike appears in all 3 → most played
  })
  it('skips people without an id (guest rows with no player id)', () => {
    const h2h = computeHeadToHead([{ won: true, opponents: [{ id: null, name: 'Ghost' }] }])
    expect(h2h).toHaveLength(0)
  })
})

// ── Tiers ──────────────────────────────────────────────────────────────────
describe('tierFor', () => {
  it('maps Elo to the right band', () => {
    expect(tierFor(900).key).toBe('bronze')
    expect(tierFor(1100).key).toBe('silver')
    expect(tierFor(1250).key).toBe('gold')
    expect(tierFor(1450).key).toBe('platinum')
    expect(tierFor(1650).key).toBe('diamond')
    expect(tierFor(9999).key).toBe('diamond')
  })
  it('defends against non-numbers', () => {
    expect(tierFor(undefined).key).toBe('bronze')
    expect(tierFor(NaN).key).toBe('bronze')
  })
})

describe('nextTier', () => {
  it('reports Elo needed for the next tier up', () => {
    const n = nextTier(1200) // silver → gold at 1250
    expect(n.key).toBe('gold')
    expect(n.needed).toBe(50)
  })
  it('returns null at the top tier', () => {
    expect(nextTier(1700)).toBeNull()
  })
})

// ── Achievements ─────────────────────────────────────────────────────────
describe('evaluateAchievements', () => {
  it('returns one entry per definition, earned-first', () => {
    const list = evaluateAchievements({ games: 0, wins: 0, winPct: 0, elo: 1000, streaks: { longestWin: 0 } })
    expect(list).toHaveLength(ACHIEVEMENTS.length)
    expect(earnedCount(list)).toBe(0)
    // A brand-new player has locked achievements carrying progress toward a goal
    const regular = list.find(a => a.id === 'regular')
    expect(regular.earned).toBe(false)
    expect(regular.progress).toEqual({ cur: 0, goal: 10 })
  })

  it('unlocks the right badges for a strong player', () => {
    const list = evaluateAchievements({
      games: 30, wins: 24, winPct: 80, elo: 1700,
      streaks: { longestWin: 6, current: 3, type: 'win' },
      pointsDiff: 120,
      partnerships: [{ games: 8, winPct: 75 }],
    })
    const earned = new Set(list.filter(a => a.earned).map(a => a.id))
    expect(earned.has('first_win')).toBe(true)
    expect(earned.has('regular')).toBe(true)
    expect(earned.has('on_fire')).toBe(true)       // 6 >= 3
    expect(earned.has('unstoppable')).toBe(true)   // 6 >= 5
    expect(earned.has('juggernaut')).toBe(false)   // 6 < 10
    expect(earned.has('consistent')).toBe(true)    // 80% over 30
    expect(earned.has('dominator')).toBe(true)     // 75%+ over 20
    expect(earned.has('reach_diamond')).toBe(true) // 1700 Elo
    expect(earned.has('dynamic_duo')).toBe(true)   // partner 8 games @ 75%
    // earned achievements sort ahead of locked ones
    expect(list[0].earned).toBe(true)
  })

  it('tolerates a missing context (defaults applied)', () => {
    const list = evaluateAchievements({})
    expect(earnedCount(list)).toBe(0)
  })
})
