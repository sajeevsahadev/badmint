// App Store icon: exactly 1024×1024, sRGB, NO alpha channel, NO rounded
// corners (Apple applies the mask itself). Flatten onto the icon's dark
// background and strip alpha so App Store Connect accepts it.
import sharp from 'sharp'
import { mkdirSync } from 'fs'

mkdirSync('store-assets', { recursive: true })

sharp('public/icon.png')
  .resize(1024, 1024, { fit: 'cover' })
  .flatten({ background: '#0A0F1E' })   // fill any transparency
  .removeAlpha()
  .png()
  .toFile('store-assets/appstore-icon-1024.png')
  .then(() => console.log('store-assets/appstore-icon-1024.png created'))
  .catch(err => { console.error(err); process.exit(1) })
