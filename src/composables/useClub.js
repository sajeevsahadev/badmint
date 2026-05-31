import { ref } from 'vue'
import { supabase } from '../lib/supabase'
const clubs = ref([])
const currentClub = ref(null)
export function useClub() {
  async function loadClubs() {
    const { data, error } = await supabase.from('club_members').select('club_id, role, clubs(name)')
    if (error) throw error
    clubs.value = data ?? []
    if (!currentClub.value && clubs.value.length) {
      const saved = localStorage.getItem('clubId')
      currentClub.value = clubs.value.find(c => c.club_id === saved) || clubs.value[0]
    }
  }
  function selectClub(c) { currentClub.value = c; localStorage.setItem('clubId', c.club_id) }
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
