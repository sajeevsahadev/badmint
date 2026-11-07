<script setup>
// Deep Analysis — ball-by-ball coach commentary (premium). Shows a shot-by-shot timeline with a
// coaching line per shot; tapping a timestamp seeks the video. Runs the real engine (analyze-video
// deep) and polls; falls back to a sample timeline if the engine isn't reachable.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'

const props = defineProps({
  videoId:  { type: String, required: true },
  canManage:{ type: Boolean, default: false },
  subjects: { type: Array, default: () => [] },   // [{ id, name }]
})
const emit = defineEmits(['seek'])

const loading = ref(true)
const data    = ref(null)
const working = ref(false)
const err     = ref('')
const elapsed = ref(0)
const activePlayer = ref('all')
let pollTimer = null, elapsedTimer = null

const video      = computed(() => data.value?.video || null)
const deepStatus = computed(() => video.value?.deep_status || 'none')
const isMock     = computed(() => !!video.value?.is_deep_mock)
const commentary = computed(() => data.value?.commentary || [])
const shotById   = computed(() => Object.fromEntries((data.value?.shots || []).map(s => [s.id, s])))

const nameByTag = computed(() => Object.fromEntries(props.subjects.map(s => [s.id, s.name])))
const lines = computed(() => {
  let c = commentary.value
  if (activePlayer.value !== 'all') c = c.filter(l => l.tag_id === activePlayer.value)
  return [...c].sort((a, b) => a.t_s - b.t_s)
})

function fmt(s) { const m = Math.floor(s / 60), x = Math.round(s % 60); return `${m}:${String(x).padStart(2, '0')}` }
const sevClass = (s) => ({ good: 'border-emerald-200 bg-emerald-50', warning: 'border-red-200 bg-red-50', watch: 'border-amber-200 bg-amber-50' }[s] || 'border-slate-200 bg-white')
const sevDot = (s) => ({ good: 'bg-emerald-500', warning: 'bg-red-500', watch: 'bg-amber-500' }[s] || 'bg-cyan-500')

onMounted(async () => { await load(); if (deepStatus.value === 'analyzing') startPolling() })
onBeforeUnmount(stop)

async function load(silent = false) {
  if (!silent) loading.value = true
  const { data: d } = await supabase.rpc('get_deep_analysis', { p_video_id: props.videoId })
  if (d) data.value = d
  if (!silent) loading.value = false
}
function startPolling() {
  stop(); elapsed.value = 0
  elapsedTimer = setInterval(() => elapsed.value++, 1000)
  let n = 0
  pollTimer = setInterval(async () => {
    n++; await load(true)
    if (deepStatus.value === 'done' || deepStatus.value === 'failed' || n > 225) stop()
  }, 4000)
}
function stop() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  if (elapsedTimer) { clearInterval(elapsedTimer); elapsedTimer = null }
}

async function runDeep() {
  working.value = true; err.value = ''
  try {
    const { data: r, error } = await supabase.functions.invoke('analyze-video', { body: { video_id: props.videoId, deep: true } })
    if (error || r?.error) {
      const { error: se } = await supabase.rpc('seed_mock_deep', { p_video_id: props.videoId })
      if (se) throw se
      await load(true)
    } else { await load(true); if (deepStatus.value === 'analyzing') startPolling() }
  } catch (e) { err.value = e?.message || 'Deep analysis failed.' }
  finally { working.value = false }
}

function shotType(l) { return l.shot_id && shotById.value[l.shot_id]?.shot_type }
</script>

