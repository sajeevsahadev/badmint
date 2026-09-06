// ─────────────────────────────────────────────────────────────────────────
// Shareable tournament images, drawn on an offscreen canvas.
// Square 1080×1080 cards for social; a portrait 1080×1440 poster with a QR code.
// Each returns a PNG data URL.
// ─────────────────────────────────────────────────────────────────────────
import QRCode from 'qrcode'

function loadImg(src) {
  return new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src })
}
function wrapLines(x, text, maxW) {
  const words = String(text || '').split(/\s+/)
  const lines = []; let line = ''
  for (const w of words) {
    const test = line ? line + ' ' + w : w
    if (x.measureText(test).width > maxW && line) { lines.push(line); line = w } else line = test
  }
  if (line) lines.push(line)
  return lines
}

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

// 📣 Auto-generated registration poster (portrait A4-ish) with a QR code that
// deep-links to the registration page.
export async function tournamentPoster(o) {
  const W = 1080, H = 1440
  const c = document.createElement('canvas'); c.width = W; c.height = H
  const x = c.getContext('2d')

  // Background + soft accent circle (top-right).
  x.fillStyle = '#f6f9fb'; x.fillRect(0, 0, W, H)
  x.fillStyle = 'rgba(16,185,129,0.13)'
  x.beginPath(); x.arc(W - 210, 300, 320, 0, Math.PI * 2); x.fill()
  x.fillStyle = 'rgba(168,85,247,0.08)'
  x.beginPath(); x.arc(W - 120, 120, 180, 0, Math.PI * 2); x.fill()

  // Club presents
  x.textAlign = 'left'; x.textBaseline = 'alphabetic'
  x.fillStyle = '#0891a8'; x.font = `800 26px ${FONT}`
  x.fillText(`${(o.clubName || 'BADMINTON 360').toUpperCase()}  PRESENTS`, 80, 150)

  // Accent bar
  const bar = x.createLinearGradient(80, 0, 300, 0); bar.addColorStop(0, '#00b4d8'); bar.addColorStop(1, '#a855f7')
  x.fillStyle = bar; x.fillRect(80, 178, 96, 8)

  // Title (wrapped, big)
  x.fillStyle = '#0f172a'
  let ty = 300
  x.font = `800 96px ${DISPLAY}`
  const lines = wrapLines(x, o.name || 'Tournament', W - 160)
  for (const ln of lines.slice(0, 3)) { x.fillText(ln, 80, ty); ty += 96 }

  // Doubles + category/skill
  x.fillStyle = '#0f8a5f'; x.font = `800 40px ${DISPLAY}`
  x.fillText('DOUBLES TOURNAMENT', 80, ty + 6); ty += 62
  const tags = [o.category, o.skillLabel].filter(Boolean).join(' · ')
  if (tags) { x.fillStyle = '#334155'; x.font = `700 34px ${FONT}`; x.fillText(tags.toUpperCase(), 80, ty + 4); ty += 54 }

  // Prizes line
  if (o.prizeInfo) {
    x.fillStyle = '#0f172a'; x.font = `700 30px ${FONT}`
    x.fillText('🏆 ' + o.prizeInfo, 80, ty + 24); ty += 54
  }

  // Detail rows (icon chips) — anchored just above the footer band so they
  // never slip under it, whatever the title length.
  const bandY = H - 360
  const rows = [
    ['📅', o.dateLabel],
    o.venue ? ['📍', o.venue + (o.venueAddress ? ' · ' + o.venueAddress : '')] : null,
    o.entryFee ? ['🎟️', 'Entry ' + o.entryFee] : null,
  ].filter(Boolean)
  let ry = bandY - 44 - (rows.length - 1) * 74
  for (const [icon, text] of rows) {
    x.save()
    x.beginPath()
    const cx = 108, cy = ry - 12
    x.fillStyle = 'rgba(16,185,129,0.12)'; x.arc(cx, cy, 30, 0, Math.PI * 2); x.fill()
    x.font = '30px ' + FONT; x.textAlign = 'center'; x.fillStyle = '#0f172a'; x.fillText(icon, cx, cy + 11)
    x.textAlign = 'left'; x.fillStyle = '#1f2937'; x.font = `700 32px ${FONT}`
    const t = String(text)
    x.fillText(x.measureText(t).width > W - 240 ? t.slice(0, 42) + '…' : t, 160, ry)
    x.restore()
    ry += 74
  }

  // Footer band (dark) with the QR code.
  const bg = x.createLinearGradient(0, bandY, W, H); bg.addColorStop(0, '#0b1220'); bg.addColorStop(1, '#0a5b74')
  x.fillStyle = bg; x.fillRect(0, bandY, W, 360)

  // QR (white rounded plate)
  const qrDataUrl = await QRCode.toDataURL(o.registerUrl || 'https://badminton360.app', { width: 260, margin: 1, color: { dark: '#0b1220', light: '#ffffff' } })
  const qrImg = await loadImg(qrDataUrl)
  const qs = 232, qx = 80, qy = bandY + 64
  x.fillStyle = '#fff'; roundRect(x, qx - 16, qy - 16, qs + 32, qs + 32, 20); x.fill()
  x.drawImage(qrImg, qx, qy, qs, qs)

  // Right side text
  const rx = qx + qs + 60
  x.textAlign = 'left'
  x.fillStyle = '#22d3ee'; x.font = `800 30px ${FONT}`; x.fillText('SCAN TO REGISTER', rx, bandY + 96)
  x.fillStyle = '#fff'; x.font = `700 26px ${FONT}`
  x.fillText('or visit', rx, bandY + 140)
  x.fillStyle = '#e2e8f0'; x.font = `700 24px ${FONT}`
  x.fillText((o.registerUrl || '').replace(/^https?:\/\//, ''), rx, bandY + 176)
  if (o.contact) {
    x.fillStyle = '#94a3b8'; x.font = `600 24px ${FONT}`
    x.fillText('📞 ' + o.contact, rx, bandY + 224)
  }
  x.fillStyle = 'rgba(255,255,255,0.55)'; x.font = `600 22px ${FONT}`
  x.fillText('Powered by Badminton 360 · badminton360.app', rx, H - 46)

  return c.toDataURL('image/png')
}

// Trigger a browser download of a data URL. Large data: URLs are blocked by
// some browsers, so convert to a Blob object URL (much more reliable).
export function downloadDataUrl(dataUrl, filename) {
  try {
    const [head, b64] = dataUrl.split(',')
    const mime = (head.match(/data:(.*?)(;|$)/) || [])[1] || 'image/png'
    const bin = atob(b64)
    const arr = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
    const url = URL.createObjectURL(new Blob([arr], { type: mime }))
    const a = document.createElement('a')
    a.href = url; a.download = filename
    document.body.appendChild(a); a.click(); a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 2000)
  } catch {
    // Fallback: open the image in a new tab so the user can save it.
    try { window.open(dataUrl, '_blank') } catch { /* ignore */ }
  }
}
