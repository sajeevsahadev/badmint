<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'

const route  = useRoute()
const router = useRouter()
const { currentClub, isManager } = useClub()
const { user } = useAuth()

const liveId  = route.params.id
const match   = ref(null)
const playerNames = ref({})
const announcement = ref('')
const announcementTimer = ref(null)
const tapping = ref(null)
const showFinishModal = ref(false)
const showCancelModal = ref(false)
const loading = ref(true)
const error   = ref('')

let channel = null

// ── Computed ──────────────────────────────────────────────────────────────────
const sideAPlayers = computed(() =>
  (match.value?.side_a || []).map(id => ({ id, name: playerNames.value[id] || id.slice(0, 6) }))
)
const sideBPlayers = computed(() =>
  (match.value?.side_b || []).map(id => ({ id, name: playerNames.value[id] || id.slice(0, 6) }))
)
const servingPlayerId = computed(() => match.value?.serving_player)
const currentScoreA  = computed(() => match.value?.score_a ?? 0)
const currentScoreB  = computed(() => match.value?.score_b ?? 0)
const gameScores     = computed(() => match.value?.game_scores ?? [])
const gamesA         = computed(() => match.value?.games_a ?? 0)
const gamesB         = computed(() => match.value?.games_b ?? 0)

// ── Load ──────────────────────────────────────────────────────────────────────
async function loadMatch() {
  const { data, error: err } = await supabase
    .from('live_matches')
    .select('*')
    .eq('id', liveId)
    .single()
  if (err || !data) { error.value = 'Match not found'; loading.value = false; return }
  match.value = data

  const allIds = [...new Set([...(data.side_a || []), ...(data.side_b || [])])]
  if (allIds.length) {
    const { data: players } = await supabase
      .from('players')
      .select('id, display_name')
      .in('id', allIds)
    if (players) {
      const map = {}
      players.forEach(p => { map[p.id] = p.display_name })
      playerNames.value = map
    }
  }
  loading.value = false
}

// ── Realtime ──────────────────────────────────────────────────────────────────
function subscribeRealtime() {
  channel = supabase.channel(`live_court_${liveId}`)
    .on('postgres_changes', {
      event: 'UPDATE', schema: 'public', table: 'live_matches',
      filter: `id=eq.${liveId}`
    }, payload => {
      match.value = { ...match.value, ...payload.new }
    })
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'live_match_points',
      filter: `live_match_id=eq.${liveId}`
    }, payload => {
      handleNewPoint(payload.new)
    })
    .subscribe()
}

// ── Announcement ──────────────────────────────────────────────────────────────
function flashAnnouncement(text) {
  if (announcementTimer.value) clearTimeout(announcementTimer.value)
  announcement.value = text
  announcementTimer.value = setTimeout(() => { announcement.value = '' }, 2500)
}

function handleNewPoint(point) {
  const a = point.score_a_after
  const b = point.score_b_after
  let msg = point.side === 'A' ? 'Point — Side A' : 'Point — Side B'
  if (a >= 20 && b >= 20 && a === b) msg = 'DEUCE!'
  else if ((a === 20 && b < 20) || (b === 20 && a < 20)) msg = 'MATCH POINT!'
  flashAnnouncement(msg)
}

// ── Actions ───────────────────────────────────────────────────────────────────
async function scoreByPlayer(playerId) {
  if (!isManager() || match.value?.status !== 'active' || !playerId) return
  tapping.value = playerId
  setTimeout(() => { tapping.value = null }, 300)
  const { data, error: err } = await supabase.rpc('add_live_point_v2', {
    p_live_match_id:    liveId,
    p_scored_by_player: playerId
  })
  if (!err && data) {
    match.value = { ...match.value, ...data }
    if (data.game_won) {
      flashAnnouncement(`Game ${(match.value.current_game - 1)} won by Side ${data.winner_side}!`)
    }
  }
}

function scoreBySide(side) {
  const player = side === 'A' ? sideAPlayers.value[0] : sideBPlayers.value[0]
  if (player) scoreByPlayer(player.id)
}

async function undoPoint() {
  const { data, error: err } = await supabase.rpc('undo_live_point_v2', {
    p_live_match_id: liveId
  })
  if (!err && data) {
    match.value = { ...match.value, ...data }
    flashAnnouncement('Undone')
  }
}

async function finishMatch() {
  showFinishModal.value = false
  const { data: matchId } = await supabase.rpc('finish_live_match', {
    p_live_match_id: liveId,
    p_display_name:  null
  })
  // Update rotation stats (fire-and-forget)
  if (currentClub.value) {
    const playedIds = [...(match.value?.side_a ?? []), ...(match.value?.side_b ?? [])]
    supabase.rpc('update_rotation_stats', {
      p_club_id:      currentClub.value.club_id,
      p_session_date: match.value?.played_on ?? new Date().toISOString().slice(0, 10),
      p_played_ids:   playedIds,
      p_bench_ids:    []
    }).catch(() => null)
  }
  router.push(matchId ? `/matches?open=${matchId}` : '/matches')
}

