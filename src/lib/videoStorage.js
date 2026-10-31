// Match-video storage abstraction.
//
// Phase 0 (prototype) stores in Supabase Storage so there are NO new secrets to
// set up — it reuses the existing Supabase project. When we move to Cloudflare R2
// (for scale + lower cost), only this file changes: swap the three functions for
// signed-URL uploads against R2 and the rest of the app keeps working unchanged.
//
// Path convention (matches the storage RLS policy in v100): "<club_id>/<video_id>.<ext>"
import { supabase } from './supabase'

const BUCKET = 'match-videos'

export function extForMime(mime = '') {
  if (mime.includes('mp4'))       return 'mp4'
  if (mime.includes('webm'))      return 'webm'
  if (mime.includes('quicktime')) return 'mov'
  if (mime.includes('matroska'))  return 'mkv'
  return 'webm'
}

// Upload a recorded Blob/File. Returns the storage path to persist on match_videos.
export async function uploadMatchVideo(blob, { clubId, videoId, contentType }) {
  const ext  = extForMime(contentType || blob.type)
  const path = `${clubId}/${videoId}.${ext}`
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, blob, { contentType: contentType || blob.type, upsert: true })
  if (error) throw error
  return path
}

// A short-lived URL to play a stored video (bucket is private).
export async function getPlaybackUrl(storagePath, expiresInSeconds = 3600) {
  if (!storagePath) return null
  const { data, error } = await supabase.storage
    .from(BUCKET)
    .createSignedUrl(storagePath, expiresInSeconds)
  if (error) throw error
  return data?.signedUrl ?? null
}

// Remove the stored object (row deletion is handled separately by the caller).
export async function deleteMatchVideo(storagePath) {
  if (!storagePath) return
  await supabase.storage.from(BUCKET).remove([storagePath])
}
