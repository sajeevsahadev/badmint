// Branded 1200x630 og:image covers + two infographics for the badminton-coaching
// blog cluster. SVG -> PNG via sharp. Filenames use the post slug (SEO-friendly).
//   node scripts/generate-coaching-covers.js
import sharp from 'sharp'
import { mkdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, resolve } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUT = resolve(__dirname, '../public/blog')
mkdirSync(OUT, { recursive: true })

const POSTS = [
  ['badminton-coaching-uae-guide', 'Badminton Coaching in the UAE'],
  ['bwf-level-1-badminton-coaching', 'BWF Level 1: Foundation Coaching'],
  ['bwf-level-2-badminton-coaching', 'BWF Level 2: Advanced Coaching'],
  ['bwf-level-3-badminton-coaching', 'BWF Level 3: High-Performance Coaching'],
  ['badminton-coaching-dubai', 'Badminton Coaching in Dubai'],
  ['badminton-coaching-sharjah', 'Badminton Coaching in Sharjah'],
  ['badminton-coaching-abu-dhabi', 'Badminton Coaching in Abu Dhabi'],
  ['kids-badminton-coaching-uae', "Kids' Badminton Coaching in the UAE"],
]

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

function tagFor(slug) {
  const has = (...w) => w.some(x => slug.includes(x))
  if (has('dubai')) return ['DUBAI', '#22d3ee']
  if (has('sharjah')) return ['SHARJAH', '#22d3ee']
  if (has('abu-dhabi')) return ['ABU DHABI', '#22d3ee']
  if (has('kids')) return ['KIDS', '#34d399']
  if (has('level-1')) return ['LEVEL 1 · FOUNDATION', '#34d399']
  if (has('level-2')) return ['LEVEL 2 · ADVANCED', '#fbbf24']
  if (has('level-3')) return ['LEVEL 3 · HIGH PERFORMANCE', '#f97316']
  return ['COACHING · UAE', '#a855f7']
}

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
  const [tag, accent] = tagFor(slug)
  const long = title.length > 40
  const fontSize = long ? 62 : 74
  const maxChars = long ? 24 : 20
  const lines = wrap(title, maxChars).slice(0, 4)
  const lineH = fontSize * 1.18
  const blockH = lines.length * lineH
  const startY = 320 - blockH / 2 + fontSize

  const titleSvg = lines.map((ln, i) =>
    `<text x="90" y="${(startY + i * lineH).toFixed(0)}" font-family="Arial, Helvetica, sans-serif" font-size="${fontSize}" font-weight="800" fill="#ffffff">${esc(ln)}</text>`
  ).join('')

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#071018"/><stop offset="0.55" stop-color="#0d2b3f"/><stop offset="1" stop-color="#0a4d5e"/>
    </linearGradient>
    <radialGradient id="g1" cx="0.85" cy="0.2" r="0.5">
      <stop offset="0" stop-color="${accent}" stop-opacity="0.28"/><stop offset="1" stop-color="${accent}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="g2" cx="0.1" cy="0.95" r="0.5">
      <stop offset="0" stop-color="#a855f7" stop-opacity="0.22"/><stop offset="1" stop-color="#a855f7" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="630" fill="url(#g1)"/>
  <rect width="1200" height="630" fill="url(#g2)"/>
  <g transform="translate(980,300)">${shuttle(0, 0, accent)}</g>
  <text x="90" y="86" font-family="Arial, Helvetica, sans-serif" font-size="30" font-weight="800" letter-spacing="2" fill="#e2e8f0">BADMINTON 360</text>
  <rect x="90" y="112" rx="14" ry="14" width="${tag.length * 15 + 40}" height="40" fill="${accent}" opacity="0.16"/>
  <text x="${90 + (tag.length * 15 + 40) / 2}" y="139" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="20" font-weight="800" letter-spacing="2" fill="${accent}">${tag}</text>
  ${titleSvg}
  <text x="90" y="575" font-family="Arial, Helvetica, sans-serif" font-size="26" font-weight="700" fill="${accent}">badminton360.app/blog</text>
