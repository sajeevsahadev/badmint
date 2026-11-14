<script setup>
// Per-video analysis hub: play → tag who's who (with a photo of each player cropped from the video)
// → (mark court swaps) → run analysis → read the 3-lens report and chat about it. Every run is a
// saved VERSION — re-analysing adds Version N+1 and keeps the earlier ones. Early-access gated.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import { withNicknames } from '../lib/playerNames'
import { getPlaybackUrl } from '../lib/videoStorage'
import { resolveTagName, versionLabel, tagThumbPath, videoTitle } from '../lib/videoAnalysis'
import { useEntitlements } from '../composables/useEntitlements'
import PageHeader from '../components/PageHeader.vue'
import PlayerTagger from '../components/PlayerTagger.vue'
import AnalysisReport from '../components/AnalysisReport.vue'
import AnalysisChat from '../components/AnalysisChat.vue'
import DeepCommentary from '../components/DeepCommentary.vue'
import CoachSummary from '../components/CoachSummary.vue'

const route  = useRoute()
const router = useRouter()
const { isManager } = useClub()
const { user } = useAuth()
const { canQuickReport, canDeepCoaching, isAppAdmin, loadEntitlements } = useEntitlements()
const tier = ref(route.query.tier === 'deep' ? 'deep' : 'quick')   // Quick Report | Deep Coaching
const videoId = route.params.id
const videoEl = ref(null)   // playback element, for deep-commentary timestamp seeking
const coachRef = ref(null)
const deepRunId = ref(null) // deep version currently shown (admins can switch versions)

const loading = ref(true)     // first load only (never re-shown by polling)
const data    = ref(null)
const playUrl = ref('')
const nameMap = ref({})       // player_id -> display name
const thumbUrl = ref({})      // R2 key -> presigned URL (cached)
const retag   = ref(false)
const working = ref(false)
const err     = ref('')
const swapAt  = ref('')
const activeSubject = ref(null)
const selectedRunId = ref(null)
const elapsed = ref(0)        // seconds since analysis started (progress UI)
let   mediaLoaded = false     // fetch playUrl + names once, so the video never reloads on poll
let   elapsedTimer = null

const video   = computed(() => data.value?.video || null)
const tracks  = computed(() => data.value?.tracks || [])
const tags    = computed(() => data.value?.tags || [])
const events  = computed(() => data.value?.events || [])
const metrics = computed(() => data.value?.metrics || [])
const reports = computed(() => data.value?.reports || [])
const runs    = computed(() => data.value?.runs || [])
const doneRuns = computed(() => runs.value.filter(r => r.status === 'done'))
const latestRun = computed(() => runs.value[0] || null)
const shownRun  = computed(() => runs.value.find(r => r.id === data.value?.run_id) || null)
const status  = computed(() => video.value?.status || 'uploaded')
const tagged  = computed(() => video.value?.tag_status === 'tagged' && tags.value.length > 0)
const indexing = computed(() => video.value?.index_status === 'indexing')
// Show reports for marked subjects; if none were marked, fall back to everyone tagged.
const subjects = computed(() => {
  const subs = tags.value.filter(t => t.is_subject)
  return subs.length ? subs : tags.value
})
// Managers OR the person who uploaded/recorded this video can edit tags/swaps (matches RLS).
const canManage = computed(() => isManager() || (!!user.value && video.value?.uploaded_by === user.value.id))

function tagName(t) { return resolveTagName(t, nameMap.value) }
function photoOf(t) { const k = tagThumbPath(t, tracks.value); return k ? thumbUrl.value[k] || '' : '' }
function metricsFor(tagId) { return metrics.value.find(m => m.tag_id === tagId) || null }
function reportsFor(tagId) { return reports.value.filter(r => r.tag_id === tagId) }
const subjectsForDeep = computed(() => subjects.value.map(t => ({ id: t.id, name: tagName(t), photo: photoOf(t) })))

function seekTo(t) {
  const v = videoEl.value
  if (!v) return
  try { v.currentTime = Math.max(0, Number(t) || 0); v.play?.().catch(() => {}); v.scrollIntoView({ behavior: 'smooth', block: 'center' }) } catch { /* ignore */ }
}

