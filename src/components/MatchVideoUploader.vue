<script setup>
// Upload an already-recorded match video (e.g. filmed on a fixed court camera) straight to R2.
// Same context model as MatchVideoRecorder (club, players, singles/doubles) so the downstream
// tagging + analysis flow is identical whether the video was recorded in-app or uploaded.
import { ref, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { uploadMatchVideo } from '../lib/videoStorage'
import { CONSENT_VERSION } from '../lib/consent'
import ConsentGate from './ConsentGate.vue'

const props = defineProps({
  clubId:       { type: String, required: true },
  gameType:     { type: String, default: 'doubles' },
  playerIds:    { type: Array,  default: () => [] },
  defaultTitle: { type: String, default: '' },
})
const emit = defineEmits(['saved'])

const MAX_BYTES = 3 * 1024 * 1024 * 1024   // 3 GB hard cap

const consent    = ref(false)
const file       = ref(null)
const previewUrl = ref('')
const durationS  = ref(0)
const err        = ref('')
const uploading  = ref(false)
const progress   = ref(0)
const done       = ref(false)

onBeforeUnmount(() => { if (previewUrl.value) URL.revokeObjectURL(previewUrl.value) })

function mb(b) { return b ? (b / 1048576).toFixed(1) + ' MB' : '—' }
function fmt(s) { const m = Math.floor(s / 60), x = Math.round(s % 60); return `${m}:${String(x).padStart(2, '0')}` }

function pick(e) {
  err.value = ''
  const f = e.target.files?.[0]
  if (!f) return
  if (!f.type.startsWith('video/')) { err.value = 'Please choose a video file.'; return }
  if (f.size > MAX_BYTES) { err.value = `That file is ${mb(f.size)} — the limit is 3 GB.`; return }
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
  file.value = f
  previewUrl.value = URL.createObjectURL(f)
  // Read duration off the decoded metadata.
  const v = document.createElement('video')
  v.preload = 'metadata'
  v.onloadedmetadata = () => { durationS.value = Math.round(v.duration || 0) }
  v.src = previewUrl.value
}

function reset() {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
  file.value = null; previewUrl.value = ''; durationS.value = 0; err.value = ''; progress.value = 0
}

async function upload() {
  if (!file.value) return
  uploading.value = true; err.value = ''; progress.value = 1
  try {
    const videoId = crypto.randomUUID()
    const path = await uploadMatchVideo(file.value, {
      clubId: props.clubId, videoId, contentType: file.value.type,
      onProgress: (p) => { progress.value = Math.max(1, Math.min(99, p)) },
    })
    const { error } = await supabase.from('match_videos').insert({
      id: videoId,
      club_id: props.clubId,
      title: props.defaultTitle?.trim() || `Uploaded match · ${new Date().toLocaleDateString()}`,
      game_type: props.gameType,
      player_ids: props.playerIds ?? [],
      consent: true,
      consent_version: CONSENT_VERSION,
      source: 'upload',
      storage_path: path,
      duration_s: durationS.value,
      size_bytes: file.value.size,
      status: 'uploaded',
    })
    if (error) throw error
    progress.value = 100
    done.value = true
    emit('saved', videoId)
  } catch (e) {
    err.value = e?.message || 'Upload failed. Check your connection and try again.'
  } finally {
    uploading.value = false
  }
}

function uploadAnother() { reset(); done.value = false }
</script>

<template>
  <div>
    <ConsentGate v-model="consent" />

    <!-- Picker -->
    <div v-if="!done">
      <label v-if="!file"
        class="card flex cursor-pointer flex-col items-center justify-center gap-2 border-2 border-dashed border-slate-300 py-10 text-center"
        :class="!consent ? 'pointer-events-none opacity-60' : 'border-violet-300 bg-violet-50/40'">
        <span class="text-3xl">{{ consent ? '📁' : '🔒' }}</span>
        <span class="text-sm font-semibold text-slate-700">{{ consent ? 'Tap to choose a video' : 'Tick the consent box above to choose a video' }}</span>
        <span class="text-xs text-slate-400">MP4, MOV or WebM · up to 3 GB · full court in frame</span>
        <input type="file" accept="video/*" class="hidden" :disabled="!consent" @change="pick" />
      </label>

      <!-- Review -->
      <div v-else class="card p-3">
        <video :src="previewUrl" controls playsinline class="w-full rounded-xl bg-black"></video>
        <div class="flex items-center justify-between py-2 text-xs text-slate-500">
          <span class="truncate">{{ file.name }}</span>
          <span class="shrink-0">{{ fmt(durationS) }} · {{ mb(file.size) }}</span>
        </div>
        <div v-if="uploading" class="mb-2 h-2 w-full overflow-hidden rounded-full bg-slate-100">
          <div class="h-full bg-cyan-500 transition-all" :style="{ width: progress + '%' }"></div>
        </div>
        <p v-if="err" class="pb-2 text-sm text-red-600">{{ err }}</p>
        <div class="flex gap-2">
          <button :disabled="uploading" @click="upload" class="btn-primary flex-1 py-3 disabled:opacity-50">
            {{ uploading ? `Uploading… ${progress}%` : '⬆ Upload video' }}
          </button>
          <button :disabled="uploading" @click="reset" class="btn-ghost px-4 py-3 text-sm">Change</button>
        </div>
      </div>
      <p v-if="err && !file" class="mt-2 text-sm text-red-600">{{ err }}</p>
    </div>

    <!-- Done -->
    <div v-else class="card card-neon p-5 text-center">
      <div class="text-3xl">✅</div>
      <div class="mt-1 font-bold text-slate-800">Video uploaded</div>
      <p class="mt-1 text-xs text-slate-500">
        Next: tag who's who in the video, then run the analysis.
      </p>
      <button @click="uploadAnother" class="btn-ghost mt-3 w-full py-2 text-sm">Upload another</button>
    </div>
  </div>
</template>
