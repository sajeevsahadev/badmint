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
export async function uploadMatchVideo(blob, { clubId, videoId, contentType }) {
  const ctype = contentType || blob.type
  const key   = buildKey(clubId, videoId, ctype)
  const { url } = await sign('put', { clubId, key, contentType: ctype })
  const res = await fetch(url, { method: 'PUT', body: blob, headers: { 'content-type': ctype } })
  if (!res.ok) throw new Error(`Upload failed (R2 ${res.status})`)
  return key
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
