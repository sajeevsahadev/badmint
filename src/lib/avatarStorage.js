import { supabase } from './supabase'
import { dataUrlToBlob } from './imageCompress'

// Avatars live in the public `avatars` Storage bucket at `<userId>/avatar.jpg`
// (one file per user). We store the public URL in user_profiles.avatar_url,
// with a ?v= cache-buster so a replaced photo shows immediately.

export async function uploadAvatarBlob(userId, blob) {
  const path = `${userId}/avatar.jpg`
  const { error } = await supabase.storage.from('avatars')
    .upload(path, blob, { upsert: true, contentType: blob.type || 'image/jpeg' })
  if (error) throw error
  const { data } = supabase.storage.from('avatars').getPublicUrl(path)
  return `${data.publicUrl}?v=${Date.now()}`
}

// One-time self-migration: if a user's avatar is still an inline base64 data
// URI, upload it to Storage and swap avatar_url to the URL. Fire-and-forget;
// returns the new URL or null if there was nothing to do / it failed.
export async function migrateOwnAvatarIfNeeded(userId, avatarUrl) {
  if (!userId || !avatarUrl || !avatarUrl.startsWith('data:')) return null
  try {
    const url = await uploadAvatarBlob(userId, dataUrlToBlob(avatarUrl))
    await supabase.from('user_profiles').update({ avatar_url: url }).eq('user_id', userId)
    return url
  } catch {
    return null   // leave the base64 in place; try again next time
  }
}
