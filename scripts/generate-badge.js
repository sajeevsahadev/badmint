// Generates the monochrome notification "badge" (status-bar small icon).
// Android uses only the alpha silhouette of this and tints it, so it MUST be
// a white shape on a transparent background — not the full-colour app icon.
import sharp from 'sharp'

const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
  <g fill="#ffffff">
    <!-- feather skirt -->
    <path d="M41 59 L27 21 Q48 31 69 21 L55 59 Z"/>
    <!-- cork -->
    <circle cx="48" cy="70" r="12"/>
  </g>
</svg>`

sharp(Buffer.from(svg))
  .resize(96, 96)
  .png()
  .toFile('public/badge.png')
  .then(() => console.log('public/badge.png created'))
  .catch(err => { console.error(err); process.exit(1) })
