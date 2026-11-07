<script setup>
// Home-page entry for AI Match Analysis. Renders nothing unless the user has early access.
// Shows the latest analysed video for the current club as a "continue" shortcut.
import { ref, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useEntitlements } from '../composables/useEntitlements'

const router = useRouter()
const { currentClub } = useClub()
const { hasEarlyAccess, loadEntitlements } = useEntitlements()
const latest = ref(null)

async function loadLatest() {
  latest.value = null
  if (!hasEarlyAccess.value || !currentClub.value) return
  const { data } = await supabase.from('match_videos')
    .select('id, title, status, deep_status, created_at')
    .eq('club_id', currentClub.value.club_id)
    .order('created_at', { ascending: false }).limit(1).maybeSingle()
  latest.value = data || null
}
onMounted(async () => { await loadEntitlements(); loadLatest() })
watch(() => currentClub.value?.club_id, loadLatest)

const statusText = (v) => v.deep_status === 'done' || v.status === 'done' ? 'Report ready'
  : (v.deep_status === 'analyzing' || v.status === 'analyzing') ? 'Analysing…' : 'Ready to analyse'
const FEATURES = [
  { icon: 'chart',  text: 'Performance breakdown' },
  { icon: 'target', text: 'Strengths and weaknesses' },
  { icon: 'bulb',   text: 'Personalised improvement insights' },
]
</script>

<template>
  <div v-if="hasEarlyAccess" class="mb-5 fade-up">
    <div class="ama-card rounded-3xl border p-5 shadow-lg">
      <div class="flex items-center gap-3">
        <span class="ama-icon flex h-11 w-11 shrink-0 items-center justify-center rounded-xl">
          <svg viewBox="0 0 24 24" class="h-6 w-6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M9.5 3.5a3 3 0 0 0-3 3v.3a3 3 0 0 0-2 2.8 3 3 0 0 0 1 2.2 3 3 0 0 0 1 4.7 3 3 0 0 0 5 1.5V5a2.5 2.5 0 0 0-2-1.5z" />
            <path d="M12.5 8h3l1.5-2M12.5 12h4.5M12.5 16h3l1.5 2" /><circle cx="18" cy="5.5" r="1" /><circle cx="18.5" cy="12" r="1" /><circle cx="18" cy="18.5" r="1" />
          </svg>
        </span>
        <div class="font-display text-lg font-bold text-white">AI Match Analysis</div>
        <span class="ama-badge ml-auto rounded-full px-2.5 py-1 text-[11px] font-bold">AI Powered</span>
      </div>

      <p class="mt-4 text-[15px] font-bold text-white">Understand your game. Improve your performance.</p>
      <p class="mt-2 text-sm leading-relaxed text-slate-300">
        Get a detailed AI-powered breakdown of your badminton match, including your shots, movement,
        playing patterns, strengths and weaknesses.
      </p>

      <ul class="mt-3 space-y-2.5">
        <li v-for="f in FEATURES" :key="f.text" class="flex items-center gap-3 text-sm text-slate-300">
          <svg viewBox="0 0 24 24" class="ama-tick h-5 w-5 shrink-0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <template v-if="f.icon === 'chart'"><path d="M4 20V14M9 20v-8M14 20v-5M19 20V9" /><path d="M4 10l5-4 5 3 6-5" /></template>
            <template v-if="f.icon === 'target'"><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="4.5" /><circle cx="12" cy="12" r="1" /></template>
            <template v-if="f.icon === 'bulb'"><path d="M9 18h6M10 21h4" /><path d="M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2.1h5c0-.9.4-1.6 1-2.1A6 6 0 0 0 12 3z" /></template>
          </svg>
          {{ f.text }}
        </li>
      </ul>

      <button v-if="latest" @click="router.push(`/coach/video/${latest.id}`)"
        class="mt-4 flex w-full items-center gap-2 rounded-xl border border-white/10 bg-white/5 px-3 py-2 text-left transition hover:bg-white/10">
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-semibold text-white">{{ latest.title }}</span>
          <span class="block text-[11px] text-emerald-300/80">{{ statusText(latest) }}</span>
        </span>
        <span class="text-emerald-300">›</span>
      </button>

      <button @click="router.push('/coach')"
        class="ama-cta press mt-4 flex w-full items-center justify-center gap-2 rounded-2xl py-3.5 text-base font-bold text-white">
        Analyse My Match <span aria-hidden="true">→</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.ama-card  { background: #050807; border-color: rgba(255,255,255,.12); }
.ama-icon  { background: #14352c; color: #6ee7b7; }
.ama-badge { background: #0f2a1f; color: #22c55e; }
.ama-tick  { color: #22c55e; }
.ama-cta   { background: #17392f; }
.ama-cta:hover { background: #1d4739; }
</style>
