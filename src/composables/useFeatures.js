import { reactive } from 'vue'
import { supabase } from '../lib/supabase'

// Runtime feature flags, sourced from the app_settings table via get_app_settings.
// Replaces the build-time TOURNAMENTS_ENABLED constant so an app admin can flip a
// feature on/off from the Admin Panel with no redeploy. Loaded once per session;
// call reloadFeatures() after an admin toggles a flag.
const flags = reactive({
  tournaments_enabled: false,   // safe default until the real value loads
  _loaded: false,
})

let inflight = null

async function load() {
  try {
    const { data } = await supabase.rpc('get_app_settings')
    if (data && typeof data === 'object') {
      for (const [k, v] of Object.entries(data)) flags[k] = !!v
    }
  } catch { /* keep defaults — feature stays hidden on error */ }
  flags._loaded = true
}

export function loadFeatures() {
  if (!inflight) inflight = load()
  return inflight
}

export function reloadFeatures() {
  inflight = load()
  return inflight
}

export function useFeatures() {
  loadFeatures()
  return { flags, reloadFeatures }
}
