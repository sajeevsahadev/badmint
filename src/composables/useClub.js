import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const clubs       = ref([])
const currentClub = ref(null)
// Admin "Super User mode": when an app_admin turns this on, the switcher lists
// EVERY club so they can monitor full activity. Persisted per device.
const superUser   = ref((() => { try { return localStorage.getItem('b360_superuser') === '1' } catch { return false } })())
const isAppAdmin  = ref(false)

export function useClub() {
  async function loadClubs() {
    // MUST filter by user_id â€” otherwise RLS returns ALL members of joined clubs,
    // causing the same club to appear once per other member (N times in switcher).
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { clubs.value = []; isAppAdmin.value = false; return }

    const { data, error } = await supabase
      .from('club_members')
      .select('club_id, role, clubs!inner(name, logo_url, currency)')
      .eq('user_id', user.id)          // â† only THIS user's memberships

    if (error) throw error

    // Deduplicate by club_id â€” RLS can return multiple rows when the manager
    // has approved members, because the policy allows reading all member rows
    // for any club you belong to. The user_id filter above should handle this,
    // but we guard defensively here in case of any query/caching edge cases.
    const seen = new Set()
    const list = (data ?? []).filter(c => {
      if (seen.has(c.club_id)) return false
      seen.add(c.club_id)
      return true
    })

    // Am I an app admin? (cheap SECURITY DEFINER check) — gates Super User mode.
    try {
      const { data: adm } = await supabase.rpc('is_app_admin')
      isAppAdmin.value = !!adm
    } catch { isAppAdmin.value = false }

    // Super User mode: fold EVERY club into the switcher (role 'owner' so all
    // screens render). _adminView flags clubs the admin is only monitoring.
    if (superUser.value && isAppAdmin.value) {
      try {
        const { data: all } = await supabase.rpc('admin_list_all_clubs')
        for (const c of all ?? []) {
          if (seen.has(c.club_id)) continue
          seen.add(c.club_id)
          list.push({
            club_id: c.club_id, role: 'owner', _adminView: true,
            clubs: { name: c.name, logo_url: c.logo_url, currency: c.currency },
          })
        }
      } catch { /* non-admin or RPC unavailable — ignore */ }
    }

    clubs.value = list
    // Pick / re-validate the current club. Self-heals when the selected club
    // vanished from the list (e.g. an admin soft-deleted it, or the user left):
    // reselect the saved/first remaining club, or clear it if none are left.
    if (clubs.value.length) {
      const stillValid = currentClub.value && clubs.value.some(c => c.club_id === currentClub.value.club_id)
      if (!stillValid) {
        const saved = localStorage.getItem('clubId')
        currentClub.value = clubs.value.find(c => c.club_id === saved) || clubs.value[0]
      }
    } else {
      currentClub.value = null
    }
  }

  function selectClub(c) {
    currentClub.value = c
    localStorage.setItem('clubId', c.club_id)
  }

  // Turn Super User mode on/off (admin only) and refresh the club list.
  async function setSuperUser(on) {
    superUser.value = !!on
    try { localStorage.setItem('b360_superuser', on ? '1' : '0') } catch { /* ignore */ }
    await loadClubs()
  }

  async function createClub(name, currency = 'AED', countryCode = 'AE') {
    const { data, error } = await supabase.rpc('create_club', {
      p_name: name, p_currency: currency, p_country_code: countryCode,
    })
    if (error) throw error
    await loadClubs()
    const found = clubs.value.find(c => c.club_id === data)
    if (found) selectClub(found)
    return data
  }

  const isManager = () => ['owner','manager'].includes(currentClub.value?.role)

  return { clubs, currentClub, loadClubs, selectClub, createClub, isManager, superUser, isAppAdmin, setSuperUser }
}
