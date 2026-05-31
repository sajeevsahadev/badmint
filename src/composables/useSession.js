import { ref } from 'vue'
import { supabase } from '../lib/supabase'

// Singleton — one session per browser tab
const sessionId = ref(null)

export function useSession() {
  async function startSession() {
    if (sessionId.value) return sessionId.value
    const ua = navigator.userAgent
    const { data, error } = await supabase.rpc('create_session', { p_user_agent: ua })
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
