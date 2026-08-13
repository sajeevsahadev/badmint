// Generates a badminton-themed blog cover (1200×630, ideal OG size).
import sharp from 'sharp'
import { mkdirSync } from 'fs'

mkdirSync('public/blog', { recursive: true })

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0b1220"/>
      <stop offset="0.55" stop-color="#0f2a4a"/>
      <stop offset="1" stop-color="#0a5b74"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.8" cy="0.2" r="0.6">
      <stop offset="0" stop-color="#22d3ee" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#22d3ee" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="shut" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#a3e635"/>
      <stop offset="1" stop-color="#22d3ee"/>
    </linearGradient>
  </defs>

  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="630" fill="url(#glow)"/>

  <!-- big neon shuttlecock, top-right -->
  <g transform="translate(880,150) scale(11)" fill="none" stroke="url(#shut)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" opacity="0.9">
    <circle cx="0" cy="16" r="4.5" fill="url(#shut)" stroke="none"/>
    <path d="M0 12 L-14 -18 M0 12 L-7 -20 M0 12 L0 -21 M0 12 L7 -20 M0 12 L14 -18"/>
    <path d="M-14 -18 Q0 -11 14 -18"/>
    <path d="M-9 -3 Q0 1 9 -3"/>
  </g>

  <!-- label + title -->
  <text x="80" y="150" font-family="Arial, sans-serif" font-size="24" font-weight="700" letter-spacing="4" fill="#7dd3fc">BADMINTON 360 · BLOG</text>
  <text x="78" y="300" font-family="Arial, sans-serif" font-size="66" font-weight="800" fill="#ffffff">How to Track Your</text>
  <text x="78" y="380" font-family="Arial, sans-serif" font-size="66" font-weight="800" fill="#ffffff">Badminton Matches</text>
  <text x="80" y="470" font-family="Arial, sans-serif" font-size="30" font-weight="500" fill="#cbd5e1">Score tracking, Elo rankings &amp; smarter play</text>
</svg>`

sharp(Buffer.from(svg))
  .png()
  .toFile('public/blog/track-badminton-matches.png')
  .then(() => console.log('public/blog/track-badminton-matches.png created'))
  .catch(err => { console.error(err); process.exit(1) })
