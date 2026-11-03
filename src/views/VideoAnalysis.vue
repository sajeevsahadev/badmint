<script setup>
// Per-video analysis hub: play → tag who's who → (mark court swaps) → run analysis → read the
// 3-lens report and chat about it. One video, one page. Early-access gated at the router.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import { withNicknames } from '../lib/playerNames'
import { getPlaybackUrl } from '../lib/videoStorage'
import { resolveTagName } from '../lib/videoAnalysis'
import PageHeader from '../components/PageHeader.vue'
import PlayerTagger from '../components/PlayerTagger.vue'
import AnalysisReport from '../components/AnalysisReport.vue'
import AnalysisChat from '../components/AnalysisChat.vue'

const route  = useRoute()
const router = useRouter()
const { isManager } = useClub()
const { user } = useAuth()
const videoId = route.params.id

const loading = ref(true)
const data    = ref(null)
const playUrl = ref('')
const nameMap = ref({})       // player_id -> display name
const retag   = ref(false)
const working = ref(false)
const err     = ref('')
const swapAt  = ref('')
const activeSubject = ref(null)

const video   = computed(() => data.value?.video || null)
const tracks  = computed(() => data.value?.tracks || [])
const tags    = computed(() => data.value?.tags || [])
const events  = computed(() => data.value?.events || [])
const metrics = computed(() => data.value?.metrics || [])
const reports = computed(() => data.value?.reports || [])
const status  = computed(() => video.value?.status || 'uploaded')
const tagged  = computed(() => video.value?.tag_status === 'tagged' && tags.value.length > 0)
// Show reports for marked subjects; if none were marked, fall back to everyone tagged.
const subjects = computed(() => {
  const subs = tags.value.filter(t => t.is_subject)
  return subs.length ? subs : tags.value
})
// Managers OR the person who uploaded/recorded this video can edit tags/swaps (matches RLS).
const canManage = computed(() => isManager() || (!!user.value && video.value?.uploaded_by === user.value.id))

function tagName(t) { return resolveTagName(t, nameMap.value) }
function metricsFor(tagId) { return metrics.value.find(m => m.tag_id === tagId) || null }
function reportsFor(tagId) { return reports.value.filter(r => r.tag_id === tagId) }

onMounted(async () => { await load(); if (status.value === 'analyzing') startPolling() })
onBeforeUnmount(stopPolling)

let pollTimer = null
function startPolling() {
  stopPolling()
  let ticks = 0
  pollTimer = setInterval(async () => {
    ticks++
    await load()
    if (subjects.value.length && !activeSubject.value) activeSubject.value = subjects.value[0].id
    if (status.value === 'done' || status.value === 'failed' || ticks > 90) stopPolling()
  }, 5000)
}
function stopPolling() { if (pollTimer) { clearInterval(pollTimer); pollTimer = null } }

async function load() {
  loading.value = true
  const { data: a, error } = await supabase.rpc('get_video_analysis', { p_video_id: videoId })
  if (error || !a) { err.value = 'Video not found or not accessible.'; loading.value = false; return }
  data.value = a
  // roster names for the video's club
  if (a.video?.club_id) {
    const { data: pl } = await supabase.from('players')
      .select('id, display_name, user_id').eq('club_id', a.video.club_id)
    const named = await withNicknames(pl ?? [])
    nameMap.value = Object.fromEntries(named.map(p => [p.id, p.display_name]))
  }
  if (a.video?.storage_path) { try { playUrl.value = await getPlaybackUrl(a.video.storage_path) } catch { /* ignore */ } }
  if (subjects.value.length && !activeSubject.value) activeSubject.value = subjects.value[0].id
  loading.value = false
}

async function onTagged() { retag.value = false; await load(); if (subjects.value.length) activeSubject.value = subjects.value[0].id }

async function addSwap() {
  const t = parseFloat(swapAt.value)
  if (isNaN(t) || t < 0) return
  await supabase.rpc('add_court_event', { p_video_id: videoId, p_at_s: t, p_type: 'end_swap' })
  swapAt.value = ''
  await load()
}
async function removeSwap(id) { await supabase.rpc('remove_court_event', { p_event_id: id }); await load() }

// Tries the real engine (Modal via analyze-video). Until that's wired, the function returns 503 and
// we fall back to a clearly-labelled sample analysis so the experience works today.
async function runAnalysis() {
  working.value = true; err.value = ''
  try {
    const { data, error } = await supabase.functions.invoke('analyze-video', { body: { video_id: videoId } })
    if (error || data?.error) {
      const { error: se } = await supabase.rpc('seed_mock_analysis', { p_video_id: videoId })
      if (se) throw se
      await load()
    } else {
      await load()
      if (status.value === 'analyzing') startPolling()
    }
    if (subjects.value.length) activeSubject.value = subjects.value[0].id
  } catch (e) {
    err.value = e?.message || 'Analysis failed.'
  } finally { working.value = false }
}

