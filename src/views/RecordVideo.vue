<script setup>
// AI Video Coaching — Phase 0: record a match video, tag the players on court,
// capture consent, and store it. No analysis yet — this proves the capture +
// upload + playback loop on real phones before we turn on the AI pipeline.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { withNicknames } from '../lib/playerNames'
import { uploadMatchVideo, getPlaybackUrl, deleteMatchVideo } from '../lib/videoStorage'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()

// ── Setup state ──────────────────────────────────────────────────────────────
const gameType  = ref('doubles')              // 'singles' | 'doubles'
const players   = ref([])
const selected  = ref(new Set())
const title     = ref('')
const consent   = ref(false)
const requiredCount = computed(() => (gameType.value === 'singles' ? 2 : 4))

// ── Recording state ──────────────────────────────────────────────────────────
const stage       = ref('setup')              // setup | record | review | done
const liveVideo   = ref(null)
const reviewVideo = ref(null)
let   stream      = null
let   recorder    = null
let   chunks      = []
const recording   = ref(false)
const elapsed     = ref(0)
let   timer       = null
const recordedBlob = ref(null)
const recordedUrl  = ref('')
const mimeUsed     = ref('')
const camError     = ref('')

// ── Upload state ─────────────────────────────────────────────────────────────
const uploading   = ref(false)
const uploadError = ref('')
const myVideos    = ref([])

onMounted(async () => { await loadPlayers(); await loadMyVideos() })
onBeforeUnmount(stopCamera)

async function loadPlayers() {
  if (!currentClub.value) return
  const { data } = await supabase.from('players')
    .select('id, display_name, elo, user_id')
    .eq('club_id', currentClub.value.club_id)
    .eq('is_active', true)
    .order('display_name')
  players.value = await withNicknames(data ?? [])
}

function toggle(id) {
  const s = new Set(selected.value)
  if (s.has(id)) s.delete(id)
  else if (s.size < requiredCount.value) s.add(id)
  selected.value = s
}

const canRecord = computed(() =>
  consent.value && selected.value.size === requiredCount.value && !!currentClub.value)

function fmt(s) {
  const m = Math.floor(s / 60), x = s % 60
  return `${m}:${String(x).padStart(2, '0')}`
}

// Pick the best container the phone's MediaRecorder actually supports.
function pickMime() {
  const prefs = [
    'video/mp4;codecs=h264,aac',
    'video/webm;codecs=vp9,opus',
    'video/webm;codecs=vp8,opus',
    'video/webm',
  ]
  for (const m of prefs) {
    if (window.MediaRecorder?.isTypeSupported?.(m)) return m
  }
  return ''
}

async function startCamera() {
  camError.value = ''
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: { ideal: 'environment' },     // rear camera for filming the court
        width:  { ideal: 1280 },
        height: { ideal: 720 },
        frameRate: { ideal: 30 },
      },
      audio: true,
    })
    stage.value = 'record'
    // wait a tick for the <video> to mount, then attach the stream
    requestAnimationFrame(() => {
      if (liveVideo.value) { liveVideo.value.srcObject = stream; liveVideo.value.play().catch(() => {}) }
    })
  } catch (e) {
    camError.value = e?.name === 'NotAllowedError'
      ? 'Camera/mic permission was blocked. Allow access in your browser settings and try again.'
      : (e?.message || 'Could not start the camera.')
  }
}

function startRecording() {
  if (!stream) return
  chunks = []
  mimeUsed.value = pickMime()
  try {
    recorder = new MediaRecorder(stream, {
      ...(mimeUsed.value ? { mimeType: mimeUsed.value } : {}),
      videoBitsPerSecond: 2_500_000,   // ~720p30 — small file, keeps footwork/arms crisp
      audioBitsPerSecond: 64_000,
    })
  } catch {
    recorder = new MediaRecorder(stream)
  }
  recorder.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data) }
  recorder.onstop = finishRecording
  recorder.start(1000)             // gather data every 1s so nothing is lost on stop
  recording.value = true
  elapsed.value = 0
  timer = setInterval(() => { elapsed.value++ }, 1000)
}

function stopRecording() {
  if (recorder && recording.value) recorder.stop()
  recording.value = false
  if (timer) { clearInterval(timer); timer = null }
}

function finishRecording() {
  const type = mimeUsed.value || (chunks[0]?.type) || 'video/webm'
  recordedBlob.value = new Blob(chunks, { type })
  recordedUrl.value  = URL.createObjectURL(recordedBlob.value)
  stage.value = 'review'
  stopCamera()                     // release the camera once we have the clip
  requestAnimationFrame(() => {
    if (reviewVideo.value) reviewVideo.value.src = recordedUrl.value
  })
}

function stopCamera() {
  if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null }
}

function reRecord() {
  if (recordedUrl.value) URL.revokeObjectURL(recordedUrl.value)
  recordedBlob.value = null; recordedUrl.value = ''
  elapsed.value = 0
  startCamera()
}

