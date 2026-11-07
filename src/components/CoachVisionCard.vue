<script setup>
// Home-page entry for Coach Vision (AI match analysis). Renders nothing unless the user has early
// access. Shows the latest analysed video for the current club as a "continue" shortcut.
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
</script>

<template>
  <div v-if="hasEarlyAccess" class="mb-5 fade-up">
    <div class="relative overflow-hidden rounded-2xl p-4 text-white shadow-lg"
      style="background: linear-gradient(135deg, #0b2a4a 0%, #134e6f 55%, #4c1d95 100%)">
      <div class="pointer-events-none absolute -right-6 -top-6 h-28 w-28 rounded-full bg-cyan-400/20 blur-2xl"></div>
      <div class="flex items-center gap-2">
        <span class="text-xl">🎥</span>
        <div class="font-display text-lg font-extrabold">Coach Vision</div>
        <span class="ml-auto rounded bg-white/15 px-1.5 py-0.5 text-[9px] font-bold tracking-wide">EARLY ACCESS</span>
      </div>
      <p class="mt-1 text-xs text-cyan-50/90">Your AI match coach — record or upload a match and get a stroke-by-stroke breakdown.</p>

      <button v-if="latest" @click="router.push(`/coach/video/${latest.id}`)"
        class="mt-3 flex w-full items-center gap-2 rounded-xl bg-white/10 px-3 py-2 text-left hover:bg-white/15 transition">
        <span class="min-w-0 flex-1">
          <span class="block truncate text-sm font-semibold">{{ latest.title }}</span>
          <span class="block text-[11px] text-cyan-100/80">{{ statusText(latest) }}</span>
        </span>
        <span class="text-cyan-200">›</span>
      </button>

      <div class="mt-3 grid grid-cols-2 gap-2">
        <button @click="router.push('/record')" class="press rounded-xl bg-cyan-400 py-2 text-sm font-bold text-slate-900">🎥 Record</button>
        <button @click="router.push('/record?upload=1')" class="press rounded-xl bg-white/15 py-2 text-sm font-bold">⬆️ Upload</button>
      </div>
      <button @click="router.push('/coach')" class="mt-2 w-full text-center text-[11px] font-semibold text-cyan-100/90">
        Open Coach Vision →
      </button>
    </div>
  </div>
</template>
