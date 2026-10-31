// Match-video storage abstraction.
//
// Provider is chosen by VITE_VIDEO_PROVIDER:
//   'r2'       → Cloudflare R2 via the `video-sign` Edge Function (presigned URLs).
//                The large bytes go straight to R2, never through Supabase. USE THIS in prod —
//                Supabase free tier is only 1 GB and a single match video can exceed that.
//   'supabase' → Supabase Storage (default). Dev/preview fallback ONLY, for small clips.
//
// Either way the rest of the app calls the same three functions and stores `storage_path`
// (an R2 key, or a Supabase object path) on match_videos. Switching providers changes only
// this file + the env var.
import { supabase } from './supabase'

const PROVIDER = (import.meta.env.VITE_VIDEO_PROVIDER || 'supabase').toLowerCase()
const BUCKET = 'match-videos'
export const isR2 = PROVIDER === 'r2'

// Supabase-fallback safety cap: never let one upload threaten the 1 GB free tier.
export const SUPABASE_MAX_BYTES = 80 * 1024 * 1024   // 80 MB

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

// Upload a recorded Blob/File. Returns the storage path/key to persist on match_videos.
export async function uploadMatchVideo(blob, { clubId, videoId, contentType }) {
  const ctype = contentType || blob.type
  const key   = buildKey(clubId, videoId, ctype)

  if (isR2) {
    const { url } = await sign('put', { clubId, key, contentType: ctype })
    const res = await fetch(url, { method: 'PUT', body: blob, headers: { 'content-type': ctype } })
    if (!res.ok) throw new Error(`Upload failed (R2 ${res.status})`)
    return key
  }

  // Supabase fallback — guard the 1 GB free tier.
  if (blob.size > SUPABASE_MAX_BYTES) {
    throw new Error(
      `This clip is ${(blob.size / 1048576).toFixed(0)} MB. The dev storage caps at ` +
      `${SUPABASE_MAX_BYTES / 1048576} MB — record a shorter clip, or switch on Cloudflare R2.`
    )
  }
  const { error } = await supabase.storage.from(BUCKET).upload(key, blob, { contentType: ctype, upsert: true })
  if (error) throw error
  return key
}

// A short-lived URL to play a stored video.
export async function getPlaybackUrl(storagePath, expiresInSeconds = 3600) {
  if (!storagePath) return null
  if (isR2) {
    const clubId = String(storagePath).split('/')[0]
    const { url } = await sign('get', { clubId, key: storagePath })
    return url
  }
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(storagePath, expiresInSeconds)
  if (error) throw error
  return data?.signedUrl ?? null
}

// Remove the stored object (row deletion is handled separately by the caller).
export async function deleteMatchVideo(storagePath) {
  if (!storagePath) return
  if (isR2) {
    const clubId = String(storagePath).split('/')[0]
    const { url } = await sign('delete', { clubId, key: storagePath })
    await fetch(url, { method: 'DELETE' })
    return
  }
  await supabase.storage.from(BUCKET).remove([storagePath])
}
