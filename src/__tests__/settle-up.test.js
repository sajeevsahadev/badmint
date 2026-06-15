import { describe, it, expect } from 'vitest'
import { computeSettledEdges } from '../utils/settle-up'

// Helper: build a netMap from an array of { id, name, net }
const mkMap = players =>
  Object.fromEntries(players.map(p => [p.id, p]))

describe('computeSettledEdges', () => {

  it('returns empty array for empty net map', () => {
    expect(computeSettledEdges({})).toEqual([])
  })

  it('returns empty array when all nets are below dust threshold', () => {
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  0.005 },
      { id: 'b', name: 'Bob',   net: -0.005 },
    ])
    expect(computeSettledEdges(m)).toHaveLength(0)
  })

  it('handles a single debt (A owes B 50)', () => {
    const m = mkMap([
      { id: 'alice', name: 'Alice', net:  50 },   // getter
      { id: 'bob',   name: 'Bob',   net: -50 },   // ower
    ])
    const edges = computeSettledEdges(m)
    expect(edges).toHaveLength(1)
    expect(edges[0]).toMatchObject({
      fromId: 'bob', fromName: 'Bob',
      toId: 'alice', toName: 'Alice',
      amount: 50,
    })
  })

  it('minimises to 2 edges for 3-player equal split (one paid)', () => {
    // Alice paid 90, each owes 30. Alice net +60, Bob net -30, Carol net -30.
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  60 },
      { id: 'b', name: 'Bob',   net: -30 },
      { id: 'c', name: 'Carol', net: -30 },
    ])
    const edges = computeSettledEdges(m)
    expect(edges).toHaveLength(2)
    expect(edges.every(e => e.toId === 'a')).toBe(true)
    expect(edges.every(e => e.amount === 30)).toBe(true)
  })

  it('produces ≤ N-1 edges for N parties', () => {
    // 5 players: one payer, four owers
    const m = mkMap([
      { id: 'host', name: 'Host', net: 200 },
      { id: 'p1',   name: 'P1',   net:  -50 },
      { id: 'p2',   name: 'P2',   net:  -50 },
      { id: 'p3',   name: 'P3',   net:  -50 },
      { id: 'p4',   name: 'P4',   net:  -50 },
    ])
    const edges = computeSettledEdges(m)
    expect(edges.length).toBeLessThanOrEqual(4)
    expect(edges.every(e => e.toId === 'host')).toBe(true)
    expect(edges.every(e => e.amount === 50)).toBe(true)
  })

  it('total settled amount equals total owed amount', () => {
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  100 },
      { id: 'b', name: 'Bob',   net:   50 },
      { id: 'c', name: 'Carol', net:  -80 },
      { id: 'd', name: 'Dan',   net:  -70 },
    ])
    const edges = computeSettledEdges(m)
    const total = edges.reduce((s, e) => s + e.amount, 0)
    expect(Math.round(total * 100) / 100).toBe(150)
  })

  it('zero-net player is excluded from edges', () => {
    const m = mkMap([
      { id: 'a', name: 'Alice',   net:  100 },
      { id: 'b', name: 'Bob',     net:    0 },   // exactly balanced
      { id: 'c', name: 'Carol',   net: -100 },
    ])
    const edges = computeSettledEdges(m)
    expect(edges).toHaveLength(1)
    expect(edges[0]).toMatchObject({ fromId: 'c', toId: 'a', amount: 100 })
    expect(edges.some(e => e.fromId === 'b' || e.toId === 'b')).toBe(false)
  })

  it('handles unequal split across multiple getters', () => {
    // Alice owed 70, Bob owed 30, Carol owes 100
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  70 },
      { id: 'b', name: 'Bob',   net:  30 },
      { id: 'c', name: 'Carol', net: -100 },
    ])
    const edges = computeSettledEdges(m)
    // Carol pays Alice 70 and Bob 30 — 2 edges total
    expect(edges).toHaveLength(2)
    const toAlice = edges.find(e => e.toId === 'a')
    const toBob   = edges.find(e => e.toId === 'b')
    expect(toAlice?.amount).toBe(70)
    expect(toBob?.amount).toBe(30)
  })

  it('handles decimal amounts without infinite loop', () => {
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  33.33 },
      { id: 'b', name: 'Bob',   net:  33.33 },
      { id: 'c', name: 'Carol', net: -66.66 },
    ])
    // Should terminate; total paid ≈ 66.66
    const edges = computeSettledEdges(m)
    const total = Math.round(edges.reduce((s, e) => s + e.amount, 0) * 100) / 100
    expect(total).toBe(66.66)
  })

  it('does not mutate the input netMap', () => {
    const m = mkMap([
      { id: 'a', name: 'Alice', net:  50 },
      { id: 'b', name: 'Bob',   net: -50 },
    ])
    const originalNet = m.a.net
    computeSettledEdges(m)
    expect(m.a.net).toBe(originalNet)
  })

  it('each fromId in an edge is always an ower (negative original net)', () => {
    const m = mkMap([
      { id: 'x', name: 'X', net:  120 },
      { id: 'y', name: 'Y', net:  -40 },
      { id: 'z', name: 'Z', net:  -80 },
    ])
    const owerIds = new Set(['y', 'z'])
    const edges = computeSettledEdges(m)
    expect(edges.every(e => owerIds.has(e.fromId))).toBe(true)
    expect(edges.every(e => e.toId === 'x')).toBe(true)
  })

})