function fmtClock(s) { const m = Math.floor(s / 60), x = Math.round(s % 60); return `${m}:${String(x).padStart(2, '0')}` }
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <button @click="router.back()" class="mb-2 text-sm text-slate-500">‹ Back</button>
    <PageHeader icon="✨" :title="video?.title || 'Match analysis'"
      :subtitle="video ? (video.game_type + ' · ' + (video.source === 'upload' ? 'uploaded' : 'recorded')) : ''" />

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading…</div>
    <div v-else-if="err && !data" class="card p-6 text-center text-red-600">{{ err }}</div>

    <template v-else>
      <!-- Playback -->
      <div v-if="playUrl" class="mb-4 overflow-hidden rounded-xl bg-black">
        <video :src="playUrl" controls playsinline class="w-full"></video>
      </div>

      <!-- Step 1: tagging -->
      <div v-if="!tagged || retag" class="mb-4">
        <PlayerTagger v-if="canManage" :video-id="videoId" :club-id="video.club_id" :game-type="video.game_type"
          :tracks="tracks" :existing-tags="tags" @saved="onTagged" @cancel="retag = false" />
        <div v-else class="card p-6 text-center text-sm text-slate-500">
          This video hasn't been tagged yet. Only the uploader or a club manager can tag the players.
        </div>
      </div>

      <!-- Tagged summary + actions -->
      <template v-else>
        <div class="card p-4 mb-4">
          <div class="mb-2 flex items-center justify-between">
            <div class="text-xs font-bold uppercase tracking-wide text-slate-500">Players in this video</div>
            <button v-if="canManage" @click="retag = true" class="text-xs font-semibold text-neon">Fix tags</button>
          </div>
          <div class="flex flex-wrap gap-2">
            <span v-for="t in tags" :key="t.id"
              class="rounded-full border border-slate-200 px-3 py-1 text-xs text-slate-600">
              {{ tagName(t) }}<span v-if="t.is_subject" class="ml-1 text-cyan-600">• analysed</span>
            </span>
          </div>
        </div>

        <!-- Court swaps -->
        <div v-if="canManage" class="card p-4 mb-4">
          <div class="text-xs font-bold uppercase tracking-wide text-slate-500">Court changes (ends swapped)</div>
          <p class="mt-1 text-xs text-slate-400">Add the time (seconds) players changed ends, if any. Positions flip from that point.</p>
          <div v-for="e in events" :key="e.id" class="mt-2 flex items-center justify-between text-sm">
            <span class="text-slate-600">↔ Ends swapped at {{ fmtClock(e.at_s) }}</span>
            <button @click="removeSwap(e.id)" class="text-xs text-red-500">Remove</button>
          </div>
          <div class="mt-2 flex gap-2">
            <input v-model="swapAt" type="number" min="0" placeholder="e.g. 420"
              class="w-28 rounded-lg border border-slate-200 px-2 py-1.5 text-sm focus:border-cyan-400 focus:outline-none" />
            <button @click="addSwap" class="btn-ghost px-3 py-1.5 text-xs">+ Add swap</button>
          </div>
        </div>

        <!-- Run analysis -->
        <div v-if="status !== 'done'" class="card card-neon p-4 mb-4 text-center">
          <div class="text-sm font-semibold text-slate-800">
            {{ status === 'analyzing' ? 'Analysis in progress…' : 'Ready to analyse' }}
          </div>
          <p class="mt-1 text-xs text-slate-500">
            We'll produce a per-player report across coach, physio and your own view.
          </p>
          <template v-if="canManage">
            <button :disabled="working" @click="runAnalysis" class="btn-primary sheen press mt-3 w-full py-2.5 disabled:opacity-50">
              {{ working ? 'Analysing…' : '✨ Run analysis' }}
            </button>
            <p class="mt-2 text-[11px] text-amber-600">
              Early access: this currently returns <b>sample analysis</b> while our vision engine finishes training on real footage.
            </p>
          </template>
          <p v-else class="mt-2 text-xs text-slate-400">The uploader or a manager can run the analysis.</p>
          <p v-if="err" class="mt-2 text-xs text-red-600">{{ err }}</p>
        </div>

        <!-- Reports -->
        <div v-if="status === 'done' && subjects.length">
          <div v-if="subjects.length > 1" class="mb-3 flex flex-wrap gap-2">
            <button v-for="t in subjects" :key="t.id" @click="activeSubject = t.id"
              class="rounded-full px-3 py-1.5 text-sm font-semibold transition"
              :class="activeSubject === t.id ? 'btn-primary' : 'btn-ghost'">
              {{ tagName(t) }}
            </button>
          </div>

          <AnalysisReport v-if="activeSubject"
            :name="tagName(subjects.find(s => s.id === activeSubject))"
            :metrics="metricsFor(activeSubject)"
            :reports="reportsFor(activeSubject)"
            class="mb-4" />

          <AnalysisChat v-if="activeSubject"
            :video-id="videoId" :tag-id="activeSubject"
            :name="tagName(subjects.find(s => s.id === activeSubject))" />

          <button v-if="canManage" @click="runAnalysis" :disabled="working" class="btn-ghost mt-3 w-full py-2 text-xs disabled:opacity-50">
            {{ working ? 'Re-running…' : '↻ Re-run analysis' }}
          </button>
        </div>
      </template>
    </template>
  </div>
</template>