<template>
  <div class="card p-4">
    <div class="mb-1 flex items-center gap-2">
      <span class="text-lg">🎙️</span>
      <div class="font-display text-base font-bold text-slate-800">Shot-by-shot coaching</div>
      <span class="badge-pending ml-auto">Premium</span>
    </div>
    <p class="mb-3 text-xs text-slate-500">Ball-by-ball commentary on every shot, like a coach watching beside you.</p>

    <div v-if="loading" class="py-6 text-center text-sm text-slate-400">Loading…</div>

    <!-- Not run yet -->
    <div v-else-if="deepStatus === 'none'" class="rounded-xl border border-violet-200 bg-violet-50 p-4 text-center">
      <p class="text-sm text-slate-600">Get a coach's shot-by-shot breakdown — what each shot did well, what to fix, and the drill.</p>
      <button v-if="canManage" :disabled="working" @click="runDeep" class="btn-violet sheen press mt-3 w-full py-2.5 disabled:opacity-50">
        {{ working ? 'Starting…' : '🎙️ Run deep analysis' }}
      </button>
      <p v-else class="mt-2 text-xs text-slate-400">The uploader or a manager can run this.</p>
      <p v-if="err" class="mt-2 text-xs text-red-600">{{ err }}</p>
    </div>

    <!-- Analysing -->
    <div v-else-if="deepStatus === 'analyzing'" class="rounded-xl border border-violet-200 bg-violet-50 p-5 text-center">
      <div class="text-sm font-bold text-slate-800">Breaking down every shot…</div>
      <div class="mt-3 h-2 w-full overflow-hidden rounded-full bg-white">
        <div class="ai-bar h-full rounded-full bg-violet-500"></div>
      </div>
      <p class="mt-2 text-xs text-slate-500">Detecting shots &amp; writing commentary · {{ fmt(elapsed) }}</p>
      <p class="mt-1 text-[11px] text-slate-400">Runs in the background — we'll notify you when it's ready.</p>
    </div>

    <!-- Failed -->
    <div v-else-if="deepStatus === 'failed'" class="rounded-xl border border-red-200 bg-red-50 p-4 text-center">
      <p class="text-sm text-red-600">{{ video?.deep_error || 'Deep analysis didn’t finish.' }}</p>
      <button v-if="canManage" :disabled="working" @click="runDeep" class="btn-ghost mt-2 px-4 py-2 text-xs">↻ Try again</button>
    </div>

    <!-- Done: the timeline -->
    <div v-else>
      <div class="mb-3 flex items-center justify-between gap-2">
        <div v-if="subjects.length > 1" class="flex flex-wrap gap-1.5">
          <button @click="activePlayer = 'all'" class="rounded-full px-2.5 py-1 text-xs font-semibold"
            :class="activePlayer === 'all' ? 'btn-primary' : 'btn-ghost'">All</button>
          <button v-for="s in subjects" :key="s.id" @click="activePlayer = s.id"
            class="rounded-full px-2.5 py-1 text-xs font-semibold" :class="activePlayer === s.id ? 'btn-primary' : 'btn-ghost'">
            {{ s.name }}
          </button>
        </div>
        <span v-if="isMock" class="badge-pending ml-auto">Sample</span>
      </div>

      <div v-if="!lines.length" class="py-5 text-center text-sm text-slate-400">No shots detected for this selection.</div>
      <div v-else class="space-y-2">
        <div v-for="l in lines" :key="l.id" class="rounded-xl border p-3" :class="sevClass(l.severity)">
          <div class="flex items-center gap-2">
            <button @click="emit('seek', l.t_s)"
              class="shrink-0 rounded-md bg-slate-800 px-2 py-0.5 font-mono text-[11px] font-bold text-white">
              ⏱ {{ fmt(l.t_s) }}
            </button>
            <span v-if="shotType(l)" class="rounded-full border border-slate-200 px-2 py-0.5 text-[10px] font-semibold uppercase text-slate-500">{{ shotType(l) }}</span>
            <span v-if="subjects.length > 1 && nameByTag[l.tag_id]" class="text-[11px] font-semibold text-cyan-700">{{ nameByTag[l.tag_id] }}</span>
            <span class="ml-auto h-2 w-2 rounded-full" :class="sevDot(l.severity)"></span>
          </div>
          <p class="mt-1.5 text-sm text-slate-700">{{ l.text }}</p>
        </div>
      </div>

      <button v-if="canManage" @click="runDeep" :disabled="working" class="btn-ghost mt-3 w-full py-2 text-xs disabled:opacity-50">
        {{ working ? 'Re-running…' : '↻ Re-run deep analysis' }}
      </button>
      <p class="mt-2 text-center text-[11px] text-slate-400">
        Shot detection &amp; types are AI estimates and improve with a clear, side-on camera. Shuttle placement &amp; audio commentary are coming next.
      </p>
    </div>
  </div>
</template>

<style scoped>
.ai-bar { width: 40%; animation: aiSweep 1.4s ease-in-out infinite; }
@keyframes aiSweep { 0% { margin-left: -40%; } 100% { margin-left: 100%; } }
@media (prefers-reduced-motion: reduce) { .ai-bar { animation: none; width: 100%; opacity: .6; } }
</style>
