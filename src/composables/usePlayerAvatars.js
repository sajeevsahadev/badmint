import { ref } from 'vue'
import { supabase } from '../lib/supabase'

// Batch-fetch avatar_url for a set of user_ids. Returns a reactive map { [user_id]: avatar_url }.
export function usePlayerAvatars() {
  const avatarMap = ref({})
  async function loadAvatars(userIds) {
    const ids = [...new Set((userIds || []).filter(Boolean))]
    if (!ids.length) return
    const { data } = await supabase.rpc('get_public_profiles', { p_user_ids: ids })
    const next = { ...avatarMap.value }
    for (const p of (data ?? [])) next[p.user_id] = p.avatar_url
    avatarMap.value = next
  }
  return { avatarMap, loadAvatars }
}
