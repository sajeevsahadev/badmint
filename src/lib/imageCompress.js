// Compress an image File to a square JPEG data-URI suitable for storing in the DB.
export async function compressImageToDataUrl(file, { maxSize = 256, quality = 0.72, maxBytes = 60000 } = {}) {
  if (!file || !file.type?.startsWith('image/')) throw new Error('Please choose an image file (JPG, PNG, WebP).')

  const src = await loadDrawable(file)
  const side = Math.min(src.width, src.height)
  const sx = (src.width - side) / 2, sy = (src.height - side) / 2

  // Encode at a given square dimension, stepping JPEG quality down until under maxBytes.
  const encodeAt = (dim) => {
    const canvas = document.createElement('canvas')
    canvas.width = dim; canvas.height = dim
    const ctx = canvas.getContext('2d')
    ctx.drawImage(src.el, sx, sy, side, side, 0, 0, dim, dim)
    let q = quality
    let out = canvas.toDataURL('image/jpeg', q)
    while (out.length > maxBytes && q > 0.3) { q -= 0.1; out = canvas.toDataURL('image/jpeg', q) }
    return out
  }

  // Try the target size; if still over budget at min quality, halve the dimensions
  // and retry so the result is always safely under maxBytes for the DB text column.
  let dim = maxSize
  let out = encodeAt(dim)
  while (out.length > maxBytes && dim > 64) { dim = Math.round(dim / 2); out = encodeAt(dim) }
  src.close?.()
  return out
}

// Decode a File into something drawable on a canvas.
// Prefer createImageBitmap: it decodes off the main thread, handles very large
// phone photos that make the classic `new Image()` path fail on mobile ("Invalid
// image"), and applies EXIF orientation. Fall back to FileReader → Image for
// older browsers that lack createImageBitmap.
async function loadDrawable(file) {
  if (typeof createImageBitmap === 'function') {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' })
      return { el: bmp, width: bmp.width, height: bmp.height, close: () => bmp.close?.() }
    } catch {
      // Some browsers reject the options object — retry without it before falling back.
      try {
        const bmp = await createImageBitmap(file)
        return { el: bmp, width: bmp.width, height: bmp.height, close: () => bmp.close?.() }
      } catch { /* fall through to the Image path */ }
    }
  }

  const srcUrl = await new Promise((res, rej) => {
    const r = new FileReader()
    r.onload = () => res(r.result)
    r.onerror = () => rej(new Error('Could not read the file. Please try another image.'))
    r.readAsDataURL(file)
  })
  const img = await new Promise((res, rej) => {
    const i = new Image()
    i.onload = () => res(i)
    i.onerror = () => rej(new Error("That image couldn't be opened. Try a JPG or PNG (iPhone HEIC photos aren't supported)."))
    i.src = srcUrl
  })
  return { el: img, width: img.width, height: img.height }
}