async function upload() {
  if (!recordedBlob.value || !currentClub.value) return
  uploading.value = true; uploadError.value = ''
  try {
    const videoId = crypto.randomUUID()
    const path = await uploadMatchVideo(recordedBlob.value, {
      clubId: currentClub.value.club_id,
      videoId,
      contentType: recordedBlob.value.type,
    })
    const { error } = await supabase.from('match_videos').insert({
      id: videoId,
      club_id: currentClub.value.club_id,
      title: title.value?.trim() || `Match video · ${new Date().toLocaleDateString()}`,
      game_type: gameType.value,
      player_ids: [...selected.value],
      consent: true,
      storage_path: path,
      duration_s: elapsed.value,
      size_bytes: recordedBlob.value.size,
      status: 'uploaded',
    })
    if (error) throw error
    stage.value = 'done'
    await loadMyVideos()
  } catch (e) {
    uploadError.value = e?.message || 'Upload failed. Check your connection and try again.'
  } finally {
    uploading.value = false
  }
}

function resetAll() {
  if (recordedUrl.value) URL.revokeObjectURL(recordedUrl.value)
  recordedBlob.value = null; recordedUrl.value = ''
  selected.value = new Set(); consent.value = false; title.value = ''
  elapsed.value = 0; uploadError.value = ''
  stage.value = 'setup'
}

// ── My recordings ────────────────────────────────────────────────────────────
async function loadMyVideos() {
  if (!currentClub.value) return
  const { data } = await supabase.from('match_videos')
    .select('id, title, game_type, duration_s, size_bytes, storage_path, status, created_at')
    .eq('club_id', currentClub.value.club_id)
    .order('created_at', { ascending: false })
    .limit(20)
  myVideos.value = data ?? []
}

const playing = ref(null)          // { id, url }
async function play(v) {
  const url = await getPlaybackUrl(v.storage_path)
  if (url) playing.value = { id: v.id, url }
}

async function remove(v) {
  if (!confirm('Delete this recording? This cannot be undone.')) return
  await deleteMatchVideo(v.storage_path)
  await supabase.from('match_videos').delete().eq('id', v.id)
  if (playing.value?.id === v.id) playing.value = null
  await loadMyVideos()
}

