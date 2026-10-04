// Branded 1200x630 og:image covers for the "3×15 scoring" blog series.
// Same house style as generate-blog-covers.js, with a consistent SCORING tag.
//   node scripts/generate-3x15-covers.js
import sharp from 'sharp'
import { mkdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, resolve } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUT = resolve(__dirname, '../public/blog')
mkdirSync(OUT, { recursive: true })

const ACCENT = '#00b4d8'
const TAG = 'SCORING'

// slug → concise cover-art title (kept short so it fits cleanly).
const POSTS = [
  ['badminton-3x15-scoring-system', "Badminton's New 3×15 Scoring System"],
  ['badminton-3x15-vs-3x21', '3×15 vs 3×21: How It Works'],
  ['badminton-scoring-singles-3x15', 'Singles Scoring Under 3×15'],
  ['badminton-scoring-doubles-3x15', 'Doubles Scoring Under 3×15'],
  ['how-to-keep-score-badminton-3x15', 'How to Keep Score (3×15)'],
  ['badminton-serving-rules-3x15', 'Serving Rules in 3×15'],
  ['badminton-3x15-tactics-fast-starts', 'Why 3×15 Rewards Fast Starts'],
  ['badminton-3x15-club-score-tracking', '3×15 & Your Club'],
  ['badminton-deuce-golden-point-3x15', 'Deuce & the Golden Point'],
  ['badminton-3x15-coaching', '3×15 for Coaches'],
  ['badminton-3x15-veterans', 'Veterans vs 3×15'],
  ['badminton-3x15-around-the-world', '3×15 Around the World'],
  ['badminton-club-ready-3x15-2027', 'Get Ready for 3×15'],
  ['badminton-3x15-goes-global-2027', "It's Here: 3×15 Goes Global"],
]

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

function wrap(text, maxChars) {
  const words = text.split(/\s+/)
  const lines = []
  let line = ''
  for (const w of words) {
    if ((line + ' ' + w).trim().length > maxChars && line) { lines.push(line); line = w }
    else line = (line + ' ' + w).trim()
  }
  if (line) lines.push(line)
  return lines
}

function shuttle(cx, cy, color) {
  const feathers = []
  for (let i = -4; i <= 4; i++) {
    const ang = (-90 + i * 12) * Math.PI / 180
    const x2 = cx + Math.cos(ang) * 230
    const y2 = cy + Math.sin(ang) * 230
    feathers.push(`<line x1="${cx}" y1="${cy}" x2="${x2.toFixed(0)}" y2="${y2.toFixed(0)}" stroke="${color}" stroke-width="7" stroke-linecap="round" opacity="0.5"/>`)
  }
  return `${feathers.join('')}<circle cx="${cx}" cy="${cy}" r="26" fill="${color}" opacity="0.85"/>`
}

async function render(slug, title) {
  const long = title.length > 46
  const fontSize = long ? 62 : 74
  const maxChars = long ? 26 : 22
  const lines = wrap(title, maxChars).slice(0, 4)
  const lineH = fontSize * 1.18
  const blockH = lines.length * lineH
  const startY = 315 - blockH / 2 + fontSize

  const titleSvg = lines.map((ln, i) =>
    `<text x="90" y="${(startY + i * lineH).toFixed(0)}" font-family="Arial, Helvetica, sans-serif" font-size="${fontSize}" font-weight="800" fill="#ffffff">${esc(ln)}</text>`
  ).join('')

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#071018"/><stop offset="0.55" stop-color="#0d2b3f"/><stop offset="1" stop-color="#0a4d5e"/>
    </linearGradient>
    <radialGradient id="g1" cx="0.85" cy="0.2" r="0.5">
      <stop offset="0" stop-color="${ACCENT}" stop-opacity="0.28"/><stop offset="1" stop-color="${ACCENT}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="g2" cx="0.1" cy="0.95" r="0.5">
      <stop offset="0" stop-color="#a855f7" stop-opacity="0.22"/><stop offset="1" stop-color="#a855f7" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="630" fill="url(#g1)"/>
  <rect width="1200" height="630" fill="url(#g2)"/>
  <g transform="translate(980,300)">${shuttle(0, 0, ACCENT)}</g>
  <text x="90" y="86" font-family="Arial, Helvetica, sans-serif" font-size="30" font-weight="800" letter-spacing="2" fill="#e2e8f0">BADMINTON 360</text>
  <rect x="90" y="112" rx="14" ry="14" width="${TAG.length * 17 + 40}" height="40" fill="${ACCENT}" opacity="0.16"/>
  <text x="${90 + (TAG.length * 17 + 40) / 2}" y="139" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="22" font-weight="800" letter-spacing="2" fill="${ACCENT}">${TAG}</text>
  ${titleSvg}
  <text x="90" y="575" font-family="Arial, Helvetica, sans-serif" font-size="26" font-weight="700" fill="${ACCENT}">badminton360.app</text>
</svg>`

  await sharp(Buffer.from(svg)).png({ quality: 90 }).toFile(resolve(OUT, `${slug}.png`))
  process.stdout.write('.')
}

const run = async () => {
  for (const [slug, title] of POSTS) await render(slug, title)
  console.log(`\nGenerated ${POSTS.length} 3×15 covers → public/blog/`)
}
run()
