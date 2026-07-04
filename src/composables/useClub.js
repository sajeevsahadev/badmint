import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const clubs       = ref([])
const currentClub = ref(null)

export function useClub() {
  async function loadClubs() {
    // MUST filter by user_id â€” otherwise RLS returns ALL members of joined clubs,
    // causing the same club to appear once per other member (N times in switcher).
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { clubs.value = []; return }

    const { data, error } = await supabase
      .from('club_members')
      .select('club_id, role, clubs(name, logo_url)')
      .eq('user_id', user.id)          // â† only THIS user's memberships

    if (error) throw error

    // Deduplicate by club_id â€” RLS can return multiple rows when the manager
    // has approved members, because the policy allows reading all member rows
    // for any club you belong to. The user_id filter above should handle this,
    // but we guard defensively here in case of any query/caching edge cases.
    const seen = new Set()
    clubs.value = (data ?? []).filter(c => {
      if (seen.has(c.club_id)) return false
      seen.add(c.club_id)
      return true
    })
    if (!currentClub.value && clubs.value.length) {
      const saved = localStorage.getItem('clubId')
      currentClub.value = clubs.value.find(c => c.club_id === saved) || clubs.value[0]
    }
  }

  function selectClub(c) {
    currentClub.value = c
    localStorage.setItem('clubId', c.club_id)
  }

  async function createClub(name) {
    const { data, error } = await supabase.rpc('create_club', { p_name: name })
    if (error) throw error
    await loadClubs()
    const found = clubs.value.find(c => c.club_id === data)
    if (found) selectClub(found)
    return data
  }

  const isManager = () => ['owner','manager'].includes(currentClub.value?.role)

  return { clubs, currentClub, loadClubs, selectClub, createClub, isManager }
}
