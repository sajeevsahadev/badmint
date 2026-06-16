import { ref, computed, watch } from 'vue'
import { supabase } from '../lib/supabase'

// 'light' | 'dark' | 'system' — persisted to localStorage immediately so the
// app paints correctly before the profile RPC round-trip resolves, and
// synced to user_profiles.theme_pref so the choice follows the user across
// devices. NOTE: a real dark palette doesn't exist in style.css yet — the
// whole app is currently light-only (see CLAUDE.md). Selecting 'dark' is
// remembered and the class is applied, but until the dark CSS pass lands,
// the Appearance screen shows it as "Coming soon" and the app stays light.
export const DARK_THEME_READY = false

const STORAGE_KEY = 'b360_theme'
const theme = ref(localStorage.getItem(STORAGE_KEY) || 'system')
const systemPrefersDark = ref(
  typeof window !== 'undefined' && window.matchMedia
    ? window.matchMedia('(prefers-color-scheme: dark)').matches
    : false
)

if (typeof window !== 'undefined' && window.matchMedia) {
  window.matchMedia('(prefers-color-scheme: dark)')
    .addEventListener('change', (e) => { systemPrefersDark.value = e.matches })
}

const resolvedTheme = computed(() => {
  if (theme.value === 'system') return systemPrefersDark.value ? 'dark' : 'light'
  return theme.value
})

function applyTheme() {
  const isDark = DARK_THEME_READY && resolvedTheme.value === 'dark'
  document.documentElement.classList.toggle('dark', isDark)
}

watch(resolvedTheme, applyTheme, { immediate: true })

export function useTheme() {
  function setTheme(value) {
    theme.value = value
    localStorage.setItem(STORAGE_KEY, value)
    supabase.rpc('update_theme_pref', { p_theme: value }).catch(() => {})
  }

  // Called once after the profile loads — adopts the server's saved
  // preference only if this device has never set one locally.
  function syncFromProfile(serverPref) {
    if (!localStorage.getItem(STORAGE_KEY) && serverPref) {
      theme.value = serverPref
    }
  }

  return { theme, resolvedTheme, setTheme, syncFromProfile, DARK_THEME_READY }
}
