import { ref } from 'vue'
import { supabase } from '../lib/supabase'
import { useGeo } from './useGeo'

// Singleton — one session per browser tab
const sessionId = ref(null)

export function useSession() {
  const { country, city, region, detectCountry } = useGeo()

  // Records a login row (IP captured server-side) tagged with the current club
  // and the IP's location, for the admin security audit.
  async function startSession(clubId = null) {
    if (sessionId.value) return sessionId.value
    // Ensure geo is resolved (cached after first run) so location is populated.
    try { await detectCountry() } catch { /* offline — location just stays null */ }
    const { data, error } = await supabase.rpc('create_session', {
      p_user_agent: navigator.userAgent,
      p_club_id:    clubId,
      p_country:    country.value || null,
      p_city:       city.value || null,
      p_region:     region.value || null,
    })
    if (!error && data) sessionId.value = data
    return sessionId.value
  }

  async function trackPage(path) {
    if (!sessionId.value) return
    // fire-and-forget — don't block navigation
    supabase.rpc('log_activity', {
      p_session_id: sessionId.value,
      p_event_type: 'page_view',
      p_event_data:  { path }
    }).catch(() => {})
  }

  async function trackAction(eventType, data = {}) {
    if (!sessionId.value) return
    supabase.rpc('log_activity', {
      p_session_id: sessionId.value,
      p_event_type: eventType,
      p_event_data:  data
    }).catch(() => {})
  }

  async function endSession() {
    if (!sessionId.value) return
    await supabase.rpc('end_session', { p_session_id: sessionId.value })
    sessionId.value = null
  }

  return { sessionId, startSession, trackPage, trackAction, endSession }
}
