<script setup>
// Deep Analysis — ball-by-ball coach commentary (premium). A stroke-by-stroke timeline with one coaching
// line per stroke; tapping a timestamp seeks the video. Every run is a saved VERSION — re-analysing adds
// Version N+1 and keeps the earlier ones. Falls back to a labelled sample if the engine isn't reachable.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { versionLabel } from '../lib/videoAnalysis'

const props = defineProps({
  videoId:  { type: String, required: true },
  canManage:{ type: Boolean, default: false },
  subjects: { type: Array, default: () => [] },   // [{ id, name, photo }]
  isAdmin:  { type: Boolean, default: false },    // version history is admin-only
  videoEl:  { type: Object, default: null },      // the <video> element, for spoken play-along
  withQuick:{ type: Boolean, default: false },    // no Quick Report yet -> make both in the same pass
})
const emit = defineEmits(['seek', 'run', 'done', 'started'])
const showLines = ref(false)   // the full stroke-by-stroke list is kept but folded away under the summary

const loading = ref(true)
const data    = ref(null)
const working = ref(false)
const err     = ref('')
const elapsed = ref(0)
const activePlayer = ref('all')
const selectedRunId = ref(null)
let pollTimer = null, elapsedTimer = null

const video      = computed(() => data.value?.video || null)
const deepStatus = computed(() => video.value?.deep_status || 'none')
const runs       = computed(() => data.value?.runs || [])
const doneRuns   = computed(() => runs.value.filter(r => r.status === 'done'))
const latestRun  = computed(() => runs.value[0] || null)
const shownRun   = computed(() => runs.value.find(r => r.id === data.value?.run_id) || null)
const commentary = computed(() => data.value?.commentary || [])
const shotById   = computed(() => Object.fromEntries((data.value?.shots || []).map(s => [s.id, s])))
const byTag      = computed(() => Object.fromEntries(props.subjects.map(s => [s.id, s])))
const activeName = computed(() => byTag.value[activePlayer.value]?.name || '')

const lines = computed(() => {
  let c = commentary.value
  if (activePlayer.value !== 'all') c = c.filter(l => l.tag_id === activePlayer.value)
  return [...c].sort((a, b) => a.t_s - b.t_s)
})

function fmt(s) { const m = Math.floor(s / 60), x = Math.floor(s % 60); return `${m}:${String(x).padStart(2, '0')}` }
const sevClass = (s) => ({ good: 'border-emerald-200 bg-emerald-50', warning: 'border-red-200 bg-red-50', watch: 'border-amber-200 bg-amber-50' }[s] || 'border-slate-200 bg-white')
const sevDot = (s) => ({ good: 'bg-emerald-500', warning: 'bg-red-500', watch: 'bg-amber-500' }[s] || 'bg-cyan-500')
const typeLabel = (t) => ({ overhead: 'Overhead', drive: 'Mid-height', low: 'Low' }[t] || t)

onMounted(async () => { await load(); if (deepStatus.value === 'analyzing') startPolling() })
onBeforeUnmount(stop)

async function load(silent = false) {
  if (!silent) loading.value = true
  const { data: d } = await supabase.rpc('get_deep_analysis', { p_video_id: props.videoId, p_run_id: selectedRunId.value })
  if (d) { data.value = d; emit('run', d.run_id || null) }
  if (!silent) loading.value = false
}
async function showVersion(id) { selectedRunId.value = id; await load(true) }

function startPolling() {
  stop(); elapsed.value = 0
  elapsedTimer = setInterval(() => elapsed.value++, 1000)
  let n = 0
  pollTimer = setInterval(async () => {
    n++; await load(true)
    if (deepStatus.value === 'done' || deepStatus.value === 'failed' || n > 225) {
      stop(); selectedRunId.value = null; await load(true)
      if (deepStatus.value === 'done') emit('done')
    }
  }, 4000)
}
function stop() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  if (elapsedTimer) { clearInterval(elapsedTimer); elapsedTimer = null }
}

async function runDeep() {
  working.value = true; err.value = ''
  try {
    const { data: r, error } = await supabase.functions.invoke('analyze-video', { body: { video_id: props.videoId, mode: props.withQuick ? 'both' : 'deep' } })
    if (error || r?.error) {
      const { error: se } = await supabase.rpc('seed_mock_deep', { p_video_id: props.videoId })
      if (se) throw se
      selectedRunId.value = null
      await load(true)
    } else { await load(true); if (deepStatus.value === 'analyzing') startPolling(); if (r?.quick_run_id) emit('started') }
  } catch (e) { err.value = e?.message || 'Deep analysis failed.' }
  finally { working.value = false }
}

