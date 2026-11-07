// Match-video storage — Cloudflare R2 only.
//
// The big video bytes go straight to R2 via short-lived presigned URLs minted by the
// `video-sign` Edge Function; they never pass through Supabase. (Supabase free tier is 1 GB —
// a single match video can exceed that, so Supabase Storage is NOT used for video.)
// Only lightweight metadata (match_videos rows) stays in Supabase.
//
// R2 secrets live server-side on the Edge Function:
//   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
// Switching storage would mean changing only this file + that function.
import { supabase } from './supabase'

// Kept for callers that still import it; video storage is always R2 now.
export const isR2 = true

export function extForMime(mime = '') {
  if (mime.includes('mp4'))       return 'mp4'
  if (mime.includes('webm'))      return 'webm'
  if (mime.includes('quicktime')) return 'mov'
  if (mime.includes('matroska'))  return 'mkv'
  return 'webm'
}

export function buildKey(clubId, videoId, contentType) {
  return `${clubId}/${videoId}.${extForMime(contentType)}`
}

async function sign(action, { clubId, key, contentType }) {
  const { data, error } = await supabase.functions.invoke('video-sign', {
    body: { action, clubId, key, contentType },
  })
  if (error) throw error
  if (data?.error) throw new Error(data.error)
  return data   // { url, method, contentType }
}

// Upload a recorded Blob/File straight to R2. Returns the storage key to persist on match_videos.
// Uses XHR (not fetch) for real upload progress, a long timeout, and one automatic retry — large
// videos on mobile connections were failing with an opaque "Failed to fetch" on a transient drop.
export async function uploadMatchVideo(blob, { clubId, videoId, contentType, onProgress }) {
  const ctype = contentType || blob.type
  const key   = buildKey(clubId, videoId, ctype)
  const { url } = await sign('put', { clubId, key, contentType: ctype })
  await putWithProgress(url, blob, ctype, onProgress)
  return key
}

function putWithProgress(url, blob, ctype, onProgress, attempt = 0) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open('PUT', url, true)
    xhr.setRequestHeader('content-type', ctype)
    xhr.timeout = 20 * 60 * 1000   // 20 min — generous for long videos on slow mobile links
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) onProgress(Math.round((e.loaded / e.total) * 100))
    }
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve()
      else reject(new Error(`Upload failed (storage ${xhr.status}). Please try again.`))
    }
    const retryOr = (msg) => {
      if (attempt < 1) {
        setTimeout(() => putWithProgress(url, blob, ctype, onProgress, attempt + 1).then(resolve, reject), 1200)
      } else reject(new Error(msg))
    }
    xhr.onerror = () => retryOr('Upload failed — network dropped. Check your connection and try again.')
    xhr.ontimeout = () => retryOr('Upload timed out — try a stronger connection or a shorter clip.')
    xhr.send(blob)
  })
}

// A short-lived URL to play a stored video.
export async function getPlaybackUrl(storagePath) {
  if (!storagePath) return null
  const clubId = String(storagePath).split('/')[0]
  const { url } = await sign('get', { clubId, key: storagePath })
  return url
}

// Remove the stored object (the match_videos row is deleted separately by the caller).
export async function deleteMatchVideo(storagePath) {
  if (!storagePath) return
  const clubId = String(storagePath).split('/')[0]
  const { url } = await sign('delete', { clubId, key: storagePath })
  await fetch(url, { method: 'DELETE' })
}
