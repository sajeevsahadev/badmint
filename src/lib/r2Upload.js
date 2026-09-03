import { supabase } from './supabase'

// Client-side image upload to Cloudflare R2, mirroring the chat photo pipeline:
// compress to a full (~1600px) + thumbnail (~480px) WebP, get short-lived
// presigned PUT URLs from the r2-upload-url Edge Function (authorized by club
// membership — a tournament manager is a club member), and PUT the bytes
// straight to R2 so nothing large passes through Supabase.

function renderBlob(src, maxDim, quality) {
  const scale = Math.min(1, maxDim / Math.max(src.width, src.height))
  const w = Math.max(1, Math.round(src.width * scale))
  const h = Math.max(1, Math.round(src.height * scale))
  const canvas = document.createElement('canvas')
  canvas.width = w; canvas.height = h
  canvas.getContext('2d').drawImage(src, 0, 0, w, h)
  return new Promise(res => canvas.toBlob(b => res({ blob: b, width: w, height: h }), 'image/webp', quality))
}

async function compressVariants(file) {
  let bmp = null
  try { bmp = await createImageBitmap(file, { imageOrientation: 'from-image' }) } catch { /* fallback */ }
  const src = bmp || await new Promise((res, rej) => {
    const img = new Image(); img.onload = () => res(img); img.onerror = rej
    img.src = URL.createObjectURL(file)
  })
  const full  = await renderBlob(src, 1600, 0.72)
  const thumb = await renderBlob(src, 480, 0.6)
  bmp?.close?.()
  if (!full.blob || !thumb.blob) throw new Error('Could not process image')
  return { full, thumb }
}

async function getUploadUrl(clubId) {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Not signed in')
  const resp = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/r2-upload-url`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ club_id: clubId }),
  })
  if (!resp.ok) throw new Error('Could not start upload')
  return await resp.json()
}

// Compress + upload one image for a club. Returns { url, thumbUrl, width, height }.
export async function uploadClubImage(file, clubId) {
  if (!file || !file.type?.startsWith('image/')) throw new Error('Please choose an image file.')
  if (file.size > 25 * 1024 * 1024) throw new Error('Image is too large (max 25 MB).')
  const { full, thumb } = await compressVariants(file)
  const up = await getUploadUrl(clubId)
  const [putFull, putThumb] = await Promise.all([
    fetch(up.uploadUrl,      { method: 'PUT', headers: { 'Content-Type': 'image/webp' }, body: full.blob }),
    fetch(up.thumbUploadUrl, { method: 'PUT', headers: { 'Content-Type': 'image/webp' }, body: thumb.blob }),
  ])
  if (!putFull.ok || !putThumb.ok) throw new Error('Upload failed — please retry')
  return { url: up.publicUrl, thumbUrl: up.thumbUrl, width: full.width, height: full.height }
}
