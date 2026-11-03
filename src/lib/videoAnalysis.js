// Pure helpers for the AI analysis flow (player mapping + court-swap geometry).
// Kept framework-free so they're unit-tested and reused by the Phase B worker logic.

// Expected on-court positions for a game type.
export function expectedSides(gameType) {
  return gameType === 'doubles'
    ? ['near_left', 'near_right', 'far_left', 'far_right']
    : ['near', 'far']
}

// Flip a court side as seen from a fixed camera when players change ends:
// near<->far and left<->right (so near_left becomes far_right).
const SWAP = { near: 'far', far: 'near', left: 'right', right: 'left' }
export function flipSide(side) {
  if (!side) return side
  return String(side).split('_').map(tok => SWAP[tok] || tok).join('_')
}

// Where a player who STARTED on baseSide actually is at time t, given end-swap events.
// An odd number of swaps before t means they're on the flipped side.
export function courtSideAt(baseSide, events, tSeconds) {
  const n = (events || []).filter(e => Number(e.at_s) <= Number(tSeconds)).length
  return n % 2 === 1 ? flipSide(baseSide) : baseSide
}

// A tagging slot is complete when it maps to a roster player or a typed label.
export function slotComplete(s) {
  return !!((s.assign && s.assign.startsWith('p:')) || (s.assign === 'label' && (s.label || '').trim()))
}
export function slotsComplete(slots) {
  return (slots || []).length > 0 && slots.every(slotComplete)
}

// Convert tagging slots into the payload set_video_tags() expects.
export function buildTags(slots) {
  return (slots || []).map(s => ({
    track_id:   s.track_id || null,
    player_id:  s.assign && s.assign.startsWith('p:') ? s.assign.slice(2) : null,
    label:      s.assign === 'label' ? (s.label || '').trim() : null,
    court_side: s.court_side || null,
    is_subject: !!s.is_subject,
  }))
}

// Display name for a tag: roster nickname if linked, else the typed label.
export function resolveTagName(tag, nameMap = {}) {
  if (!tag) return 'Player'
  if (tag.player_id && nameMap[tag.player_id]) return nameMap[tag.player_id]
  return tag.label || 'Player'
}
