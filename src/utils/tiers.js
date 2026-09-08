// Elo rank tiers — a presentation layer over a player's raw Elo, à la EloSmash's
// Bronze→Diamond badges. Pure function, no state; used on PlayerProfile, the
// Dashboard mini-board and the Scoreboard podium so a rating gets an identity,
// not just a number. Bands are tunable here in one place.
//
// Colours use the app's existing token hexes so chips sit naturally in the
// light theme (see style.css design system).

export const TIERS = [
  { key: 'diamond',  label: 'Diamond',  emoji: '💎', min: 1650, color: '#a855f7' }, // violet
  { key: 'platinum', label: 'Platinum', emoji: '🔵', min: 1450, color: '#0891b2' }, // cyan-700
  { key: 'gold',     label: 'Gold',     emoji: '🟡', min: 1250, color: '#d97706' }, // amber-600
  { key: 'silver',   label: 'Silver',   emoji: '⚪', min: 1100, color: '#64748b' }, // slate-500
  { key: 'bronze',   label: 'Bronze',   emoji: '🟤', min: 0,    color: '#b45309' }, // amber-700
]

// Highest tier whose `min` the Elo meets. Always resolves (bronze has min 0).
export function tierFor(elo) {
  const e = Number.isFinite(elo) ? elo : 0
  return TIERS.find(t => e >= t.min) ?? TIERS[TIERS.length - 1]
}

// Elo needed to reach the next tier up, or null if already Diamond.
// Handy for "42 Elo to Platinum" style nudges.
export function nextTier(elo) {
  const cur = tierFor(elo)
  const idx = TIERS.findIndex(t => t.key === cur.key)
  if (idx <= 0) return null            // already top tier
  const up = TIERS[idx - 1]
  return { ...up, needed: Math.max(0, up.min - (Number.isFinite(elo) ? elo : 0)) }
}
