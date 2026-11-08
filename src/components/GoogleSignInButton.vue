<script setup>
// One-tap Google sign-in: goes straight to Google's account picker (no intermediate /login page).
// White Google-style pill so it stands out on both the dark hero and white cards.
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth'

defineProps({ label: { type: String, default: 'Continue with Google' } })
const { signInWithGoogle } = useAuth()
const busy = ref(false)
async function go() {
  if (busy.value) return
  busy.value = true
  try { await signInWithGoogle() } catch { busy.value = false }
}
</script>

<template>
  <button type="button" class="btn-google" :disabled="busy" @click="go">
    <svg viewBox="0 0 48 48" class="h-5 w-5 shrink-0" aria-hidden="true">
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/>
      <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.9 1.2 8 3.1l5.7-5.7C34.1 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/>
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.5 39.6 16.2 44 24 44z"/>
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/>
    </svg>
    <span>{{ busy ? 'Opening Google…' : label }}</span>
  </button>
</template>

<style scoped>
.btn-google {
  display: inline-flex; align-items: center; justify-content: center; gap: .65rem;
  min-height: 52px; padding: .8rem 1.75rem; border-radius: 9999px;
  background: #ffffff; color: #1f2937; font-weight: 700; font-size: 1rem;
  border: 2px solid rgba(0, 180, 216, .55);
  box-shadow: 0 0 0 4px rgba(0, 180, 216, .12), 0 10px 28px rgba(0, 153, 184, .35);
  transition: transform .15s ease, box-shadow .15s ease;
  animation: gpulse 2.4s ease-in-out infinite;
}
.btn-google:hover { transform: translateY(-1px); box-shadow: 0 0 0 6px rgba(0, 180, 216, .18), 0 14px 34px rgba(0, 153, 184, .45); }
.btn-google:active { transform: scale(.98); }
.btn-google:disabled { opacity: .7; animation: none; }
@keyframes gpulse { 0%,100% { box-shadow: 0 0 0 4px rgba(0,180,216,.12), 0 10px 28px rgba(0,153,184,.35) } 50% { box-shadow: 0 0 0 8px rgba(0,180,216,.06), 0 10px 28px rgba(0,153,184,.35) } }
@media (prefers-reduced-motion: reduce) { .btn-google { animation: none } }
</style>
