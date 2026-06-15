/**
 * Greedy minimum-transaction settle-up (Splitwise-style).
 *
 * @param {Record<string, {id: string, name: string, net: number}>} netMap
 *   net > 0  → player is owed money (getter)
 *   net < 0  → player owes money (ower)
 * @returns {{ fromId, fromName, toId, toName, amount }[]}
 */
export function computeSettledEdges(netMap) {
  const positions = Object.values(netMap).filter(p => Math.abs(p.net) >= 0.01)
  const getters = positions
    .filter(p => p.net > 0)
    .map(p => ({ ...p }))
    .sort((a, b) => b.net - a.net)
  const owers = positions
    .filter(p => p.net < 0)
    .map(p => ({ ...p, net: Math.abs(p.net) }))
    .sort((a, b) => b.net - a.net)

  const edges = []
  let gi = 0, oi = 0
  while (gi < getters.length && oi < owers.length) {
    const g = getters[gi], o = owers[oi]
    const amount = Math.round(Math.min(g.net, o.net) * 100) / 100
    if (amount >= 0.01) {
      edges.push({ fromId: o.id, fromName: o.name, toId: g.id, toName: g.name, amount })
    }
    g.net = Math.round((g.net - amount) * 100) / 100
    o.net = Math.round((o.net - amount) * 100) / 100
    if (g.net < 0.01) gi++
    if (o.net < 0.01) oi++
  }
  return edges
}
