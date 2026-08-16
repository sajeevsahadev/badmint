// Renders a shareable player "scorecard" PNG (CricHeroes-style) and shares it
// via the Web Share API (as an actual image file) with a download fallback.
// Pure canvas — no external libraries, no CORS taint (avatar loaded with
// crossOrigin='anonymous'; if the host doesn't allow it, we fall back to initials).

function loadImg(url) {
  return new Promise(resolve => {
    if (!url) return resolve(null)
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = url
  })
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

/**
 * @param {Object} d
 * @param {string} d.name
 * @param {string} d.club
 * @param {string} [d.city]
 * @param {string|number} d.rank
 * @param {string|number} d.elo
 * @param {string|number} d.games
 * @param {string|number} d.winPct
 * @param {boolean[]} [d.form]        recent results (true=win), chronological
 * @param {number[]}  [d.eloSeries]   elo history for the sparkline
 * @param {string}    [d.avatarUrl]
 * @param {string}    [d.url]
 * @returns {Promise<Blob>}
 */
export async function renderPlayerCard(d) {
  // Ensure the brand fonts are loaded so the card text isn't drawn in a
  // fallback face on first render.
  try { if (document.fonts?.ready) await document.fonts.ready } catch { /* ignore */ }

  const W = 1080, H = 1350
  const canvas = document.createElement('canvas')
  canvas.width = W; canvas.height = H
  const ctx = canvas.getContext('2d')

  // ── Background: deep neon gradient + glows ──
  const bg = ctx.createLinearGradient(0, 0, W, H)
  bg.addColorStop(0, '#071018'); bg.addColorStop(0.55, '#0d2b3f'); bg.addColorStop(1, '#0a4d5e')
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H)
  const glow = (x, y, r, color) => {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r)
    g.addColorStop(0, color); g.addColorStop(1, 'rgba(0,0,0,0)')
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H)
  }
  glow(160, 200, 420, 'rgba(34,211,238,0.20)')
  glow(940, 1150, 480, 'rgba(168,85,247,0.18)')

  ctx.textAlign = 'center'

  // ── Brand ──
  ctx.font = '700 34px Outfit, system-ui, sans-serif'
  ctx.fillStyle = 'rgba(255,255,255,0.85)'
  ctx.fillText('🏸  BADMINTON 360', W / 2, 90)
  ctx.font = '600 20px Outfit, system-ui, sans-serif'
  ctx.fillStyle = 'rgba(148,163,184,0.9)'
  ctx.fillText('YOUR CLUB · YOUR GAME · ONE APP', W / 2, 126)

  // ── Avatar with neon ring ──
  const cx = W / 2, cy = 330, r = 120
  ctx.save()
  ctx.beginPath(); ctx.arc(cx, cy, r + 8, 0, Math.PI * 2)
  const ring = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r)
  ring.addColorStop(0, '#22d3ee'); ring.addColorStop(1, '#a855f7')
  ctx.strokeStyle = ring; ctx.lineWidth = 8; ctx.stroke()
  ctx.restore()

  const img = await loadImg(d.avatarUrl)
  ctx.save()
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.clip()
  if (img) {
    // cover-fit
    const s = Math.max((2 * r) / img.width, (2 * r) / img.height)
    const iw = img.width * s, ih = img.height * s
    ctx.drawImage(img, cx - iw / 2, cy - ih / 2, iw, ih)
  } else {
    const grd = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r)
    grd.addColorStop(0, '#00b4d8'); grd.addColorStop(1, '#a855f7')
    ctx.fillStyle = grd; ctx.fillRect(cx - r, cy - r, 2 * r, 2 * r)
    ctx.fillStyle = '#fff'; ctx.font = '800 96px Outfit, system-ui, sans-serif'
    const initials = (d.name || '?').trim().split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase()
    ctx.fillText(initials, cx, cy + 34)
  }
  ctx.restore()

  // ── Name + club ──
  ctx.fillStyle = '#fff'; ctx.font = '800 68px "Bricolage Grotesque", Outfit, sans-serif'
  ctx.fillText(d.name || 'Player', W / 2, 560)
  ctx.fillStyle = 'rgba(203,213,225,0.9)'; ctx.font = '500 30px Outfit, sans-serif'
  ctx.fillText([d.club, d.city].filter(Boolean).join('  ·  ') || '—', W / 2, 605)

  // ── Stat tiles ──
  const tiles = [
    { label: 'RANK',  value: d.rank != null ? `#${d.rank}` : '–', color: '#fbbf24' },
    { label: 'ELO',   value: `${d.elo ?? '–'}`,                    color: '#22d3ee' },
    { label: 'GAMES', value: `${d.games ?? 0}`,                    color: '#ffffff' },
    { label: 'WIN %', value: `${d.winPct ?? 0}%`,                  color: '#a855f7' },
  ]
  const tw = 232, th = 150, gap = 20, totalW = tiles.length * tw + (tiles.length - 1) * gap
  let tx = (W - totalW) / 2, ty = 680
  for (const t of tiles) {
    ctx.fillStyle = 'rgba(255,255,255,0.06)'
    roundRect(ctx, tx, ty, tw, th, 24); ctx.fill()
    ctx.strokeStyle = 'rgba(255,255,255,0.10)'; ctx.lineWidth = 1.5; ctx.stroke()
    ctx.fillStyle = t.color; ctx.font = '800 54px Outfit, sans-serif'
    ctx.fillText(t.value, tx + tw / 2, ty + 82)
    ctx.fillStyle = 'rgba(148,163,184,0.95)'; ctx.font = '700 22px Outfit, sans-serif'
    ctx.fillText(t.label, tx + tw / 2, ty + 122)
    tx += tw + gap
  }

  // ── Elo sparkline ──
  const series = (d.eloSeries || []).filter(Number.isFinite)
  const sx = 80, sy = 900, sw = W - 160, sh = 220
  ctx.fillStyle = 'rgba(255,255,255,0.05)'; roundRect(ctx, sx, sy, sw, sh, 28); ctx.fill()
  ctx.textAlign = 'left'
  ctx.fillStyle = 'rgba(148,163,184,0.95)'; ctx.font = '700 22px Outfit, sans-serif'
  ctx.fillText('ELO PROGRESSION', sx + 28, sy + 42)
  ctx.textAlign = 'center'
  if (series.length >= 2) {
    let mn = Math.min(...series), mx = Math.max(...series)
    if (mn === mx) { mn -= 20; mx += 20 }
    const pl = sx + 28, pr = sx + sw - 28, pt = sy + 66, pb = sy + sh - 30
    const px = i => pl + (i / (series.length - 1)) * (pr - pl)
    const py = v => pb - ((v - mn) / (mx - mn)) * (pb - pt)
    // area
    ctx.beginPath(); ctx.moveTo(px(0), pb)
    series.forEach((v, i) => ctx.lineTo(px(i), py(v)))
    ctx.lineTo(px(series.length - 1), pb); ctx.closePath()
    const fill = ctx.createLinearGradient(0, pt, 0, pb)
    fill.addColorStop(0, 'rgba(34,211,238,0.35)'); fill.addColorStop(1, 'rgba(34,211,238,0)')
    ctx.fillStyle = fill; ctx.fill()
    // line
    ctx.beginPath()
    series.forEach((v, i) => (i ? ctx.lineTo(px(i), py(v)) : ctx.moveTo(px(i), py(v))))
    const ls = ctx.createLinearGradient(pl, 0, pr, 0)
    ls.addColorStop(0, '#22d3ee'); ls.addColorStop(1, '#a855f7')
    ctx.strokeStyle = ls; ctx.lineWidth = 4; ctx.lineJoin = 'round'; ctx.stroke()
  } else {
    ctx.fillStyle = 'rgba(148,163,184,0.7)'; ctx.font = '500 24px Outfit, sans-serif'
    ctx.fillText('Play a few matches to see your trend', W / 2, sy + sh / 2 + 20)
  }

  // ── Form dots ──
  const form = (d.form || []).slice(-8)
  if (form.length) {
    ctx.textAlign = 'left'
    ctx.fillStyle = 'rgba(148,163,184,0.95)'; ctx.font = '700 22px Outfit, sans-serif'
    ctx.fillText('RECENT FORM', 80, 1190)
    let dx = 300
    for (const won of form) {
      ctx.beginPath(); ctx.arc(dx, 1183, 14, 0, Math.PI * 2)
      ctx.fillStyle = won ? '#10b981' : '#f43f5e'; ctx.fill()
      dx += 40
    }
  }

  // ── Footer (URL is baked onto the image so it survives even if a share
  //     target drops the caption text) ──
  ctx.textAlign = 'center'
  ctx.fillStyle = '#22d3ee'; ctx.font = '700 26px Outfit, sans-serif'
  ctx.fillText((d.url || 'badminton360.app').replace(/^https?:\/\//, ''), W / 2, 1285)
  ctx.fillStyle = 'rgba(148,163,184,0.8)'; ctx.font = '500 22px Outfit, sans-serif'
  ctx.fillText('View the full profile & live rankings', W / 2, 1320)

  return await new Promise(res => canvas.toBlob(b => res(b), 'image/png', 0.95))
}

/**
 * Share the rendered card as an image. Returns 'shared' | 'downloaded'.
 */
export async function sharePlayerCard(d) {
  const blob = await renderPlayerCard(d)
  const file = new File([blob], 'badminton360-card.png', { type: 'image/png' })
  // Fold the marketing URL INTO the caption text. Many share targets (WhatsApp
  // especially) drop the separate `url` field when a file is attached but keep
  // `text`, so the link rides along as the image caption. The URL is also drawn
  // on the card itself as a last-resort fallback.
  const text =
    `🏸 ${d.name} on Badminton 360 — ${d.rank != null ? '#' + d.rank + ' · ' : ''}${d.elo} Elo · ${d.winPct}% wins.\n` +
    `Free Elo rankings & match tracking for your badminton club: ${d.url}`
  if (typeof navigator !== 'undefined' && navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'Badminton 360', text })
      return 'shared'
    } catch (e) {
      if (e && e.name === 'AbortError') return 'cancelled'
      // fall through to download
    }
  }
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = 'badminton360-card.png'
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 1000)
  return 'downloaded'
}

// Open WhatsApp directly with the marketing message + link (no image). Handy as
// an explicit "Share on WhatsApp" action for desktop or when the user wants the
// clickable link in the chat regardless of image-caption behaviour.
export function whatsappShareUrl(d) {
  const text =
    `🏸 ${d.name} on Badminton 360 — ${d.rank != null ? '#' + d.rank + ' · ' : ''}${d.elo} Elo · ${d.winPct}% wins.\n` +
    `Free Elo rankings & match tracking for your badminton club: ${d.url}`
  return `https://wa.me/?text=${encodeURIComponent(text)}`
}