onMounted(async () => {
  loadEntitlements()
  await load()
  if (status.value === 'analyzing') startPolling()
  maybeIndex()
})
onBeforeUnmount(() => { stopPolling(); stopIndexPoll() })

let pollTimer = null
function startPolling() {
  stopPolling()
  elapsed.value = 0
  elapsedTimer = setInterval(() => { elapsed.value++ }, 1000)
  let ticks = 0
  const prev = status.value
  pollTimer = setInterval(async () => {
    ticks++
    await load(true)   // SILENT refresh — never flips the page back to the spinner
    if (status.value === 'done' || status.value === 'failed' || ticks > 225) {
      stopPolling()
      if (status.value === 'done' && prev !== 'done') { selectedRunId.value = null; await load(true); notifyDone() }
    }
  }, 4000)
}
function stopPolling() {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  if (elapsedTimer) { clearInterval(elapsedTimer); elapsedTimer = null }
}

// Quick "find the people" pass → a cropped photo of each player for tagging + display.
let indexTimer = null
async function maybeIndex() {
  const hasPhoto = tags.value.some(t => tagThumbPath(t, tracks.value)) || tracks.value.some(t => t.thumb_path)
  if (hasPhoto || !video.value) return
  if (video.value.index_status === 'none') {
    const { error } = await supabase.functions.invoke('analyze-video', { body: { video_id: videoId, mode: 'index' } })
    if (error) return            // engine not configured / not allowed — photos are optional
    await load(true)
  }
  if (video.value?.index_status === 'indexing') {
    let n = 0
    stopIndexPoll()
    indexTimer = setInterval(async () => {
      n++
      await load(true)
      if (video.value?.index_status !== 'indexing' || n > 40) stopIndexPoll()
    }, 4000)
  }
}
function stopIndexPoll() { if (indexTimer) { clearInterval(indexTimer); indexTimer = null } }

// Best-effort local notification when analysis finishes while the page is still open.
function notifyDone() {
  try {
    if ('Notification' in window && Notification.permission === 'granted') {
      new Notification('Match analysis ready', { body: video.value?.title || 'Your report is ready to view.' })
    }
  } catch { /* ignore */ }
}

async function loadThumbs() {
  const keys = new Set()
  for (const t of tags.value) { const k = tagThumbPath(t, tracks.value); if (k) keys.add(k) }
  for (const t of tracks.value) if (t.thumb_path) keys.add(t.thumb_path)
  for (const k of keys) {
    if (thumbUrl.value[k]) continue
    try { const u = await getPlaybackUrl(k); if (u) thumbUrl.value = { ...thumbUrl.value, [k]: u } } catch { /* ignore */ }
  }
}

// load(silent): silent=true refreshes data in place without the full-page spinner or reloading
// the video/roster (those are fetched once). This is what polling uses, so the UI stays stable.
async function load(silent = false) {
  if (!silent) loading.value = true
  const { data: a, error } = await supabase.rpc('get_video_analysis', { p_video_id: videoId, p_run_id: selectedRunId.value })
  if (error || !a) { if (!silent) { err.value = 'Video not found or not accessible.'; loading.value = false } return }
  data.value = a
  err.value = ''   // a successful load clears any stale/transient error
  if (!mediaLoaded) {
    mediaLoaded = true
    if (a.video?.club_id) {
      const { data: pl } = await supabase.from('players')
        .select('id, display_name, user_id').eq('club_id', a.video.club_id)
      const named = await withNicknames(pl ?? [])
      nameMap.value = Object.fromEntries(named.map(p => [p.id, p.display_name]))
    }
    if (a.video?.storage_path) { try { playUrl.value = await getPlaybackUrl(a.video.storage_path) } catch { /* ignore */ } }
  }
  loadThumbs()
  if (subjects.value.length && !activeSubject.value) activeSubject.value = subjects.value[0].id
  if (!silent) loading.value = false
}

async function showVersion(id) { selectedRunId.value = id; await load(true) }

async function onTagged() { retag.value = false; await load(); if (subjects.value.length) activeSubject.value = subjects.value[0].id }