function shotType(l) { return l.shot_id && shotById.value[l.shot_id]?.shot_type }

// ── Spoken commentary ───────────────────────────────────────────────────────────────────────────
// Each line is voiced once by the AI (cached in storage); the browser's own voice is the fallback.
const audioUrl  = ref({})          // line id → playback URL
const speaking  = ref(null)        // line id currently being spoken
const narrate   = ref(false)       // "play with commentary" mode
const audioNote = ref('')
let player = null, played = new Set(), fetching = new Set()

async function fetchAudio(ids) {
  const want = ids.filter(id => !audioUrl.value[id] && !fetching.has(id)).slice(0, 40)
  if (!want.length || !data.value?.run_id) return
  want.forEach(id => fetching.add(id))
  try {
    const { data: r, error } = await supabase.functions.invoke('commentary-audio',
      { body: { video_id: props.videoId, run_id: data.value.run_id, line_ids: want } })
    if (error || r?.error) audioNote.value = 'AI voice unavailable right now — using your device voice.'
    const next = { ...audioUrl.value }
    for (const c of r?.clips || []) next[c.id] = c.url
    audioUrl.value = next
  } catch { audioNote.value = 'AI voice unavailable right now — using your device voice.' }
  finally { want.forEach(id => fetching.delete(id)) }
}

function stopSpeech() {
  if (player) { player.pause(); player = null }
  try { window.speechSynthesis?.cancel() } catch { /* ignore */ }
  speaking.value = null
}

async function speak(l, { wait = true } = {}) {
  stopSpeech()
  speaking.value = l.id
  if (!audioUrl.value[l.id] && wait) await fetchAudio([l.id])
  const url = audioUrl.value[l.id]
  if (url) {
    player = new Audio(url)
    player.onended = () => { if (speaking.value === l.id) speaking.value = null }
    try { await player.play(); return } catch { /* fall through to device voice */ }
  }
  try {
    const u = new SpeechSynthesisUtterance(l.text)
    u.rate = 1.05
    u.onend = () => { if (speaking.value === l.id) speaking.value = null }
    window.speechSynthesis.speak(u)
  } catch { speaking.value = null }
}

function playLine(l) { emit('seek', l.t_s); speak(l) }

function onTime() {
  const v = props.videoEl
  if (!v || !narrate.value) return
  const t = v.currentTime
  // Pre-voice the next stretch so lines are ready before their moment.
  const ahead = lines.value.filter(l => l.t_s >= t && l.t_s < t + 45).map(l => l.id)
  if (ahead.some(id => !audioUrl.value[id])) fetchAudio(ahead)
  const due = lines.value.find(l => !played.has(l.id) && l.t_s <= t && t - l.t_s < 0.8)
  if (due) { played.add(due.id); speak(due, { wait: false }) }
}
function onSeeked() {
  const t = props.videoEl?.currentTime ?? 0
  played = new Set(lines.value.filter(l => l.t_s < t - 0.1).map(l => l.id))
}

async function toggleNarrate() {
  narrate.value = !narrate.value
  const v = props.videoEl
  if (!narrate.value) { stopSpeech(); return }
  audioNote.value = ''
  if (!v) return
  onSeeked()
  await fetchAudio(lines.value.filter(l => l.t_s >= v.currentTime).slice(0, 20).map(l => l.id))
  try { await v.play() } catch { /* user can press play */ }
}

watch(() => props.videoEl, (v, old) => {
  old?.removeEventListener('timeupdate', onTime); old?.removeEventListener('seeked', onSeeked)
  v?.addEventListener('timeupdate', onTime); v?.addEventListener('seeked', onSeeked)
}, { immediate: true })
watch(() => data.value?.run_id, () => { audioUrl.value = {}; played = new Set(); stopSpeech() })
onBeforeUnmount(() => {
  stopSpeech()
  props.videoEl?.removeEventListener('timeupdate', onTime); props.videoEl?.removeEventListener('seeked', onSeeked)
})
</script>

