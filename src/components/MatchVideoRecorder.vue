<script setup>
// Reusable match-video recorder: consent → camera → record → review → upload.
// Context (club, players, singles/doubles, live/match link) is passed in, so the live-match
// flow needs NO re-tagging — it just inherits what's already on screen. Used by LiveMatch.vue
// and RecordVideo.vue so there is ONE capture implementation.
import { ref, computed, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { uploadMatchVideo, isR2 } from '../lib/videoStorage'

const props = defineProps({
  clubId:       { type: String, required: true },
  gameType:     { type: String, default: 'doubles' },   // 'singles' | 'doubles'
  playerIds:    { type: Array,  default: () => [] },
  liveMatchId:  { type: String, default: null },
  matchId:      { type: String, default: null },
  defaultTitle: { type: String, default: '' },
  compact:      { type: Boolean, default: false },       // tighter UI for the live page
})
const emit = defineEmits(['saved'])

// On the capped Supabase fallback keep live clips short; on R2 allow long matches.
const maxSeconds = computed(() => (isR2 ? 60 * 60 : 3 * 60))

const stage       = ref('consent')   // consent | record | review | done
const consent     = ref(false)
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
const uploading    = ref(false)
const uploadError  = ref('')

onBeforeUnmount(() => { stopCamera(); if (timer) clearInterval(timer); if (recordedUrl.value) URL.revokeObjectURL(recordedUrl.value) })

function fmt(s) { const m = Math.floor(s / 60), x = s % 60; return `${m}:${String(x).padStart(2, '0')}` }
function mb(b) { return b ? (b / 1048576).toFixed(1) + ' MB' : '—' }

function pickMime() {
  const prefs = ['video/mp4;codecs=h264,aac', 'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
  for (const m of prefs) if (window.MediaRecorder?.isTypeSupported?.(m)) return m
  return ''
}

async function startCamera() {
  camError.value = ''
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
      audio: true,
    })
    stage.value = 'record'
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
      videoBitsPerSecond: 2_500_000, audioBitsPerSecond: 64_000,
    })
  } catch { recorder = new MediaRecorder(stream) }
  recorder.ondataavailable = (e) => { if (e.data && e.data.size) chunks.push(e.data) }
  recorder.onstop = finishRecording
  recorder.start(1000)
  recording.value = true
  elapsed.value = 0
  timer = setInterval(() => {
    elapsed.value++
    if (elapsed.value >= maxSeconds.value) stopRecording()   // auto-stop at the cap
  }, 1000)
}

function stopRecording() {
  if (recorder && recording.value) recorder.stop()
  recording.value = false
  if (timer) { clearInterval(timer); timer = null }
}

function finishRecording() {
  const type = mimeUsed.value || chunks[0]?.type || 'video/webm'
  recordedBlob.value = new Blob(chunks, { type })
  recordedUrl.value = URL.createObjectURL(recordedBlob.value)
  stage.value = 'review'
  stopCamera()
  requestAnimationFrame(() => { if (reviewVideo.value) reviewVideo.value.src = recordedUrl.value })
}

function stopCamera() { if (stream) { stream.getTracks().forEach(t => t.stop()); stream = null } }

function reRecord() {
  if (recordedUrl.value) URL.revokeObjectURL(recordedUrl.value)
  recordedBlob.value = null; recordedUrl.value = ''; elapsed.value = 0; uploadError.value = ''
  startCamera()
}

async function upload() {
  if (!recordedBlob.value) return
  uploading.value = true; uploadError.value = ''
  try {
    const videoId = crypto.randomUUID()
    const path = await uploadMatchVideo(recordedBlob.value, {
      clubId: props.clubId, videoId, contentType: recordedBlob.value.type,
    })
    const { error } = await supabase.from('match_videos').insert({
      id: videoId,
      club_id: props.clubId,
      match_id: props.matchId || null,
      live_match_id: props.liveMatchId || null,
      title: props.defaultTitle?.trim() || `Match video · ${new Date().toLocaleDateString()}`,
      game_type: props.gameType,
      player_ids: props.playerIds ?? [],
      consent: true,
      storage_path: path,
      duration_s: elapsed.value,
      size_bytes: recordedBlob.value.size,
      status: 'uploaded',
    })
    if (error) throw error
    stage.value = 'done'
    emit('saved', videoId)
  } catch (e) {
    uploadError.value = e?.message || 'Upload failed. Check your connection and try again.'
  } finally {
    uploading.value = false
  }
}

