import { describe, it, expect } from 'vitest'
import {
  orderTeams, buildKnockout, buildRoundRobin, buildGroups, assignCourts, generateDraw,
  seedAdvancers, buildKnockoutFromGroups, computeGroupStandings,
} from '../utils/tournament-draw'

function seeded(seed = 1) {
  let s = seed >>> 0
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296 }
}
const mk = (n, seedFn = () => 1) =>
  Array.from({ length: n }, (_, i) => ({ id: `t${i + 1}`, seed: seedFn(i) }))

const ids = m => [m.team_a_id, m.team_b_id]

describe('orderTeams', () => {
  it('unseeded (all seed 1) is a deterministic shuffle', () => {
    const teams = mk(8)
    const a = orderTeams(teams, seeded(5)).map(t => t.id)
    const b = orderTeams(teams, seeded(5)).map(t => t.id)
    expect(a).toEqual(b)                       // same rng → same order
    expect(new Set(a).size).toBe(8)            // all present
  })
  it('seeded teams are ordered by seed ascending', () => {
    const teams = [{ id: 'x', seed: 3 }, { id: 'y', seed: 1 }, { id: 'z', seed: 2 }]
    expect(orderTeams(teams).map(t => t.id)).toEqual(['y', 'z', 'x'])
  })
})

describe('buildKnockout', () => {
  it('8 teams → 7 matches over 3 rounds, fully linked', () => {
    const m = buildKnockout(mk(8))
    expect(m).toHaveLength(7)
    expect(new Set(m.map(x => x.round))).toEqual(new Set([1, 2, 3]))
    expect(m.filter(x => x.round === 1)).toHaveLength(4)
    // every non-final match points to a real parent match
    const byId = Object.fromEntries(m.map(x => [x.id, x]))
    for (const x of m.filter(x => x.round < 3)) {
      expect(byId[x.next_match_id]).toBeTruthy()
      expect(['A', 'B']).toContain(x.next_match_slot)
    }
    // round 1 uses all 8 teams exactly once
    const r1 = m.filter(x => x.round === 1).flatMap(ids)
    expect(new Set(r1)).toEqual(new Set(mk(8).map(t => t.id)))
  })

  it('non-power-of-two (6 teams) gives byes that auto-advance top seeds', () => {
    const teams = mk(6, i => i + 1)          // seeds 1..6
    const m = buildKnockout(orderTeams(teams))
    // bracket size 8 → 2 byes; top 2 seeds should skip round 1
    const byes = m.filter(x => x.status === 'bye')
    expect(byes.length).toBe(2)
    for (const b of byes) {
      expect(b.winner_id).toBeTruthy()
      // the bye winner is pre-filled into its parent match
      const parent = m.find(x => x.id === b.next_match_id)
      const slot = b.next_match_slot === 'A' ? parent.team_a_id : parent.team_b_id
      expect(slot).toBe(b.winner_id)
    }
  })

  it('every team appears and the bracket has a single final', () => {
    const m = buildKnockout(mk(16))
    expect(m).toHaveLength(15)
    expect(m.filter(x => x.next_match_id === null)).toHaveLength(1) // the final
  })
})

describe('buildRoundRobin', () => {
  it('n teams → n*(n-1)/2 matches, each pair exactly once', () => {
    const m = buildRoundRobin(mk(6))
    expect(m).toHaveLength(15)
    const pairs = m.map(x => [x.team_a_id, x.team_b_id].sort().join('-'))
    expect(new Set(pairs).size).toBe(15)
  })
  it('no team plays twice in the same round', () => {
    const m = buildRoundRobin(mk(6))
    const byRound = {}
    for (const x of m) (byRound[x.round] ||= []).push(...ids(x))
    for (const list of Object.values(byRound)) expect(new Set(list).size).toBe(list.length)
  })
  it('odd team count works (5 teams → 10 matches)', () => {
    expect(buildRoundRobin(mk(5))).toHaveLength(10)
  })
})

describe('buildGroups', () => {
  it('snake-seeds into groups and round-robins each', () => {
    const { groups, matches } = buildGroups(mk(8), 2)
    expect(groups).toHaveLength(2)
    expect(groups[0].teamIds).toHaveLength(4)
    expect(groups[1].teamIds).toHaveLength(4)
    // 2 groups of 4 → 6 + 6 = 12 group matches
    expect(matches).toHaveLength(12)
    expect(matches.every(m => m.stage === 'group')).toBe(true)
    expect(new Set(matches.map(m => m.group_label))).toEqual(new Set(['A', 'B']))
  })
})

describe('status vocabulary', () => {
  it('round-1 knockout matches are scheduled, later rounds pending', () => {
    const m = buildKnockout(mk(8))
    expect(m.filter(x => x.round === 1).every(x => x.status === 'scheduled')).toBe(true)
    expect(m.filter(x => x.round > 1).every(x => x.status === 'pending')).toBe(true)
  })
  it('round-robin matches are all scheduled', () => {
    expect(buildRoundRobin(mk(6)).every(x => x.status === 'scheduled')).toBe(true)
  })
})

