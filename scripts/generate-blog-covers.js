// Generates cover images (1200×630) for additional blog posts.
import sharp from 'sharp'
import { mkdirSync } from 'fs'

mkdirSync('public/blog', { recursive: true })

const COVERS = [
  { file: 'badminton-scoring-rules.png',   l1: 'Badminton Scoring', l2: 'Rules Explained',   sub: 'Rally scoring to 21, in plain English', c1: '#a3e635', c2: '#22d3ee' },
  { file: 'best-badminton-apps-2026.png',  l1: 'The Best Badminton', l2: 'Apps in 2026',      sub: 'Track scores, rank players, run your club', c1: '#c084fc', c2: '#22d3ee' },
  { file: 'how-elo-ranking-works.png',     l1: 'How Elo Ranking',   l2: 'Works in Badminton', sub: 'Why it beats just counting wins',       c1: '#fbbf24', c2: '#22d3ee' },
]

const svg = ({ l1, l2, sub, c1, c2 }) => `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0b1220"/><stop offset="0.55" stop-color="#0f2a4a"/><stop offset="1" stop-color="#0a5b74"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.8" cy="0.2" r="0.6">
      <stop offset="0" stop-color="${c2}" stop-opacity="0.35"/><stop offset="1" stop-color="${c2}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="shut" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${c1}"/><stop offset="1" stop-color="${c2}"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="630" fill="url(#glow)"/>
  <g transform="translate(880,150) scale(11)" fill="none" stroke="url(#shut)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" opacity="0.9">
    <circle cx="0" cy="16" r="4.5" fill="url(#shut)" stroke="none"/>
    <path d="M0 12 L-14 -18 M0 12 L-7 -20 M0 12 L0 -21 M0 12 L7 -20 M0 12 L14 -18"/>
    <path d="M-14 -18 Q0 -11 14 -18"/><path d="M-9 -3 Q0 1 9 -3"/>
  </g>
  <text x="80" y="150" font-family="Arial, sans-serif" font-size="24" font-weight="700" letter-spacing="4" fill="#7dd3fc">BADMINTON 360 · BLOG</text>
  <text x="78" y="300" font-family="Arial, sans-serif" font-size="66" font-weight="800" fill="#ffffff">${l1}</text>
  <text x="78" y="380" font-family="Arial, sans-serif" font-size="66" font-weight="800" fill="#ffffff">${l2}</text>
  <text x="80" y="470" font-family="Arial, sans-serif" font-size="30" font-weight="500" fill="#cbd5e1">${sub}</text>
</svg>`

for (const c of COVERS) {
  await sharp(Buffer.from(svg(c))).png().toFile(`public/blog/${c.file}`)
  console.log(`public/blog/${c.file} created`)
}