async function addSwap() {
  const t = parseFloat(swapAt.value)
  if (isNaN(t) || t < 0) return
  await supabase.rpc('add_court_event', { p_video_id: videoId, p_at_s: t, p_type: 'end_swap' })
  swapAt.value = ''
  await load(true)
}
async function removeSwap(id) { await supabase.rpc('remove_court_event', { p_event_id: id }); await load(true) }

// Dispatches to the real engine (Modal) as a NEW version. Runs in the background — the server keeps
// analysing even if you leave; we poll for status. Falls back to a sample only if the engine is off.
async function runAnalysis() {
  working.value = true; err.value = ''
  try {
    try { if ('Notification' in window && Notification.permission === 'default') await Notification.requestPermission() } catch { /* ignore */ }
    const { data: d, error } = await supabase.functions.invoke('analyze-video', { body: { video_id: videoId, mode: 'simple' } })
    if (error || d?.error) {
      const { error: se } = await supabase.rpc('seed_mock_analysis', { p_video_id: videoId })
      if (se) throw se
      selectedRunId.value = null
      await load(true)
    } else {
      await load(true)
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
    <PageHeader icon="✨" :title="video ? videoTitle(video, tags, nameMap) : 'Match analysis'"
      :subtitle="video ? (video.game_type + ' · ' + (video.source === 'upload' ? 'uploaded' : 'recorded')) : ''" />

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading…</div>
    <div v-else-if="err && !data" class="card p-6 text-center text-red-600">{{ err }}</div>

    <template v-else>
      <!-- Playback -->
      <div v-if="playUrl" class="mb-4 overflow-hidden rounded-xl bg-black">
        <video ref="videoEl" :src="playUrl" controls playsinline class="w-full"></video>
      </div>

      <!-- Step 1: tagging -->
      <div v-if="!tagged || retag" class="mb-4">
        <p v-if="indexing" class="mb-2 text-center text-xs text-slate-400">📸 Finding the players in your video…</p>
        <PlayerTagger v-if="canManage" :video-id="videoId" :club-id="video.club_id" :game-type="video.game_type"
          :tracks="tracks" :existing-tags="tags" :photos="thumbUrl" @saved="onTagged" @cancel="retag = false" />
        <div v-else class="card p-6 text-center text-sm text-slate-500">
          This video hasn't been tagged yet. Only the uploader or a club manager can tag the players.
        </div>
      </div>

      <!-- Tagged summary + actions -->
      <template v-else>
        <!-- Players: one compact strip (names + photos), not a block of cards -->
        <div class="card mb-3 flex items-center gap-2 px-3 py-2.5">
          <div class="flex min-w-0 flex-1 flex-wrap gap-x-3 gap-y-1.5">
            <div v-for="t in tags" :key="t.id" class="flex items-center gap-1.5">
              <img v-if="photoOf(t)" :src="photoOf(t)" :alt="tagName(t)"
                class="h-8 w-8 shrink-0 rounded-full bg-slate-100 object-cover object-top" />
              <span v-else class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-100 text-xs">👤</span>
              <span class="max-w-[7.5rem] truncate text-xs font-semibold text-slate-700">{{ tagName(t) }}</span>
            </div>
          </div>
          <button v-if="canManage" @click="retag = true" class="shrink-0 text-xs font-semibold text-neon">Fix names</button>
        </div>
        <p v-if="indexing" class="-mt-1 mb-3 text-center text-[11px] text-slate-400">📸 Capturing player photos from the video…</p>

        <!-- Court swaps: rarely needed, so folded away -->
        <details v-if="canManage" class="card mb-4 px-4 py-2.5" :open="events.length > 0">
          <summary class="cursor-pointer text-xs font-semibold text-slate-500">
            ↔ Players changed ends during this video?<span v-if="events.length" class="text-cyan-600"> · {{ events.length }} added</span>
          </summary>
          <p class="mt-2 text-xs text-slate-400">Add the time (in seconds) they changed ends. Positions flip from that point.</p>
          <div v-for="e in events" :key="e.id" class="mt-2 flex items-center justify-between text-sm">
            <span class="text-slate-600">↔ Ends swapped at {{ fmtClock(e.at_s) }}</span>
            <button @click="removeSwap(e.id)" class="text-xs text-red-500">Remove</button>
          </div>
          <div class="mt-2 flex gap-2">
            <input v-model="swapAt" type="number" min="0" placeholder="e.g. 420"
              class="w-28 rounded-lg border border-slate-200 px-2 py-1.5 text-sm focus:border-cyan-400 focus:outline-none" />
            <button @click="addSwap" class="btn-ghost px-3 py-1.5 text-xs">+ Add swap</button>
          </div>
        </details>

        <!-- AI Match Analysis tiers. Each is gated by its own entitlement so subscriptions slot in later. -->
        <!-- Two separate products: pick one (cards), its content lives in its own framed panel below. -->
        <div class="mb-3 grid grid-cols-2 gap-2.5" role="tablist" aria-label="Analysis type">
          <button role="tab" :aria-selected="tier === 'quick'" @click="tier = 'quick'"
            class="tier-tab" :class="tier === 'quick' ? 'tier-tab-quick' : ''">
            <span class="flex items-center justify-between">
              <span class="tier-icon bg-cyan-50 text-cyan-600">📊</span>
              <span v-if="tier === 'quick'" class="tier-check bg-cyan-500">✓</span>
            </span>
            <span class="mt-2 block text-[15px] font-bold text-slate-800">Quick Report</span>
            <span class="mt-0.5 block text-[11px] leading-snug text-slate-500">Ratings, coach &amp; physio view, AI chat</span>
          </button>
          <button role="tab" :aria-selected="tier === 'deep'" @click="tier = 'deep'"
            class="tier-tab" :class="tier === 'deep' ? 'tier-tab-deep' : ''">
            <span class="flex items-center justify-between">
              <span class="tier-icon bg-violet-50 text-violet-600">🎙️</span>
              <span v-if="tier === 'deep'" class="tier-check bg-violet-500">✓</span>
              <span v-else class="rounded-full bg-amber-100 px-2 py-0.5 text-[9px] font-bold tracking-wide text-amber-700">PREMIUM</span>
            </span>
            <span class="mt-2 block text-[15px] font-bold text-slate-800">Deep Coaching</span>
            <span class="mt-0.5 block text-[11px] leading-snug text-slate-500">Head coach report, voice, every stroke</span>
          </button>
        </div>

        <section class="tier-panel" :class="tier === 'deep' ? 'tier-panel-deep' : 'tier-panel-quick'">
        <header class="tier-head">
          <div class="min-w-0">
            <div class="text-[10px] font-bold uppercase tracking-[0.14em]"
              :class="tier === 'deep' ? 'text-violet-600' : 'text-cyan-700'">
              {{ tier === 'deep' ? 'Premium · Deep Coaching' : 'Quick Report' }}
            </div>
            <div class="mt-0.5 text-base font-bold text-slate-800">
              {{ tier === 'deep' ? 'Your head coach’s breakdown' : 'Match overview per player' }}
            </div>
            <p class="mt-0.5 text-xs text-slate-500">
              {{ tier === 'deep'
                ? 'KPIs vs your last match, a coach verdict you can listen to, drills — and every stroke explained.'
                : 'Movement and technique ratings with coach, physio and player views. Ask the AI anything.' }}
            </p>
          </div>
        </header>
        <div class="tier-body">

        <!-- Locked tier (shown once subscriptions are live and the user's plan doesn't include it) -->
        <div v-if="(tier === 'quick' && !canQuickReport) || (tier === 'deep' && !canDeepCoaching)"
          class="card p-6 text-center">
          <div class="text-2xl">🔒</div>
          <div class="mt-1 text-sm font-semibold text-slate-800">{{ tier === 'deep' ? 'Deep Coaching' : 'Quick Report' }} isn't included in your plan</div>
          <p class="mt-1 text-xs text-slate-500">It's rolling out to early-access members first.</p>
        </div>

        <template v-if="tier === 'quick' && canQuickReport">
        <!-- Analysing — stable, non-blocking progress (safe to leave the page) -->
        <div v-if="status === 'analyzing'" class="card card-neon p-5 mb-4 text-center fade-up">
          <div class="text-base font-bold text-slate-800">
            Analysing your match{{ isAppAdmin && latestRun ? ` — Version ${latestRun.version}` : '' }}…
          </div>
          <div class="mt-3 h-2 w-full overflow-hidden rounded-full bg-slate-100">
            <div class="ai-bar h-full rounded-full bg-cyan-500"></div>
          </div>
          <p class="mt-2 text-xs text-slate-500">
            Running pose &amp; movement analysis · {{ fmtClock(elapsed) }} elapsed
          </p>
          <p class="mt-1 text-[11px] text-slate-400">
            This runs in the background — you can leave this page and come back; we'll notify you when the report is ready.
          </p>
        </div>

        <!-- No completed version yet: ready / failed -->
        <div v-else-if="!doneRuns.length" class="card card-neon p-4 mb-4 text-center">
          <div class="text-sm font-semibold text-slate-800">
            {{ status === 'failed' ? 'Analysis didn’t finish' : 'Ready to analyse' }}
          </div>
          <p v-if="status === 'failed'" class="mt-1 text-xs text-red-600">{{ video.error || 'Something went wrong. Please try again.' }}</p>
          <p v-else class="mt-1 text-xs text-slate-500">
            Get a per-player report across coach, physio and your own view. Takes a minute or two to process.
          </p>
          <template v-if="canManage">
            <button :disabled="working" @click="runAnalysis" class="btn-primary sheen press mt-3 w-full py-2.5 disabled:opacity-50">
              {{ working ? 'Starting…' : (status === 'failed' ? '↻ Try again' : '✨ Run analysis') }}
            </button>
          </template>
          <p v-else class="mt-2 text-xs text-slate-400">The uploader or a manager can run the analysis.</p>
          <p v-if="err" class="mt-2 text-xs text-red-600">{{ err }}</p>
        </div>

        <!-- Reports for the selected version -->
        <div v-if="doneRuns.length && subjects.length">
          <p v-if="latestRun && latestRun.status === 'failed'" class="mb-3 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-700">
            <template v-if="isAppAdmin">Version {{ latestRun.version }} didn’t finish ({{ latestRun.error || 'error' }}). Showing your last completed version.</template>
            <template v-else>The latest re-analysis didn’t finish — showing your previous report.</template>
          </p>

          <!-- Version history is an admin tool; members always see the latest report. -->
          <div v-if="isAppAdmin && doneRuns.length > 1" class="mb-3">
            <div class="mb-1 text-[11px] font-bold uppercase tracking-wide text-slate-400">Analysis versions</div>
            <div class="flex flex-wrap gap-1.5">
              <button v-for="r in doneRuns" :key="r.id" @click="showVersion(r.id)"
                class="rounded-full px-2.5 py-1 text-[11px] font-semibold transition"
                :class="shownRun && shownRun.id === r.id ? 'btn-primary' : 'btn-ghost'">
                {{ versionLabel(r, latestRun && latestRun.version) }}
              </button>
            </div>
          </div>
          <p v-else-if="isAppAdmin && shownRun" class="mb-3 text-[11px] text-slate-400">{{ versionLabel(shownRun, latestRun && latestRun.version) }}</p>

          <div v-if="subjects.length > 1" class="mb-3 flex flex-wrap gap-2">
            <button v-for="t in subjects" :key="t.id" @click="activeSubject = t.id"
              class="flex items-center gap-1.5 rounded-full py-1 pl-1 pr-3 text-sm font-semibold transition"
              :class="activeSubject === t.id ? 'btn-primary' : 'btn-ghost'">
              <img v-if="photoOf(t)" :src="photoOf(t)" alt="" class="h-6 w-6 rounded-full object-cover object-top" />
              <span v-else class="pl-2"></span>
              {{ tagName(t) }}
            </button>
          </div>

          <AnalysisReport v-if="activeSubject"
            :name="tagName(subjects.find(s => s.id === activeSubject))"
            :photo="photoOf(subjects.find(s => s.id === activeSubject))"
            :metrics="metricsFor(activeSubject)"
            :reports="reportsFor(activeSubject)"
            class="mb-4" />

          <AnalysisChat v-if="activeSubject"
            :video-id="videoId" :tag-id="activeSubject"
            :name="tagName(subjects.find(s => s.id === activeSubject))" />

          <button v-if="canManage && status !== 'analyzing'" @click="runAnalysis" :disabled="working"
            class="btn-ghost mt-3 w-full py-2 text-xs disabled:opacity-50">
            {{ working ? 'Starting…' : (isAppAdmin
              ? `↻ Re-analyse — saves as Version ${(latestRun ? latestRun.version : 0) + 1} (older versions are kept)`
              : '↻ Re-analyse') }}
          </button>
        </div>
        </template>

        <!-- Deep Coaching (premium): stroke-by-stroke commentary + spoken audio -->
        <!-- Head Coach Report first: KPIs, verdict, voice, progress. Then the full stroke-by-stroke detail. -->
        <CoachSummary v-if="tier === 'deep' && canDeepCoaching" ref="coachRef" class="mb-3"
          :video-id="videoId" :run-id="deepRunId" :subjects="subjectsForDeep" :play-url="playUrl" />
        <DeepCommentary v-if="tier === 'deep' && canDeepCoaching" :video-id="videoId" :can-manage="canManage" :is-admin="isAppAdmin"
          :subjects="subjectsForDeep" :video-el="videoEl" @seek="seekTo"
          @run="id => deepRunId = id" @done="coachRef?.load()" />
        </div>
        </section>
      </template>
    </template>
  </div>
</template>

<style scoped>
/* Tier picker + framed panel: Quick (cyan) and Deep (violet) read as two separate products. */
.tier-tab {
  text-align: left; border-radius: 1.1rem; padding: 0.8rem 0.85rem; background: #fff;
  border: 1.5px solid #e2e8f0; box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  transition: border-color .15s, box-shadow .15s, transform .15s;
}
.tier-tab:active { transform: scale(0.98); }
.tier-tab-quick { border-color: #22b8d8; box-shadow: 0 6px 18px -8px rgba(0, 153, 184, 0.45); }
.tier-tab-deep  { border-color: #8b5cf6; box-shadow: 0 6px 18px -8px rgba(139, 92, 246, 0.5); }
.tier-icon { display: inline-flex; height: 2rem; width: 2rem; align-items: center; justify-content: center; border-radius: 0.7rem; font-size: 1rem; }
.tier-check { display: inline-flex; height: 1.25rem; width: 1.25rem; align-items: center; justify-content: center; border-radius: 9999px; color: #fff; font-size: 0.7rem; font-weight: 700; }

.tier-panel { border-radius: 1.5rem; overflow: hidden; border: 1.5px solid; margin-bottom: 1rem; background: #fff; }
.tier-panel-quick { border-color: #bdeaf5; }
.tier-panel-deep  { border-color: #ddd0fd; }
.tier-head { padding: 0.95rem 1rem 0.85rem; border-bottom: 1px solid; }
.tier-panel-quick .tier-head { background: linear-gradient(135deg, #e8f9fd, #ffffff); border-color: #d5f1f8; border-left: 4px solid #00b4d8; }
.tier-panel-deep  .tier-head { background: linear-gradient(135deg, #f3edff, #ffffff); border-color: #ebe3fe; border-left: 4px solid #8b5cf6; }
.tier-body { padding: 0.75rem; }
.tier-panel-quick .tier-body { background: #f6fcfe; }
.tier-panel-deep  .tier-body { background: #faf8ff; }
/* Indeterminate progress sweep — honest "working" signal, no fake percentage. */
.ai-bar { width: 40%; animation: aiSweep 1.4s ease-in-out infinite; }
@keyframes aiSweep {
  0%   { margin-left: -40%; }
  100% { margin-left: 100%; }
}
@media (prefers-reduced-motion: reduce) {
  .ai-bar { animation: none; width: 100%; opacity: 0.6; }
}
</style>