describe('seedAdvancers + buildKnockoutFromGroups', () => {
  const groups = [
    { label: 'A', teams: [{ id: 'a1' }, { id: 'a2' }, { id: 'a3' }] },
    { label: 'B', teams: [{ id: 'b1' }, { id: 'b2' }, { id: 'b3' }] },
  ]
  it('seeds winners then runners-up in group order', () => {
    // winners in group order: a1,b1 ; then runners-up in group order: a2,b2
    expect(seedAdvancers(groups, 2).map(t => t.id)).toEqual(['a1', 'b1', 'a2', 'b2'])
  })
  it('builds a knockout of the advancers (4 teams → 3 matches, 1 final)', () => {
    const m = buildKnockoutFromGroups(groups, 2)
    expect(m).toHaveLength(3)
    expect(m.filter(x => x.next_match_id === null)).toHaveLength(1)
    // only advancers appear
    const teamIds = new Set(m.flatMap(ids).filter(Boolean))
    expect([...teamIds].sort()).toEqual(['a1', 'a2', 'b1', 'b2'])
  })
  it('never pairs two teams from the same group in the first knockout round', () => {
    const m = buildKnockoutFromGroups(groups, 2)  // 4 teams → 2 first-round matches
    const grp = id => (id && id[0])               // 'a'/'b' from the id
    for (const match of m.filter(x => x.round === 1)) {
      if (match.team_a_id && match.team_b_id) {
        expect(grp(match.team_a_id)).not.toBe(grp(match.team_b_id))
      }
    }
  })
  it('needs at least 2 advancers', () => {
    expect(buildKnockoutFromGroups([{ label: 'A', teams: [{ id: 'x' }] }], 2)).toHaveLength(0)
  })
})

describe('computeGroupStandings', () => {
  it('ranks a group by wins then set difference', () => {
    // Group A: x1 beats x2 (11-2), x1 beats x3 (11-9), x2 beats x3 (11-8)
    const matches = [
      { stage: 'group', group_label: 'A', team_a_id: 'x1', team_b_id: 'x2', score_a: 11, score_b: 2, winner_id: 'x1', status: 'completed' },
      { stage: 'group', group_label: 'A', team_a_id: 'x1', team_b_id: 'x3', score_a: 11, score_b: 9, winner_id: 'x1', status: 'completed' },
      { stage: 'group', group_label: 'A', team_a_id: 'x2', team_b_id: 'x3', score_a: 11, score_b: 8, winner_id: 'x2', status: 'completed' },
    ]
    const g = computeGroupStandings(matches)
    expect(g).toHaveLength(1)
    expect(g[0].teams.map(t => t.id)).toEqual(['x1', 'x2', 'x3'])
    expect(g[0].teams[0].wins).toBe(2)
  })
  it('ignores knockout matches and unplayed group games', () => {
    const matches = [
      { stage: 'group', group_label: 'A', team_a_id: 'x1', team_b_id: 'x2', status: 'scheduled' },
      { stage: 'knockout', team_a_id: 'x1', team_b_id: 'x2', score_a: 11, score_b: 3, winner_id: 'x1', status: 'completed' },
    ]
    const g = computeGroupStandings(matches)
    expect(g[0].teams.every(t => t.played === 0)).toBe(true)
  })
})

describe('assignCourts', () => {
  it('distinct courts for simultaneous matches within a round', () => {
    const m = assignCourts(buildKnockout(mk(8)), 2)
    const r1 = m.filter(x => x.round === 1)
    expect(new Set(r1.map(x => x.court))).toEqual(new Set(['1', '2']))
  })
})

describe('generateDraw', () => {
  it('dispatches by draw type', () => {
    expect(generateDraw({ teams: mk(8), drawType: 'knockout' }).matches).toHaveLength(7)
    expect(generateDraw({ teams: mk(6), drawType: 'round_robin' }).matches).toHaveLength(15)
    const g = generateDraw({ teams: mk(8), drawType: 'groups_knockout', groupsCount: 2 })
    expect(g.groups).toHaveLength(2)
    expect(g.matches).toHaveLength(12)
  })
  it('needs at least 2 teams', () => {
    expect(generateDraw({ teams: mk(1), drawType: 'knockout' }).error).toBeTruthy()
  })
  it('is deterministic for a given rng', () => {
    const a = generateDraw({ teams: mk(8), drawType: 'knockout', rng: seeded(9) }).matches.flatMap(ids)
    const b = generateDraw({ teams: mk(8), drawType: 'knockout', rng: seeded(9) }).matches.flatMap(ids)
    expect(a).toEqual(b)
  })
})