<template>
  <div class="card p-4">
    <div class="mb-1 flex items-center gap-2">
      <span class="text-lg">🎙️</span>
      <div class="font-display text-base font-bold text-slate-800">Shot-by-shot coaching</div>
      <span class="badge-pending ml-auto">Premium</span>
    </div>
    <p class="mb-3 text-xs text-slate-500">Ball-by-ball commentary on every stroke, like a coach watching beside you.</p>

    <div v-if="loading" class="py-6 text-center text-sm text-slate-400">Loading…</div>

    <template v-else>
      <!-- A new version is being analysed (earlier versions stay visible below) -->
      <div v-if="deepStatus === 'analyzing'" class="mb-3 rounded-xl border border-violet-200 bg-violet-50 p-4 text-center">
        <div class="text-sm font-bold text-slate-800">
          Breaking down every stroke{{ isAdmin && latestRun ? ` — Version ${latestRun.version}` : '' }}…
        </div>
        <div class="mt-3 h-2 w-full overflow-hidden rounded-full bg-white">
          <div class="ai-bar h-full rounded-full bg-violet-500"></div>
        </div>
        <p class="mt-2 text-xs text-slate-500">Detecting strokes &amp; writing commentary · {{ fmt(elapsed) }}</p>
        <p class="mt-2 rounded-xl bg-white/70 px-3 py-2 text-xs text-slate-600">
          This usually takes <b>3–8 minutes</b>, depending on the video's length and quality (longer if the servers are busy). It runs quietly in the
          background — you can close this page and come back later.
        </p>
      </div>

      <!-- Latest run failed -->
      <div v-if="deepStatus === 'failed' && latestRun" class="mb-3 rounded-xl border border-red-200 bg-red-50 p-3 text-center">
        <p v-if="isAdmin" class="text-sm text-red-600">Version {{ latestRun.version }} didn’t finish: {{ latestRun.error || video?.deep_error || 'error' }}</p>
        <p v-if="!isAdmin" class="text-sm text-red-600">The latest coaching run didn’t finish. {{ latestRun.error || '' }}</p>
        <button v-if="canManage" :disabled="working" @click="runDeep" class="btn-ghost mt-2 px-4 py-2 text-xs">↻ Try again</button>
      </div>

      <!-- Never run -->
      <div v-if="!doneRuns.length && deepStatus !== 'analyzing'" class="rounded-xl border border-violet-200 bg-violet-50 p-4 text-center">
        <p class="text-sm text-slate-600">Get a coach's stroke-by-stroke breakdown — what each stroke did well, what to fix, and how.</p>
        <button v-if="canManage" :disabled="working" @click="runDeep" class="btn-violet sheen press mt-3 w-full py-2.5 disabled:opacity-50">
          {{ working ? 'Starting…' : '🎙️ Run deep analysis' }}
        </button>
        <p v-else class="mt-2 text-xs text-slate-400">The uploader or a manager can run this.</p>
        <p v-if="err" class="mt-2 text-xs text-red-600">{{ err }}</p>
      </div>

      <!-- A completed version: the timeline -->
      <div v-if="doneRuns.length">
        <div v-if="isAdmin && doneRuns.length > 1" class="mb-3">
          <div class="mb-1 text-[11px] font-bold uppercase tracking-wide text-slate-400">Analysis versions · admin</div>
          <div class="flex flex-wrap gap-1.5">
            <button v-for="r in doneRuns" :key="r.id" @click="showVersion(r.id)"
              class="rounded-full px-2.5 py-1 text-[11px] font-semibold transition"
              :class="shownRun && shownRun.id === r.id ? 'btn-violet' : 'btn-ghost'">
              {{ versionLabel(r, latestRun && latestRun.version) }}
            </button>
          </div>
        </div>
        <p v-if="isAdmin && doneRuns.length === 1 && shownRun" class="mb-3 text-[11px] text-slate-400">{{ versionLabel(shownRun, latestRun && latestRun.version) }}</p>

        <!-- Spoken commentary -->
        <div v-if="lines.length" class="mb-3 rounded-xl border border-violet-200 bg-violet-50 p-3">
          <button @click="toggleNarrate" class="press w-full rounded-lg py-2 text-sm font-bold"
            :class="narrate ? 'btn-violet' : 'btn-ghost'">
            {{ narrate ? '⏸ Stop commentary' : '🔊 Play with commentary' }}
          </button>
          <p class="mt-1.5 text-center text-[11px] text-slate-500">
            {{ narrate ? 'The coach speaks each line as the video reaches that stroke.' : 'Watch the video with the coach talking you through every stroke.' }}
          </p>
          <p v-if="audioNote" class="mt-1 text-center text-[11px] text-amber-600">{{ audioNote }}</p>
        </div>

        <button v-if="commentary.length" @click="showLines = !showLines"
          class="mb-3 flex w-full items-center justify-between rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm font-semibold text-slate-700">
          <span>📝 Every stroke, explained · {{ commentary.length }} notes</span>
          <span class="text-slate-400">{{ showLines ? 'Hide ▴' : 'Show ▾' }}</span>
        </button>

        <div v-if="showLines && subjects.length > 1" class="mb-3 flex flex-wrap gap-1.5">
          <button @click="activePlayer = 'all'" class="rounded-full px-3 py-1 text-xs font-semibold"
            :class="activePlayer === 'all' ? 'btn-primary' : 'btn-ghost'">All</button>
          <button v-for="s in subjects" :key="s.id" @click="activePlayer = s.id"
            class="flex items-center gap-1.5 rounded-full py-1 pl-1 pr-3 text-xs font-semibold"
            :class="activePlayer === s.id ? 'btn-primary' : 'btn-ghost'">
            <img v-if="s.photo" :src="s.photo" alt="" class="h-6 w-6 rounded-full object-cover object-top" />
            <span v-else class="pl-2"></span>
            {{ s.name }}
          </button>
        </div>

        <div v-if="!lines.length && (showLines || !commentary.length)" class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-5 text-center text-sm text-slate-500">
          <template v-if="activePlayer !== 'all'">No clear strokes detected for <b>{{ activeName }}</b> in this version.</template>
          <template v-else>No clear strokes detected in this clip — players may be warming up, or the camera can't see the swings clearly.</template>
        </div>
        <div v-if="lines.length && showLines" class="space-y-2">
          <div v-for="l in lines" :key="l.id" class="rounded-xl border p-3" :class="sevClass(l.severity)">
            <div class="flex items-center gap-2">
              <button @click="emit('seek', l.t_s)"
                class="shrink-0 rounded-md bg-slate-800 px-2 py-0.5 font-mono text-[11px] font-bold text-white">
                ⏱ {{ fmt(l.t_s) }}
              </button>
              <img v-if="byTag[l.tag_id]?.photo" :src="byTag[l.tag_id].photo" alt=""
                class="h-7 w-7 shrink-0 rounded-full border border-white object-cover object-top shadow-sm" />
              <span v-if="byTag[l.tag_id]" class="truncate text-[11px] font-semibold text-cyan-700">{{ byTag[l.tag_id].name }}</span>
              <span v-if="shotType(l)" class="shrink-0 rounded-full border border-slate-200 px-2 py-0.5 text-[10px] font-semibold uppercase text-slate-500">{{ typeLabel(shotType(l)) }}</span>
              <button @click="speaking === l.id ? stopSpeech() : playLine(l)" :aria-label="speaking === l.id ? 'Stop' : 'Hear this line'"
                class="ml-auto shrink-0 rounded-full border border-violet-200 bg-white px-2 py-0.5 text-[11px] font-bold text-violet-700">
                {{ speaking === l.id ? '■' : '🔊' }}
              </button>
              <span class="h-2 w-2 shrink-0 rounded-full" :class="sevDot(l.severity)"></span>
            </div>
            <p class="mt-1.5 text-sm text-slate-700">{{ l.text }}</p>
          </div>
        </div>

        <button v-if="canManage && deepStatus !== 'analyzing'" @click="runDeep" :disabled="working"
          class="btn-ghost mt-3 w-full py-2 text-xs disabled:opacity-50">
          {{ working ? 'Starting…' : isAdmin ? `↻ Re-analyse — saves as Version ${(latestRun ? latestRun.version : 0) + 1} (older versions are kept)` : '↻ Re-analyse' }}
        </button>
        <p class="mt-2 text-center text-[11px] text-slate-400">
          Stroke timing &amp; height come from body-pose tracking. Exact shot names, shuttle placement and footwork need
          shuttle tracking — coming next. The commentary voice is AI-generated.
        </p>
      </div>
    </template>
  </div>
</template>

<style scoped>
.ai-bar { width: 40%; animation: aiSweep 1.4s ease-in-out infinite; }
@keyframes aiSweep { 0% { margin-left: -40%; } 100% { margin-left: 100%; } }
@media (prefers-reduced-motion: reduce) { .ai-bar { animation: none; width: 100%; opacity: .6; } }
</style>