async function cancelMatch() {
  showCancelModal.value = false
  await supabase.from('live_matches').update({ status: 'cancelled' }).eq('id', liveId)
  router.push('/matches')
}

onMounted(async () => {
  await loadMatch()
  subscribeRealtime()
})

onUnmounted(() => {
  if (channel) supabase.removeChannel(channel)
  if (announcementTimer.value) clearTimeout(announcementTimer.value)
})
</script>

<template>
  <div v-if="loading" class="flex items-center justify-center h-screen text-slate-400">Loading…</div>
  <div v-else-if="error" class="flex items-center justify-center h-screen text-rose-500">{{ error }}</div>

  <div v-else class="h-screen flex flex-col bg-[#eef4ff] select-none overflow-hidden">

    <!-- Score header (dark navy) -->
    <div class="bg-[#0d1b2a] text-white px-3 py-2 flex items-center gap-2 shrink-0">
      <!-- Side B (left) -->
      <div class="flex-1 text-right">
        <div class="text-xs text-slate-400 truncate">{{ sideBPlayers.map(p => p.name).join(' / ') }}</div>
        <div class="flex items-end justify-end gap-2">
          <span v-for="(g, i) in gameScores" :key="i" class="text-xs text-slate-500">{{ g.b }}</span>
          <span class="text-3xl font-bold text-violet-400">{{ currentScoreB }}</span>
        </div>
      </div>

      <!-- Center: game indicator + game dots -->
      <div class="flex flex-col items-center shrink-0 px-2">
        <div class="text-xs text-slate-400">Game {{ match?.current_game ?? 1 }}</div>
        <div class="flex gap-1 mt-1">
          <span v-for="g in (gamesA + gamesB + 1)" :key="g"
                class="w-2 h-2 rounded-full"
                :class="g <= gamesA ? 'bg-cyan-400' : g <= gamesA + gamesB ? 'bg-violet-400' : 'bg-slate-600'">
          </span>
        </div>
      </div>

      <!-- Side A (right) -->
      <div class="flex-1 text-left">
        <div class="text-xs text-slate-400 truncate">{{ sideAPlayers.map(p => p.name).join(' / ') }}</div>
        <div class="flex items-end justify-start gap-2">
          <span class="text-3xl font-bold text-cyan-400">{{ currentScoreA }}</span>
          <span v-for="(g, i) in gameScores" :key="i" class="text-xs text-slate-500">{{ g.a }}</span>
        </div>
      </div>
    </div>

    <!-- Finished / cancelled banner -->
    <div v-if="match?.status !== 'active'" class="bg-white px-4 py-3 text-center shrink-0">
      <p v-if="match?.status === 'finished'" class="text-emerald-600 font-semibold text-sm">
        Match finished · Scores recorded
      </p>
      <p v-else class="text-slate-500 text-sm">Match cancelled</p>
    </div>

    <!-- Court area (flex-1) -->
    <div class="flex-1 flex items-stretch p-2 gap-2 min-h-0">

      <!-- Left rail: Side B score tap -->
      <button @click="scoreBySide('B')" :disabled="!isManager() || match?.status !== 'active'"
              class="w-12 flex flex-col items-center justify-center rounded-xl bg-violet-900/20 border border-violet-500/30 shrink-0 transition-all"
              :class="!isManager() ? 'opacity-50 cursor-default' : 'active:bg-violet-900/40'">
        <span class="text-violet-400 text-xs font-medium">+1</span>
        <span class="text-violet-400 text-2xl font-bold">{{ currentScoreB }}</span>
      </button>

      <!-- Court -->
      <div class="flex-1 relative rounded-2xl overflow-hidden"
           style="background: linear-gradient(160deg, #1a4a1a 0%, #0d2e0d 50%, #0f3510 100%)">

        <!-- Court lines: outer border -->
        <div class="absolute inset-3 border-2 border-white/40 rounded pointer-events-none"></div>

        <!-- Net (horizontal middle) -->
        <div class="absolute left-0 right-0 top-1/2 -translate-y-px h-0.5 bg-white/60 pointer-events-none"></div>
        <!-- Net posts -->
        <div class="absolute left-3 top-1/2 -translate-y-1 w-0.5 h-2 bg-white/40 pointer-events-none"></div>
        <div class="absolute right-3 top-1/2 -translate-y-1 w-0.5 h-2 bg-white/40 pointer-events-none"></div>

        <!-- Service centre lines -->
        <div class="absolute top-3 bottom-1/2 left-1/2 -translate-x-px w-px bg-white/25 pointer-events-none"></div>
        <div class="absolute top-1/2 bottom-3 left-1/2 -translate-x-px w-px bg-white/25 pointer-events-none"></div>
        <!-- Short service lines -->
        <div class="absolute left-3 right-3 pointer-events-none" style="top: calc(50% - 22%)">
          <div class="border-t border-dashed border-white/20"></div>
        </div>
        <div class="absolute left-3 right-3 pointer-events-none" style="bottom: calc(50% - 22%)">
          <div class="border-t border-dashed border-white/20"></div>
        </div>

        <!-- 4 player zones: 2×2 grid -->
        <div class="absolute inset-0 grid grid-cols-2 grid-rows-2">

          <!-- Top-left: Side B player 0 -->
          <button @click="scoreByPlayer(sideBPlayers[0]?.id)"
                  :disabled="!isManager() || match?.status !== 'active' || !sideBPlayers[0]"
                  class="relative flex flex-col items-center justify-center transition-all duration-150"
                  :class="[
                    tapping === sideBPlayers[0]?.id ? 'bg-violet-500/30 scale-95' : 'hover:bg-white/5 active:bg-violet-500/20',
                    (!isManager() || match?.status !== 'active') ? 'cursor-default' : 'cursor-pointer'
                  ]">
            <div class="w-9 h-9 rounded-full bg-violet-600/80 flex items-center justify-center text-white font-bold text-sm mb-1">
              {{ (sideBPlayers[0]?.name || '?')[0].toUpperCase() }}
            </div>
            <span class="text-white/80 text-xs font-medium text-center leading-tight px-1 truncate max-w-full">
              {{ sideBPlayers[0]?.name || '—' }}
            </span>
            <div v-if="servingPlayerId === sideBPlayers[0]?.id"
                 class="absolute top-2 right-2 w-3 h-3 rounded-full bg-cyan-400 shadow-[0_0_8px_#22d3ee] animate-pulse">
            </div>
          </button>

          <!-- Top-right: Side A player 1 -->
          <button @click="scoreByPlayer(sideAPlayers[1]?.id)"
                  :disabled="!isManager() || match?.status !== 'active' || !sideAPlayers[1]"
                  class="relative flex flex-col items-center justify-center transition-all duration-150"
                  :class="[
                    tapping === sideAPlayers[1]?.id ? 'bg-cyan-500/30 scale-95' : 'hover:bg-white/5 active:bg-cyan-500/20',
                    (!isManager() || match?.status !== 'active') ? 'cursor-default' : 'cursor-pointer'
                  ]">
            <div class="w-9 h-9 rounded-full bg-cyan-600/80 flex items-center justify-center text-white font-bold text-sm mb-1">
              {{ (sideAPlayers[1]?.name || '?')[0].toUpperCase() }}
            </div>
            <span class="text-white/80 text-xs font-medium text-center leading-tight px-1 truncate max-w-full">
              {{ sideAPlayers[1]?.name || '—' }}
            </span>
            <div v-if="servingPlayerId === sideAPlayers[1]?.id"
                 class="absolute top-2 left-2 w-3 h-3 rounded-full bg-cyan-400 shadow-[0_0_8px_#22d3ee] animate-pulse">
            </div>
          </button>

          <!-- Bottom-left: Side B player 1 -->
          <button @click="scoreByPlayer(sideBPlayers[1]?.id)"
                  :disabled="!isManager() || match?.status !== 'active' || !sideBPlayers[1]"
                  class="relative flex flex-col items-center justify-center transition-all duration-150"
                  :class="[
                    tapping === sideBPlayers[1]?.id ? 'bg-violet-500/30 scale-95' : 'hover:bg-white/5 active:bg-violet-500/20',
                    (!isManager() || match?.status !== 'active') ? 'cursor-default' : 'cursor-pointer'
                  ]">
            <div class="w-9 h-9 rounded-full bg-violet-600/80 flex items-center justify-center text-white font-bold text-sm mb-1">
              {{ (sideBPlayers[1]?.name || '?')[0].toUpperCase() }}
            </div>
            <span class="text-white/80 text-xs font-medium text-center leading-tight px-1 truncate max-w-full">
              {{ sideBPlayers[1]?.name || '—' }}
            </span>
            <div v-if="servingPlayerId === sideBPlayers[1]?.id"
                 class="absolute bottom-2 right-2 w-3 h-3 rounded-full bg-cyan-400 shadow-[0_0_8px_#22d3ee] animate-pulse">
            </div>
          </button>

          <!-- Bottom-right: Side A player 0 -->
          <button @click="scoreByPlayer(sideAPlayers[0]?.id)"
                  :disabled="!isManager() || match?.status !== 'active' || !sideAPlayers[0]"
                  class="relative flex flex-col items-center justify-center transition-all duration-150"
                  :class="[
                    tapping === sideAPlayers[0]?.id ? 'bg-cyan-500/30 scale-95' : 'hover:bg-white/5 active:bg-cyan-500/20',
                    (!isManager() || match?.status !== 'active') ? 'cursor-default' : 'cursor-pointer'
                  ]">
            <div class="w-9 h-9 rounded-full bg-cyan-600/80 flex items-center justify-center text-white font-bold text-sm mb-1">
              {{ (sideAPlayers[0]?.name || '?')[0].toUpperCase() }}
            </div>
            <span class="text-white/80 text-xs font-medium text-center leading-tight px-1 truncate max-w-full">
              {{ sideAPlayers[0]?.name || '—' }}
            </span>
            <div v-if="servingPlayerId === sideAPlayers[0]?.id"
                 class="absolute bottom-2 left-2 w-3 h-3 rounded-full bg-cyan-400 shadow-[0_0_8px_#22d3ee] animate-pulse">
            </div>
          </button>
        </div>

        <!-- Announcement overlay -->
        <Transition name="announcement">
          <div v-if="announcement"
               class="absolute top-3 left-1/2 -translate-x-1/2 bg-black/70 text-white text-sm font-semibold px-4 py-1.5 rounded-full backdrop-blur-sm whitespace-nowrap z-10">
            {{ announcement }}
          </div>
        </Transition>

        <!-- Spectator badge -->
        <div v-if="!isManager()"
             class="absolute bottom-2 left-1/2 -translate-x-1/2 bg-black/50 text-white/70 text-xs px-3 py-1 rounded-full">
          Live · View only
        </div>
      </div>

      <!-- Right rail: Side A score tap -->
      <button @click="scoreBySide('A')" :disabled="!isManager() || match?.status !== 'active'"
              class="w-12 flex flex-col items-center justify-center rounded-xl bg-cyan-900/20 border border-cyan-500/30 shrink-0 transition-all"
              :class="!isManager() ? 'opacity-50 cursor-default' : 'active:bg-cyan-900/40'">
        <span class="text-cyan-400 text-xs font-medium">+1</span>
        <span class="text-cyan-400 text-2xl font-bold">{{ currentScoreA }}</span>
      </button>
    </div>

    <!-- Action bar -->
    <div class="flex items-center gap-3 px-4 py-3 bg-white border-t border-slate-200 shrink-0">
      <button v-if="isManager()" @click="undoPoint"
              class="btn-ghost flex items-center gap-1.5 text-sm">
        ↩ Undo
      </button>
      <div class="flex-1"></div>
      <button v-if="isManager() && match?.status === 'active'"
              @click="showFinishModal = true"
              class="btn-success text-sm">
        Finish &amp; Record
      </button>
      <button v-if="isManager() && match?.status === 'active'"
              @click="showCancelModal = true"
              class="btn-danger text-sm">
        Cancel
      </button>
    </div>

    <!-- Finish modal -->
    <Teleport to="body">
      <div v-if="showFinishModal" class="fixed inset-0 bg-black/50 flex items-end justify-center z-50 p-4">
        <div class="card w-full max-w-sm p-6">
          <h3 class="font-semibold text-lg mb-2">Finish &amp; Record Match?</h3>
          <p class="text-slate-500 text-sm mb-4">
            Final score: Side B {{ currentScoreB }} – {{ currentScoreA }} Side A
            <span v-if="gameScores.length"> ({{ gameScores.length + 1 }} games)</span>
          </p>
          <div class="flex gap-3">
            <button @click="showFinishModal = false" class="btn-ghost flex-1">Cancel</button>
            <button @click="finishMatch" class="btn-success flex-1">Yes, Record</button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Cancel modal -->
    <Teleport to="body">
      <div v-if="showCancelModal" class="fixed inset-0 bg-black/50 flex items-end justify-center z-50 p-4">
        <div class="card w-full max-w-sm p-6">
          <h3 class="font-semibold text-lg mb-2">Cancel Match?</h3>
          <p class="text-slate-500 text-sm mb-4">The match will be discarded without recording.</p>
          <div class="flex gap-3">
            <button @click="showCancelModal = false" class="btn-ghost flex-1">Keep Playing</button>
            <button @click="cancelMatch" class="btn-danger flex-1">Yes, Cancel</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.announcement-enter-active, .announcement-leave-active { transition: all 0.3s ease; }
.announcement-enter-from, .announcement-leave-to { opacity: 0; transform: translateX(-50%) translateY(-8px); }
</style>