function mb(bytes) { return bytes ? (bytes / 1048576).toFixed(1) + ' MB' : '—' }
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <PageHeader icon="🎥" title="Record Match"
      subtitle="Film a match to get AI coaching (analysis coming soon). Prop your phone up in landscape so the whole court is in frame.">
      <template #help>
        <p class="text-sm text-slate-600">
          Place the phone on a tripod or lean it on the fence, capturing the full court side-on.
          Keep clips short while we test (1–3 min). After analysis launches, this same footage
          gives each player a footwork, shot and positioning report.
        </p>
      </template>
    </PageHeader>

    <div v-if="!currentClub" class="card p-6 text-center text-slate-500">
      Select a club first to record a match.
    </div>

    <!-- ── STEP 1: Setup ─────────────────────────────────────────────────── -->
    <div v-if="currentClub && stage === 'setup'">
      <div class="card p-4 mb-4">
        <div class="text-xs font-bold uppercase tracking-wide text-slate-500 mb-2">Match type</div>
        <div class="flex gap-2">
          <button @click="gameType='singles'; selected=new Set()"
            class="flex-1 rounded-xl py-2 text-sm font-semibold transition"
            :class="gameType==='singles' ? 'btn-primary' : 'btn-ghost'">🏸 Singles</button>
          <button @click="gameType='doubles'; selected=new Set()"
            class="flex-1 rounded-xl py-2 text-sm font-semibold transition"
            :class="gameType==='doubles' ? 'btn-primary' : 'btn-ghost'">👥 Doubles</button>
        </div>
      </div>

      <div class="card p-4 mb-4">
        <div class="flex items-center justify-between mb-2">
          <div class="text-xs font-bold uppercase tracking-wide text-slate-500">
            Who's playing?
          </div>
          <div class="text-xs font-semibold"
            :class="selected.size === requiredCount ? 'text-emerald-600' : 'text-slate-400'">
            {{ selected.size }} / {{ requiredCount }} selected
          </div>
        </div>
        <div v-if="!players.length" class="text-sm text-slate-400 py-3">No active players in this club.</div>
        <div class="grid grid-cols-2 gap-2">
          <button v-for="p in players" :key="p.id" @click="toggle(p.id)"
            class="flex items-center gap-2 rounded-xl border px-3 py-2 text-left text-sm transition"
            :class="selected.has(p.id)
              ? 'border-cyan-500 bg-cyan-50 font-semibold text-cyan-800'
              : 'border-slate-200 text-slate-600 hover:border-slate-300'">
            <span class="truncate">{{ p.display_name }}</span>
          </button>
        </div>
        <p class="mt-2 text-xs text-slate-400">
          We tag who's in the video now; the AI will match each person on court to these players later.
        </p>
      </div>

      <div class="card p-4 mb-4">
        <label class="text-xs font-bold uppercase tracking-wide text-slate-500">Title (optional)</label>
        <input v-model="title" type="text" placeholder="e.g. Saturday 6am — Court 2"
          class="mt-2 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-cyan-400 focus:outline-none" />
      </div>

      <!-- Consent — ethical + GDPR. Recording is blocked until this is ticked. -->
      <label class="card card-amber mb-4 flex items-start gap-3 p-4 cursor-pointer">
        <input type="checkbox" v-model="consent" class="mt-0.5 h-5 w-5 shrink-0 accent-cyan-600" />
        <span class="text-sm text-slate-700">
          <b>Everyone on court agrees to be recorded</b> for coaching analysis. The video is private
          to this club and is deleted after analysis (or kept only as a private link).
        </span>
      </label>

      <button :disabled="!canRecord" @click="startCamera"
        class="btn-primary w-full py-3 text-base disabled:opacity-40 disabled:cursor-not-allowed">
        🎬 Open camera
      </button>
      <p v-if="!canRecord" class="mt-2 text-center text-xs text-slate-400">
        Pick {{ requiredCount }} players and tick consent to continue.
      </p>

      <div v-if="myVideos.length" class="mt-8">
        <div class="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500">Recent recordings</div>
        <div v-for="v in myVideos" :key="v.id" class="card p-3 mb-2">
          <div class="flex items-center justify-between gap-2">
            <div class="min-w-0">
              <div class="truncate text-sm font-semibold text-slate-800">{{ v.title }}</div>
              <div class="text-xs text-slate-400">
                {{ v.game_type }} · {{ fmt(v.duration_s || 0) }} · {{ mb(v.size_bytes) }} ·
                <span class="badge-pending">{{ v.status }}</span>
              </div>
            </div>
            <div class="flex shrink-0 gap-2">
              <button @click="play(v)" class="btn-ghost px-3 py-1 text-xs">▶ Play</button>
              <button v-if="isManager()" @click="remove(v)" class="btn-danger px-3 py-1 text-xs">Delete</button>
            </div>
          </div>
          <video v-if="playing?.id === v.id" :src="playing.url" controls playsinline
            class="mt-2 w-full rounded-xl bg-black"></video>
        </div>
      </div>
    </div>

    <!-- ── STEP 2: Record ────────────────────────────────────────────────── -->
    <div v-if="currentClub && stage === 'record'">
      <div class="card p-2">
        <div class="relative overflow-hidden rounded-xl bg-black">
          <video ref="liveVideo" muted playsinline autoplay class="w-full"></video>
          <div v-if="recording"
            class="absolute left-3 top-3 flex items-center gap-2 rounded-full bg-black/60 px-3 py-1 text-xs font-bold text-white">
            <span class="h-2 w-2 animate-pulse rounded-full bg-red-500"></span>
            REC {{ fmt(elapsed) }}
          </div>
        </div>
        <p v-if="camError" class="px-2 py-3 text-sm text-red-600">{{ camError }}</p>
        <div class="flex gap-2 p-2">
          <button v-if="!recording" @click="startRecording" class="btn-primary flex-1 py-3 text-base">● Start</button>
          <button v-else @click="stopRecording" class="btn-danger flex-1 py-3 text-base">■ Stop</button>
          <button @click="stopCamera(); stage='setup'" class="btn-ghost px-4 py-3 text-sm">Cancel</button>
        </div>
      </div>
      <p class="mt-3 text-center text-xs text-slate-400">
        Keep the whole court in frame. Tip: landscape, phone steady, 1–3 min for this test.
      </p>
    </div>

    <!-- ── STEP 3: Review + upload ───────────────────────────────────────── -->
    <div v-if="currentClub && stage === 'review'">
      <div class="card p-2">
        <video ref="reviewVideo" controls playsinline class="w-full rounded-xl bg-black"></video>
        <div class="px-2 py-2 text-xs text-slate-500">
          Length {{ fmt(elapsed) }} · {{ mb(recordedBlob?.size) }}
        </div>
        <p v-if="uploadError" class="px-2 pb-2 text-sm text-red-600">{{ uploadError }}</p>
        <div class="flex gap-2 p-2">
          <button :disabled="uploading" @click="upload" class="btn-primary flex-1 py-3 text-base disabled:opacity-50">
            {{ uploading ? 'Uploading…' : '⬆ Save recording' }}
          </button>
          <button :disabled="uploading" @click="reRecord" class="btn-ghost px-4 py-3 text-sm">Re-record</button>
        </div>
      </div>
    </div>

    <!-- ── STEP 4: Done ──────────────────────────────────────────────────── -->
    <div v-if="currentClub && stage === 'done'">
      <div class="card card-neon p-6 text-center">
        <div class="text-4xl">✅</div>
        <div class="mt-2 text-lg font-bold text-slate-800">Recording saved</div>
        <p class="mt-1 text-sm text-slate-500">
          Stored privately for your club. Once AI analysis is live, each tagged player will get a
          footwork, shot and positioning report from this match.
        </p>
        <button @click="resetAll" class="btn-primary mt-4 w-full py-3">Record another</button>
      </div>
    </div>
  </div>
</template>
