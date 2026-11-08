<script setup>
// Standalone/ad-hoc match recording (also reachable mid-flow). Setup here (type + players +
// title); the actual capture + upload is the shared MatchVideoRecorder component — the same one
// embedded in the live-match page.
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { getPlaybackUrl, deleteMatchVideo } from '../lib/videoStorage'
import MatchVideoRecorder from '../components/MatchVideoRecorder.vue'
import MatchVideoUploader from '../components/MatchVideoUploader.vue'
import PageHeader from '../components/PageHeader.vue'

const route  = useRoute()
const router = useRouter()
const { currentClub, isManager } = useClub()

const mode     = ref(route.query.upload ? 'upload' : 'record')
const gameType = ref('doubles')
const title    = ref('')
const ready    = ref(false)          // mode chosen → show recorder / uploader
const myVideos = ref([])

onMounted(loadMyVideos)

function fmt(s) { const m = Math.floor(s / 60), x = s % 60; return `${m}:${String(x).padStart(2, '0')}` }
function mb(b) { return b ? (b / 1048576).toFixed(1) + ' MB' : '—' }

async function loadMyVideos() {
  if (!currentClub.value) return
  const { data } = await supabase.from('match_videos')
    .select('id, title, game_type, duration_s, size_bytes, storage_path, status, created_at')
    .eq('club_id', currentClub.value.club_id)
    .order('created_at', { ascending: false })
    .limit(20)
  myVideos.value = data ?? []
}

const playing = ref(null)
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
function onSaved(videoId) {
  ready.value = false; title.value = ''
  if (videoId) router.push(`/coach/video/${videoId}`)   // straight to tagging + analysis
  else loadMyVideos()
}
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <PageHeader icon="🎥" title="Add Match Video"
      subtitle="Upload or record a match for AI Match Analysis. Keep the whole court in frame.">
      <template #help>
        <p class="text-sm text-slate-600">
          Tip: record straight from the live-score page instead — tap 🎥 while a match is running and
          the video links to that match automatically. Use this page for a quick standalone clip.
        </p>
      </template>
    </PageHeader>

    <div v-if="!currentClub" class="card p-6 text-center text-slate-500">
      Select a club first to record a match.
    </div>

    <!-- Setup -->
    <div v-if="currentClub && !ready">
      <!-- Step 1: match details (players are identified/tagged on the next screen, from the video itself) -->
      <div class="card p-4 mb-4">
        <div class="mb-2 flex items-center gap-2">
          <span class="step-dot">1</span>
          <span class="text-sm font-bold text-slate-800">Match details</span>
        </div>
        <div class="flex gap-1 rounded-xl bg-slate-100 p-1">
          <button @click="gameType = 'singles'" class="flex-1 rounded-lg py-2 text-sm font-semibold transition"
            :class="gameType === 'singles' ? 'bg-white text-slate-800 shadow' : 'text-slate-500'">🏸 Singles</button>
          <button @click="gameType = 'doubles'" class="flex-1 rounded-lg py-2 text-sm font-semibold transition"
            :class="gameType === 'doubles' ? 'bg-white text-slate-800 shadow' : 'text-slate-500'">👥 Doubles</button>
        </div>
        <input v-model="title" type="text" placeholder="Title (optional) — e.g. Saturday 6am, Court 2"
          class="mt-3 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-cyan-400 focus:outline-none" />
      </div>

      <!-- Step 2: one clear action — each card goes straight to the camera or the file picker -->
      <div class="mb-2 flex items-center gap-2 px-1">
        <span class="step-dot">2</span>
        <span class="text-sm font-bold text-slate-800">Add your video</span>
      </div>
      <div class="grid gap-3 sm:grid-cols-2">
        <button @click="mode = 'upload'; ready = true" class="add-card add-card-upload">
          <span class="add-icon bg-violet-100 text-violet-600">📁</span>
          <span class="min-w-0">
            <span class="block text-base font-bold text-slate-800">Upload a video file</span>
            <span class="block text-xs text-slate-500">Pick a match video already on your phone or from a court camera</span>
          </span>
          <span class="ml-auto text-xl text-violet-400">›</span>
        </button>
        <button @click="mode = 'record'; ready = true" class="add-card add-card-record">
          <span class="add-icon bg-cyan-100 text-cyan-600">🎥</span>
          <span class="min-w-0">
            <span class="block text-base font-bold text-slate-800">Record a match now</span>
            <span class="block text-xs text-slate-500">Use this phone's camera — prop it up in landscape</span>
          </span>
          <span class="ml-auto text-xl text-cyan-400">›</span>
        </button>
      </div>
      <p class="mt-3 text-center text-xs text-slate-400">
        Next you'll tag who's who on court — then the AI analyses the match.
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
              <button @click="router.push(`/coach/video/${v.id}`)" class="btn-primary px-3 py-1 text-xs">✨ Analyse</button>
              <button @click="play(v)" class="btn-ghost px-3 py-1 text-xs">▶</button>
              <button v-if="isManager()" @click="remove(v)" class="btn-danger px-3 py-1 text-xs">✕</button>
            </div>
          </div>
          <video v-if="playing?.id === v.id" :src="playing.url" controls playsinline
            class="mt-2 w-full rounded-xl bg-black"></video>
        </div>
      </div>
    </div>

    <!-- Capture / upload (shared components) -->
    <div v-if="currentClub && ready">
      <div class="card p-3 mb-3 flex items-center justify-between">
        <div class="text-sm text-slate-600">
          <b>{{ mode === 'upload' ? '📁 Upload' : '🎥 Record' }}</b> · {{ gameType === 'singles' ? 'Singles' : 'Doubles' }}
        </div>
        <button @click="ready = false" class="btn-ghost px-3 py-1 text-xs">← Back</button>
      </div>
      <MatchVideoRecorder v-if="mode === 'record'"
        :club-id="currentClub.club_id"
        :game-type="gameType"
        :default-title="title"
        @saved="onSaved" />
      <MatchVideoUploader v-else
        :club-id="currentClub.club_id"
        :game-type="gameType"
        :default-title="title"
        @saved="onSaved" />
    </div>
  </div>
</template>

<style scoped>
.step-dot { display: inline-flex; height: 1.4rem; width: 1.4rem; align-items: center; justify-content: center;
  border-radius: 9999px; background: #0f172a; color: #fff; font-size: 0.72rem; font-weight: 700; }
.add-card { display: flex; align-items: center; gap: 0.85rem; width: 100%; text-align: left; padding: 1rem;
  border-radius: 1.1rem; background: #fff; border: 1.5px solid #e2e8f0; box-shadow: 0 1px 2px rgba(15,23,42,.05);
  transition: transform .15s, box-shadow .15s, border-color .15s; }
.add-card:active { transform: scale(0.98); }
.add-card-upload:hover { border-color: #a78bfa; box-shadow: 0 6px 18px -8px rgba(139,92,246,.45); }
.add-card-record:hover { border-color: #22b8d8; box-shadow: 0 6px 18px -8px rgba(0,153,184,.45); }
.add-icon { display: inline-flex; flex-shrink: 0; height: 2.75rem; width: 2.75rem; align-items: center;
  justify-content: center; border-radius: 0.9rem; font-size: 1.35rem; }
</style>
