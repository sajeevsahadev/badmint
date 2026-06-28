// Compress an image File to a square JPEG data-URI suitable for storing in the DB.
export async function compressImageToDataUrl(file, { maxSize = 256, quality = 0.72, maxBytes = 60000 } = {}) {
  if (!file || !file.type?.startsWith('image/')) throw new Error('Please choose an image file (JPG, PNG, WebP).')
  const srcUrl = await new Promise((res, rej) => {
    const r = new FileReader(); r.onload = () => res(r.result); r.onerror = () => rej(new Error('Could not read file')); r.readAsDataURL(file)
  })
  const img = await new Promise((res, rej) => {
    const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('Invalid image')); i.src = srcUrl
  })
  const side = Math.min(img.width, img.height)
  const sx = (img.width - side) / 2, sy = (img.height - side) / 2
  const canvas = document.createElement('canvas')
  canvas.width = maxSize; canvas.height = maxSize
  const ctx = canvas.getContext('2d')
  ctx.drawImage(img, sx, sy, side, side, 0, 0, maxSize, maxSize)
  let q = quality
  let out = canvas.toDataURL('image/jpeg', q)
  // Step quality down until under maxBytes (base64 length ≈ bytes)
  while (out.length > maxBytes && q > 0.3) { q -= 0.1; out = canvas.toDataURL('image/jpeg', q) }
  return out
}
