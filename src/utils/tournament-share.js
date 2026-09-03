// ─────────────────────────────────────────────────────────────────────────
// Shareable tournament images, drawn on an offscreen canvas (no dependencies).
// Square 1080×1080 so they look right on WhatsApp / Instagram / status.
// Each returns a PNG data URL.
// ─────────────────────────────────────────────────────────────────────────

const W = 1080

function baseCanvas() {
  const c = document.createElement('canvas')
  c.width = W; c.height = W
  const x = c.getContext('2d')
  // brand gradient ground (matches the public hero)
  const g = x.createLinearGradient(0, 0, W, W)
  g.addColorStop(0, '#0b1220'); g.addColorStop(0.55, '#0f2a4a'); g.addColorStop(1, '#0a5b74')
  x.fillStyle = g; x.fillRect(0, 0, W, W)
  // glow orbs
  glow(x, W * 0.2, W * 0.28, 360, 'rgba(34,211,238,0.28)')
  glow(x, W * 0.82, W * 0.18, 320, 'rgba(168,85,247,0.26)')
  glow(x, W * 0.85, W * 0.9, 340, 'rgba(251,191,36,0.14)')
  return { c, x }
}
function glow(x, cx, cy, r, color) {
  const rg = x.createRadialGradient(cx, cy, 0, cx, cy, r)
  rg.addColorStop(0, color); rg.addColorStop(1, 'rgba(0,0,0,0)')
  x.fillStyle = rg; x.beginPath(); x.arc(cx, cy, r, 0, Math.PI * 2); x.fill()
}
function roundRect(x, X, Y, w, h, r) {
  x.beginPath(); x.moveTo(X + r, Y)
  x.arcTo(X + w, Y, X + w, Y + h, r); x.arcTo(X + w, Y + h, X, Y + h, r)
  x.arcTo(X, Y + h, X, Y, r); x.arcTo(X, Y, X + w, Y, r); x.closePath()
}
const FONT = "'Outfit', system-ui, -apple-system, Segoe UI, Roboto, sans-serif"
const DISPLAY = "'Bricolage Grotesque', " + FONT
// Shrink font until the text fits maxW.
function fitText(x, text, maxW, start, weight, family) {
  let size = start
  do { x.font = `${weight} ${size}px ${family}`; size -= 4 }
  while (x.measureText(text).width > maxW && size > 22)
  return x.font
}
function center(x, text, y, maxW = W - 140) {
  x.textAlign = 'center'
  x.fillText(text, W / 2, y, maxW)
}

// 🏆 Champion / results card — used once a tournament is completed.
export function championCard({ name, clubName, winner, runnerUp, third, dateLabel }) {
  const { c, x } = baseCanvas()
  x.textAlign = 'center'; x.textBaseline = 'alphabetic'

  x.fillStyle = 'rgba(255,255,255,0.75)'
  x.font = `600 30px ${FONT}`
  center(x, '🏸  CHAMPIONS CROWNED', 150)

  x.fillStyle = '#fff'
  fitText(x, name, W - 150, 74, 800, DISPLAY)
  center(x, name, 250)

  x.fillStyle = 'rgba(255,255,255,0.6)'
  x.font = `500 30px ${FONT}`
  center(x, clubName + (dateLabel ? '  ·  ' + dateLabel : ''), 300)

  // trophy
  x.font = '150px ' + FONT
  center(x, '🏆', 470)

  // winner plate
  const plateW = W - 200
  x.save()
  roundRect(x, 100, 520, plateW, 150, 28)
  const pg = x.createLinearGradient(100, 520, 100 + plateW, 670)
  pg.addColorStop(0, 'rgba(251,191,36,0.95)'); pg.addColorStop(1, 'rgba(245,158,11,0.95)')
  x.fillStyle = pg; x.fill()
  x.fillStyle = '#3b2600'
  x.font = `700 26px ${FONT}`; center(x, '🥇  CHAMPIONS', 566)
  x.fillStyle = '#1a1200'
  fitText(x, winner || 'Champions', plateW - 70, 56, 800, DISPLAY)
  center(x, winner || 'Champions', 636, plateW - 70)
  x.restore()

  let y = 740
  if (runnerUp) { y = medalRow(x, '🥈', 'Runner-up', runnerUp, y) }
  if (third)    { y = medalRow(x, '🥉', 'Third place', third, y) }

  footer(x)
  return c.toDataURL('image/png')
}

