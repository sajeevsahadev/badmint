// Generate branded 1200x630 og:image cover art for blog posts that lack one.
// SVG → PNG via sharp. Filenames use the post slug (keyword-rich = SEO-friendly).
//   node scripts/generate-blog-covers.js
import sharp from 'sharp'
import { mkdirSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, resolve } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUT = resolve(__dirname, '../public/blog')
mkdirSync(OUT, { recursive: true })

// Posts to render (slug → filename, title → artwork text).
const POSTS = [
  ['badminton-clear-shot', "The Badminton Clear: The Most Important Shot You're Neglecting"],
  ['badminton-drop-shot', 'The Badminton Drop Shot: Slow, Fast and Sliced'],
  ['where-to-play-badminton-dubai', 'Where to Play Badminton in Dubai: A 2026 Guide to Courts & Clubs'],
  ['choose-badminton-partner', 'How to Choose a Badminton Doubles Partner'],
  ['find-badminton-club-uae', 'How to Find a Badminton Club in the UAE'],
  ['feather-vs-nylon-shuttlecocks', 'Feather vs Nylon Shuttlecocks: Which Should You Use?'],
  ['badminton-court-booking-dubai', 'Badminton Court Booking in Dubai: Costs, Peak Hours and Tips'],
  ['badminton-defence-survive-smash', 'Badminton Defence: How to Survive a Smash'],
  ['start-badminton-group-dubai', 'How to Start a Weekend Badminton Group in Dubai'],
  ['badminton-rules-players-get-wrong', 'Badminton Rules Every Player Gets Wrong'],
  ['badminton-abu-dhabi-sharjah', 'Badminton in Abu Dhabi and Sharjah'],
  ['how-to-return-serve-badminton', 'How to Return Serve in Badminton'],
  ['dubai-fitness-challenge-badminton', 'Dubai Fitness Challenge: How to Take Part with Badminton'],
  ['fair-badminton-ranking-uae-club', 'How to Run a Fair Badminton Ranking for Your UAE Club'],
  ['build-badminton-stamina', 'Building Badminton Stamina for Long Rallies'],
  ['why-badminton-perfect-fitness-challenge-sport', 'Why Badminton Is the Perfect Dubai Fitness Challenge Sport'],
  ['indoor-badminton-uae-heat', 'Indoor Badminton in the UAE: Playing Year-Round'],
  ['common-badminton-mistakes', 'Common Badminton Mistakes (and How to Fix Them)'],
  ['badminton-facilities-dubai-stay-fit', 'Badminton Facilities in Dubai: Where to Get Your 30 Minutes In'],
  ['badminton-tournament-dubai', 'How to Organise a Small Badminton Tournament in Dubai'],
  ['30x30-badminton-active-minutes', '30x30 with a Racket: Hit Your 30 Active Minutes'],
  ['badminton-etiquette-club', 'Badminton Etiquette: The Unwritten Rules of the Club'],
  ['dubai-fitness-challenge-city-moving', 'How the Dubai Fitness Challenge Gets a Whole City Moving'],
  ['badminton-beginners-dubai-first-30-days', 'Badminton for Beginners in Dubai: Your First 30 Days'],
  ['best-badminton-shoes-guide', 'Best Badminton Shoes: What to Look For'],
  ['family-fitness-challenge-badminton', 'Family Fitness in the Dubai Fitness Challenge'],
  ['mixed-doubles-badminton-tactics', 'Mixed Doubles Badminton: Roles, Rotation and Tactics'],
  ['badminton-string-tension-explained', 'Badminton String Tension Explained'],
  ['start-badminton-fitness-challenge-beginner', "Beginner's Guide: Start Badminton During the Fitness Challenge"],
  ['improve-badminton-smash', 'How to Improve Your Badminton Smash'],
  ['corporate-badminton-uae-league', 'Corporate Badminton in the UAE: Start a Workplace League'],
  ['keep-momentum-after-fitness-challenge', 'Keep the Momentum: A Lasting Badminton Habit'],
  ['badminton-warm-up-injury-prevention', 'Badminton Warm-Up and Injury Prevention'],
  ['badminton-deception-feints', 'Reading Your Opponent: Badminton Deception and Feints'],
  ['kids-badminton-dubai', "Kids' Badminton in Dubai: Getting Children Started"],
  ['singles-vs-doubles-badminton', 'Singles vs Doubles Badminton: Which Should You Play?'],
  ['badminton-grip-techniques', 'Badminton Grip Techniques: Forehand, Backhand and More'],
  ['winter-badminton-uae-best-season', 'Winter Badminton in the UAE: The Best Season to Play'],
  ['practise-badminton-alone-solo-drills', 'How to Practise Badminton Alone: Solo Drills'],
  ['badminton-ladder-league-club', 'How to Build a Badminton Ladder or League'],
  ['badminton-net-play-front-court', 'Badminton Net Play: Winning the Front Court'],
  ['badminton-gift-guide-2026', 'Badminton Gift Guide 2026: Rackets, Shoes and Gear'],
  ['badminton-goals-2027', 'New Year, New Game: Set Your Badminton Goals for 2027'],
  ['badminton-club-year-in-review', "Your Badminton Club's Year in Review"],
]

const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')

// Category + accent colour from the slug.
function tagFor(slug) {
  const has = (...w) => w.some(x => slug.includes(x))
  if (has('dubai')) return ['DUBAI', '#22d3ee']
  if (has('uae', 'abu-dhabi', 'sharjah')) return ['UAE', '#22d3ee']
  if (has('fitness', '30x30', 'stamina', 'warm-up', 'momentum', 'active')) return ['FITNESS', '#34d399']
  if (has('club', 'ladder', 'league', 'etiquette', 'ranking', 'tournament', 'corporate', 'year-in-review')) return ['CLUB', '#fbbf24']
  if (has('shoe', 'shuttlecock', 'string', 'gift', 'racket', 'gear')) return ['GEAR', '#a855f7']
  return ['TECHNIQUE', '#a855f7']
}

// Greedy word-wrap to a max chars/line budget.
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

// A simple decorative shuttlecock (feathers fanning from a cork), tinted.
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
  <rect x="90" y="112" rx="14" ry="14" width="${tag.length * 17 + 40}" height="40" fill="${accent}" opacity="0.16"/>
  <text x="${90 + (tag.length * 17 + 40) / 2}" y="139" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="22" font-weight="800" letter-spacing="2" fill="${accent}">${tag}</text>
  ${titleSvg}
  <text x="90" y="575" font-family="Arial, Helvetica, sans-serif" font-size="26" font-weight="700" fill="${accent}">badminton360.app</text>
</svg>`

  await sharp(Buffer.from(svg)).png({ quality: 90 }).toFile(resolve(OUT, `${slug}.png`))
  process.stdout.write('.')
}

const run = async () => {
  for (const [slug, title] of POSTS) await render(slug, title)
  console.log(`\nGenerated ${POSTS.length} covers → public/blog/`)
}
run()
