import sharp from 'sharp'
import { readFileSync } from 'fs'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = join(__dirname, '..')

const svg = readFileSync(join(root, 'public', 'icon.svg'))

await sharp(svg).resize(512, 512).png({ compressionLevel: 9 }).toFile(join(root, 'public', 'icon-512.png'))
console.log('✓ icon-512.png')

await sharp(svg).resize(192, 192).png({ compressionLevel: 9 }).toFile(join(root, 'public', 'icon-192.png'))
console.log('✓ icon-192.png')

// Also update favicon.svg (keep the SVG as-is — browsers use it directly)
console.log('✓ done — copy public/icon.svg to public/favicon.svg if needed')