function medalRow(x, medal, label, team, y) {
  const w = W - 200
  x.save()
  roundRect(x, 100, y, w, 96, 22)
  x.fillStyle = 'rgba(255,255,255,0.08)'; x.fill()
  x.strokeStyle = 'rgba(255,255,255,0.12)'; x.lineWidth = 1.5; x.stroke()
  x.textAlign = 'left'
  x.font = '44px ' + FONT; x.fillText(medal, 128, y + 62)
  x.fillStyle = 'rgba(255,255,255,0.5)'; x.font = `600 22px ${FONT}`; x.fillText(label.toUpperCase(), 200, y + 44)
  x.fillStyle = '#fff'; x.font = `700 34px ${DISPLAY}`; x.fillText(team, 200, y + 78, w - 130)
  x.restore()
  return y + 116
}

// 📣 Announcement card — used to promote an open / upcoming tournament.
export function announcementCard({ name, clubName, dateLabel, venue, entryFee, shareUrl, statusText }) {
  const { c, x } = baseCanvas()
  x.textBaseline = 'alphabetic'

  x.fillStyle = '#22d3ee'; x.font = `700 32px ${FONT}`
  center(x, '🏸  ' + (statusText || 'TOURNAMENT'), 170)

  x.fillStyle = '#fff'
  fitText(x, name, W - 150, 92, 800, DISPLAY)
  center(x, name, 300)

  x.fillStyle = 'rgba(255,255,255,0.7)'; x.font = `500 36px ${FONT}`
  center(x, clubName, 360)

  const rows = [
    ['📅', dateLabel],
    venue ? ['📍', venue] : null,
    entryFee ? ['🎟️', 'Entry ' + entryFee] : null,
  ].filter(Boolean)
  let y = 470
  for (const [icon, text] of rows) {
    const w = W - 240
    x.save()
    roundRect(x, 120, y, w, 92, 20)
    x.fillStyle = 'rgba(255,255,255,0.07)'; x.fill()
    x.textAlign = 'left'
    x.font = '40px ' + FONT; x.fillText(icon, 150, y + 60)
    x.fillStyle = '#fff'; x.font = `600 36px ${FONT}`; x.fillText(text, 220, y + 60, w - 120)
    x.restore()
    y += 116
  }

  // CTA
  x.save()
  const bw = W - 240
  roundRect(x, 120, y + 10, bw, 110, 26)
  const bg = x.createLinearGradient(120, y, 120 + bw, y + 110)
  bg.addColorStop(0, '#00e5ff'); bg.addColorStop(1, '#a855f7')
  x.fillStyle = bg; x.fill()
  x.fillStyle = '#04121a'; x.textAlign = 'center'
  x.font = `800 40px ${DISPLAY}`; x.fillText('Register / Follow live', W / 2, y + 78, bw - 60)
  x.restore()

  x.fillStyle = 'rgba(255,255,255,0.8)'; x.font = `600 30px ${FONT}`
  center(x, (shareUrl || 'badminton360.app').replace(/^https?:\/\//, ''), y + 180)

  footer(x)
  return c.toDataURL('image/png')
}

function footer(x) {
  x.textAlign = 'center'
  x.fillStyle = 'rgba(255,255,255,0.45)'
  x.font = `600 26px ${FONT}`
  x.fillText('Powered by Badminton 360  ·  badminton360.app', W / 2, W - 54)
}

// Trigger a browser download of a data URL.
export function downloadDataUrl(dataUrl, filename) {
  const a = document.createElement('a')
  a.href = dataUrl; a.download = filename
  document.body.appendChild(a); a.click(); a.remove()
}