</svg>`

  await sharp(Buffer.from(svg)).png({ quality: 90 }).toFile(resolve(OUT, `${slug}.png`))
  process.stdout.write('.')
}

// ── Infographic 1: the BWF level pathway (L1 -> L2 -> L3) ──
async function renderPathway() {
  const card = (x, color, tag, title, sub) => `
    <rect x="${x}" y="220" rx="20" ry="20" width="300" height="230" fill="${color}" opacity="0.12" stroke="${color}" stroke-opacity="0.4"/>
    <text x="${x + 26}" y="270" font-family="Arial" font-size="22" font-weight="800" letter-spacing="1.5" fill="${color}">${tag}</text>
    <text x="${x + 26}" y="316" font-family="Arial" font-size="30" font-weight="800" fill="#ffffff">${title}</text>
    <text x="${x + 26}" y="360" font-family="Arial" font-size="19" fill="#cbd5e1">${sub}</text>`
  const arrow = x => `<text x="${x}" y="350" font-family="Arial" font-size="46" font-weight="800" fill="#64748b">→</text>`
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#071018"/><stop offset="1" stop-color="#0a3a4a"/></linearGradient></defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <text x="600" y="110" text-anchor="middle" font-family="Arial" font-size="42" font-weight="800" fill="#ffffff">The BWF Coaching Pathway</text>
  <text x="600" y="156" text-anchor="middle" font-family="Arial" font-size="22" fill="#94a3b8">Foundation → Advanced → High Performance</text>
  ${card(70, '#34d399', 'LEVEL 1', 'Foundation', 'Beginners &amp; groups')}
  ${arrow(388)}
  ${card(450, '#fbbf24', 'LEVEL 2', 'Advanced', 'Club &amp; regional')}
  ${arrow(768)}
  ${card(830, '#f97316', 'LEVEL 3', 'High Perf.', 'Elite &amp; national')}
  <text x="600" y="560" text-anchor="middle" font-family="Arial" font-size="24" font-weight="700" fill="#22d3ee">badminton360.app/blog</text>
</svg>`
  await sharp(Buffer.from(svg)).png({ quality: 90 }).toFile(resolve(OUT, 'bwf-coaching-levels-pathway.png'))
  process.stdout.write('.')
}

// ── Infographic 2: ideal starting age bands ──
async function renderAges() {
  const band = (y, color, age, label) => `
    <rect x="90" y="${y}" rx="16" ry="16" width="1020" height="70" fill="${color}" opacity="0.12" stroke="${color}" stroke-opacity="0.35"/>
    <text x="120" y="${y + 46}" font-family="Arial" font-size="30" font-weight="800" fill="${color}">${age}</text>
    <text x="340" y="${y + 46}" font-family="Arial" font-size="26" fill="#e2e8f0">${label}</text>`
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#071018"/><stop offset="1" stop-color="#0a3a4a"/></linearGradient></defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <text x="90" y="96" font-family="Arial" font-size="40" font-weight="800" fill="#ffffff">Best Age to Start Badminton</text>
  ${band(150, '#34d399', '5–7', 'Fun, movement &amp; racket familiarity')}
  ${band(240, '#22d3ee', '8–10', 'Foundation strokes &amp; footwork')}
  ${band(330, '#fbbf24', '11–13', 'Tactics, match play &amp; competition')}
  ${band(420, '#f97316', '14+', 'Advanced training &amp; high performance')}
  <text x="90" y="560" font-family="Arial" font-size="24" font-weight="700" fill="#22d3ee">badminton360.app/blog</text>
</svg>`
  await sharp(Buffer.from(svg)).png({ quality: 90 }).toFile(resolve(OUT, 'badminton-starting-age-guide.png'))
  process.stdout.write('.')
}

const run = async () => {
  for (const [slug, title] of POSTS) await render(slug, title)
  await renderPathway()
  await renderAges()
  console.log(`\nGenerated ${POSTS.length} covers + 2 infographics -> public/blog/`)
}
run()
