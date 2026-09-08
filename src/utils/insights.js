// Player insight computations — pure functions over a player's match history.
// Everything here is derived from data PlayerProfile.vue already loads (each
// match carries won/score/eloDelta plus partner & opponent ids), so these add
// EloSmash-style analytics with no extra queries and full offline support.
//
// Match shape expected:
//   { won:boolean, myScore:number, oppScore:number, eloDelta:number|null,
//     partners:[{id,name}], opponents:[{id,name}] }
// The `matches` arrays passed in are newest-first (as PlayerProfile builds them);
// helpers that care about order reverse internally.

// Current + longest win/loss streaks.
// `wonChrono` is an array of booleans in chronological (oldest-first) order.
export function computeStreaks(wonChrono) {
  let longestWin = 0, longestLoss = 0, runW = 0, runL = 0
  for (const w of wonChrono) {
    if (w) { runW++; runL = 0; if (runW > longestWin) longestWin = runW }
    else   { runL++; runW = 0; if (runL > longestLoss) longestLoss = runL }
  }
  // Current streak = the trailing run (walk back from the most recent match).
  let current = 0, type = null
  for (let i = wonChrono.length - 1; i >= 0; i--) {
    const t = wonChrono[i] ? 'win' : 'loss'
    if (current === 0) { type = t; current = 1 }
    else if (t === type) current++
    else break
  }
  return { current, type, longestWin, longestLoss }
}

// Net points differential across all matches (sum of my score − opp score).
export function computePointsDiff(matches) {
  return matches.reduce((s, m) => s + ((m.myScore ?? 0) - (m.oppScore ?? 0)), 0)
}

function aggregateBy(matches, key) {
  const map = new Map()
  for (const m of matches) {
    for (const person of (m[key] ?? [])) {
      if (!person?.id) continue
      const e = map.get(person.id) ?? { id: person.id, name: person.name, games: 0, wins: 0, eloSum: 0, eloN: 0 }
      e.games++
      if (m.won) e.wins++
      if (m.eloDelta != null) { e.eloSum += m.eloDelta; e.eloN++ }
      if (person.name) e.name = person.name
      map.set(person.id, e)
    }
  }
  return [...map.values()].map(e => ({
    id: e.id,
    name: e.name,
    games: e.games,
    wins: e.wins,
    winPct: e.games ? Math.round((e.wins / e.games) * 100) : 0,
    // Avg Elo swing in matches with this person — the "+18 avg ELO" EloSmash shows.
    avgElo: e.eloN ? Math.round(e.eloSum / e.eloN) : null,
  }))
}

// Partnerships (doubles teammates), sorted best win% first then most-played.
export function computePartnerships(matches) {
  return aggregateBy(matches, 'partners')
    .sort((a, b) => b.winPct - a.winPct || b.games - a.games)
}

// Head-to-head vs opponents, sorted most-played first then win%.
export function computeHeadToHead(matches) {
  return aggregateBy(matches, 'opponents')
    .sort((a, b) => b.games - a.games || b.winPct - a.winPct)
}
