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
// Only ONE named person is needed to analyse a video; the rest may stay empty (no report for them).
export function anySlotComplete(slots) {
  return (slots || []).some(slotComplete)
}

// Convert tagging slots into the payload set_video_tags() expects. Empty slots are left out.
export function buildTags(slots) {
  return (slots || []).filter(slotComplete).map(s => ({
    track_id:   s.track_id || null,
    player_id:  s.assign && s.assign.startsWith('p:') ? s.assign.slice(2) : null,
    label:      s.assign === 'label' ? (s.label || '').trim() : null,
    court_side: s.court_side || null,
    is_subject: !!s.is_subject,
  }))
}

// Human name for an analysis version, e.g. "Version 2 · 7 Nov 2026, 11:16 (latest)".
export function versionLabel(run, latestVersion, locale) {
  if (!run) return ''
  let s = `Version ${run.version}`
  const d = run.created_at ? new Date(run.created_at) : null
  if (d && !isNaN(d.getTime())) {
    s += ` · ${d.toLocaleString(locale, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}`
  }
  if (latestVersion != null && run.version === latestVersion) s += ' (latest)'
  if (run.is_mock) s += ' · Sample'
  return s
}

// R2 key of a player's photo: the tag's own photo, else its linked track's, else the track at the
// same starting court position.
export function tagThumbPath(tag, tracks = []) {
  if (!tag) return null
  if (tag.thumb_path) return tag.thumb_path
  const byId = tag.track_id ? tracks.find(t => t.id === tag.track_id) : null
  if (byId?.thumb_path) return byId.thumb_path
  const bySide = tag.court_side ? tracks.find(t => t.court_side === tag.court_side && t.thumb_path) : null
  return bySide?.thumb_path || null
}

// Display name for a tag: roster nickname if linked, else the typed label.
export function resolveTagName(tag, nameMap = {}) {
  if (!tag) return 'Player'
  if (tag.player_id && nameMap[tag.player_id]) return nameMap[tag.player_id]
  return tag.label || 'Player'
}

// The automatic titles given at upload/record time ("Uploaded match · 14/11/2026"). A title the
// user typed themselves is anything else and is never replaced.
export function isDefaultTitle(title) {
  return !title || !String(title).trim() || /^(Uploaded match|Match video)\s*·/.test(String(title).trim())
}

// List/heading name for a video: the tagged players' names ("Sajeev & Aravind vs Vishnu & Mathews"),
// near side first. Falls back to the stored title when nobody is tagged or the title was typed by hand.
export function videoTitle(video, tags = [], nameMap = {}) {
  const stored = video?.title || 'Match video'
  if (!isDefaultTitle(video?.title)) return stored
  const named = (tags || [])
    .map(t => ({ side: String(t.court_side || ''), name: (t.player_id && nameMap[t.player_id]) || (t.label || '').trim() }))
    .filter(t => t.name)
    .sort((a, b) => a.side.localeCompare(b.side))
  if (!named.length) return stored
  const team = (pfx) => named.filter(t => t.side.startsWith(pfx)).map(t => t.name).join(' & ')
  const near = team('near'), far = team('far')
  if (near && far) return `${near} vs ${far}`
  return near || far || named.map(t => t.name).join(' & ')
}
