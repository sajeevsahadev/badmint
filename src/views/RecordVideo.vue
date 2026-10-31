<script setup>
// Standalone/ad-hoc match recording (also reachable mid-flow). Setup here (type + players +
// title); the actual capture + upload is the shared MatchVideoRecorder component — the same one
// embedded in the live-match page.
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { withNicknames } from '../lib/playerNames'
import { getPlaybackUrl, deleteMatchVideo, isR2 } from '../lib/videoStorage'
import MatchVideoRecorder from '../components/MatchVideoRecorder.vue'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()

const gameType = ref('doubles')
const players  = ref([])
const selected = ref(new Set())
const title    = ref('')
const requiredCount = computed(() => (gameType.value === 'singles' ? 2 : 4))
const ready    = ref(false)          // setup confirmed → show recorder
const myVideos = ref([])

onMounted(async () => { await loadPlayers(); await loadMyVideos() })

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

const canStart = computed(() => selected.value.size === requiredCount.value && !!currentClub.value)

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
function onSaved() { ready.value = false; selected.value = new Set(); title.value = ''; loadMyVideos() }
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <PageHeader icon="🎥" title="Record Match"
      subtitle="Film a match to get AI coaching (analysis coming soon). Prop your phone up in landscape so the whole court is in frame.">
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
      <div class="card p-4 mb-4">
        <div class="text-xs font-bold uppercase tracking-wide text-slate-500 mb-2">Match type</div>
        <div class="flex gap-2">
          <button @click="gameType = 'singles'; selected = new Set()"
            class="flex-1 rounded-xl py-2 text-sm font-semibold transition"
            :class="gameType === 'singles' ? 'btn-primary' : 'btn-ghost'">🏸 Singles</button>
          <button @click="gameType = 'doubles'; selected = new Set()"
            class="flex-1 rounded-xl py-2 text-sm font-semibold transition"
            :class="gameType === 'doubles' ? 'btn-primary' : 'btn-ghost'">👥 Doubles</button>
        </div>
      </div>

      <div class="card p-4 mb-4">
        <div class="flex items-center justify-between mb-2">
          <div class="text-xs font-bold uppercase tracking-wide text-slate-500">Who's playing?</div>
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
      </div>

      <div class="card p-4 mb-4">
        <label class="text-xs font-bold uppercase tracking-wide text-slate-500">Title (optional)</label>
        <input v-model="title" type="text" placeholder="e.g. Saturday 6am — Court 2"
          class="mt-2 w-full rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-cyan-400 focus:outline-none" />
      </div>

      <button :disabled="!canStart" @click="ready = true"
        class="btn-primary w-full py-3 text-base disabled:opacity-40 disabled:cursor-not-allowed">
        Continue →
      </button>
      <p v-if="!canStart" class="mt-2 text-center text-xs text-slate-400">
        Pick {{ requiredCount }} players to continue.
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

    <!-- Capture (shared component) -->
    <div v-if="currentClub && ready">
      <div class="card p-3 mb-3 flex items-center justify-between">
        <div class="text-sm text-slate-600">
          <b>{{ gameType === 'singles' ? 'Singles' : 'Doubles' }}</b> · {{ selected.size }} players tagged
        </div>
        <button @click="ready = false" class="btn-ghost px-3 py-1 text-xs">← Back</button>
      </div>
      <MatchVideoRecorder
        :club-id="currentClub.club_id"
        :game-type="gameType"
        :player-ids="[...selected]"
        :default-title="title"
        @saved="onSaved" />
      <p v-if="!isR2" class="mt-3 text-center text-xs text-amber-600">
        Dev storage (Supabase) — keep clips short. Turn on Cloudflare R2 for full-length matches.
      </p>
    </div>
  </div>
</template>