function recordAnother() {
  if (recordedUrl.value) URL.revokeObjectURL(recordedUrl.value)
  recordedBlob.value = null; recordedUrl.value = ''; elapsed.value = 0; uploadError.value = ''
  stage.value = 'consent'
}

defineExpose({ stage })
</script>

<template>
  <div>
    <!-- Consent — ethical + GDPR. Required once before the camera opens. -->
    <div v-if="stage === 'consent'">
      <label class="card card-amber flex items-start gap-3 p-4 cursor-pointer"
        :class="compact ? 'mb-3' : 'mb-4'">
        <input type="checkbox" v-model="consent" class="mt-0.5 h-5 w-5 shrink-0 accent-cyan-600" />
        <span class="text-sm text-slate-700">
          <b>Everyone on court agrees to be recorded</b> for coaching analysis. The video is private
          to this club and is deleted after analysis (or kept only as a private link).
        </span>
      </label>
      <button :disabled="!consent" @click="startCamera"
        class="btn-primary w-full py-3 disabled:opacity-40 disabled:cursor-not-allowed">
        🎬 Open camera
      </button>
    </div>

    <!-- Record -->
    <div v-if="stage === 'record'">
      <div class="relative overflow-hidden rounded-xl bg-black">
        <video ref="liveVideo" muted playsinline autoplay class="w-full"></video>
        <div v-if="recording"
          class="absolute left-3 top-3 flex items-center gap-2 rounded-full bg-black/60 px-3 py-1 text-xs font-bold text-white">
          <span class="h-2 w-2 animate-pulse rounded-full bg-red-500"></span> REC {{ fmt(elapsed) }}
        </div>
      </div>
      <p v-if="camError" class="py-2 text-sm text-red-600">{{ camError }}</p>
      <div class="flex gap-2 pt-2">
        <button v-if="!recording" @click="startRecording" class="btn-primary flex-1 py-3">● Start</button>
        <button v-else @click="stopRecording" class="btn-danger flex-1 py-3">■ Stop</button>
        <button @click="stopCamera(); stage = 'consent'" class="btn-ghost px-4 py-3 text-sm">Cancel</button>
      </div>
      <p v-if="!compact" class="mt-2 text-center text-xs text-slate-400">
        Keep the whole court in frame. Landscape, phone steady. Auto-stops at {{ Math.round(maxSeconds / 60) }} min.
      </p>
    </div>

    <!-- Review + upload -->
    <div v-if="stage === 'review'">
      <video ref="reviewVideo" controls playsinline class="w-full rounded-xl bg-black"></video>
      <div class="py-2 text-xs text-slate-500">Length {{ fmt(elapsed) }} · {{ mb(recordedBlob?.size) }}</div>
      <p v-if="uploadError" class="pb-2 text-sm text-red-600">{{ uploadError }}</p>
      <div class="flex gap-2">
        <button :disabled="uploading" @click="upload" class="btn-primary flex-1 py-3 disabled:opacity-50">
          {{ uploading ? 'Uploading…' : '⬆ Save recording' }}
        </button>
        <button :disabled="uploading" @click="reRecord" class="btn-ghost px-4 py-3 text-sm">Re-record</button>
      </div>
    </div>

    <!-- Done -->
    <div v-if="stage === 'done'" class="card card-neon p-5 text-center">
      <div class="text-3xl">✅</div>
      <div class="mt-1 font-bold text-slate-800">Recording saved</div>
      <p class="mt-1 text-xs text-slate-500">
        Stored privately for your club. Once AI analysis is live, each tagged player gets a
        footwork, shot and positioning report from this match.
      </p>
      <button @click="recordAnother" class="btn-ghost mt-3 w-full py-2 text-sm">Record another</button>
    </div>
  </div>
</template>
