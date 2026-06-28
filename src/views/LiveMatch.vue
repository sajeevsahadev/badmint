<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { currentClub, isManager } = useClub()

const liveId  = route.params.id
const match   = ref(null)
const playerNames = ref({})
const avatarMap   = ref({})
const announcement = ref('')
const announcementTimer = ref(null)
const tapping = ref(null)
const showFinishModal = ref(false)
const showCancelModal = ref(false)
const loading = ref(true)
const error   = ref('')
const undoError = ref('')

let channel = null

// ── Computed ──────────────────────────────────────────────────────────────────
const sideAPlayers = computed(() =>
  (match.value?.side_a || []).map(id => ({
    id,
    name: playerNames.value[id] || id.slice(0, 6),
    avatar: avatarMap.value[id] || null
  }))
)
const sideBPlayers = computed(() =>
  (match.value?.side_b || []).map(id => ({
    id,
    name: playerNames.value[id] || id.slice(0, 6),
    avatar: avatarMap.value[id] || null
  }))
)
const servingPlayerId = computed(() => match.value?.serving_player)
const currentScoreA  = computed(() => match.value?.score_a ?? 0)
const currentScoreB  = computed(() => match.value?.score_b ?? 0)

// Single-game win detection (client-side mirror of SQL logic)
const isMatchWon = computed(() => {
  const a = currentScoreA.value, b = currentScoreB.value
  return (a >= 21 && a - b >= 2) || a === 30 ||
         (b >= 21 && b - a >= 2) || b === 30
})
const matchWinner = computed(() => {
  const a = currentScoreA.value, b = currentScoreB.value
  if ((a >= 21 && a - b >= 2) || a === 30) return 'A'
  if ((b >= 21 && b - a >= 2) || b === 30) return 'B'
  return null
})

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
      .select('id, display_name, user_id')
      .in('id', allIds)
    if (players) {
      const nameMap = {}
      const userIdToPlayerId = {}
      players.forEach(p => {
        nameMap[p.id] = p.display_name
        if (p.user_id) userIdToPlayerId[p.user_id] = p.id
      })
      playerNames.value = nameMap

      // Fetch avatars for linked users via get_public_profiles RPC
      const linkedUserIds = players.filter(p => p.user_id).map(p => p.user_id)
      if (linkedUserIds.length) {
        const { data: profiles } = await supabase.rpc('get_public_profiles', {
          p_user_ids: linkedUserIds
        })
        if (profiles) {
          const aMap = {}
          profiles.forEach(prof => {
            const playerId = userIdToPlayerId[prof.user_id]
            if (playerId && prof.avatar_url) aMap[playerId] = prof.avatar_url
          })
          avatarMap.value = aMap
        }
      }
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
const suppressNextPointAnnouncement = ref(false)

function flashAnnouncement(text) {
  if (announcementTimer.value) clearTimeout(announcementTimer.value)
  announcement.value = text
  announcementTimer.value = setTimeout(() => { announcement.value = '' }, 2500)
}

function handleNewPoint(point) {
  // Skip generic "Point" flash if a win announcement was just issued locally
  if (suppressNextPointAnnouncement.value) {
    suppressNextPointAnnouncement.value = false
    return
  }
  const a = point.score_a_after
  const b = point.score_b_after
  let msg = point.side === 'A' ? 'Point — Side A' : 'Point — Side B'
  // Deuce: both sides ≥20 and level (can happen at 20-20, 21-21, etc. up to 29-29)
  if (a >= 20 && b >= 20 && a === b) msg = 'DEUCE!'
  // Match point: one side needs exactly one more to win
  // Normal win: score ≥20 with a 1-point lead (next point gives the 2-point margin)
  // Cap win: one side is at 29 (next point = 30 = cap win)
  else if ((a >= 20 && a === b + 1) || (b >= 20 && b === a + 1) || a === 29 || b === 29) msg = 'MATCH POINT!'
  flashAnnouncement(msg)
}

// ── Actions ───────────────────────────────────────────────────────────────────
async function scoreByPlayer(playerId) {
  if (!isManager() || match.value?.status !== 'active' || !playerId || isMatchWon.value) return
  tapping.value = playerId
  setTimeout(() => { tapping.value = null }, 300)
  const { data, error: err } = await supabase.rpc('add_live_point_v2', {
    p_live_match_id:    liveId,
    p_scored_by_player: playerId
  })
  if (!err && data) {
    match.value = { ...match.value, score_a: data.score_a, score_b: data.score_b,
      serving_player: data.serving_player, serving_side: data.serving_side }
    if (data.match_won) {
      suppressNextPointAnnouncement.value = true
      const winnerName = data.winner_side === 'A'
        ? sideAPlayers.value.map(p => p.name).join(' & ')
        : sideBPlayers.value.map(p => p.name).join(' & ')
      flashAnnouncement(`🏆 ${winnerName} wins!`)
    }
  }
}

function scoreBySide(side) {
  const player = side === 'A' ? sideAPlayers.value[0] : sideBPlayers.value[0]
  if (player) scoreByPlayer(player.id)
}

async function undoPoint() {
  undoError.value = ''
  const { data, error: err } = await supabase.rpc('undo_live_point_v2', {
    p_live_match_id: liveId
  })
  if (err) {
    undoError.value = err.message || 'Nothing to undo'
    setTimeout(() => { undoError.value = '' }, 2000)
    return
  }
  if (data) {
    match.value = { ...match.value, ...data }
    flashAnnouncement('Undone')
  }
}

const finishing = ref(false)
const finishError = ref('')

async function finishMatch() {
  finishing.value = true
  finishError.value = ''
  const { data: matchId, error: err } = await supabase.rpc('finish_live_match', {
    p_live_match_id: liveId,
    p_display_name:  null
  })
  finishing.value = false
  if (err) { finishError.value = err.message; return }
  showFinishModal.value = false
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

// Auto-navigate when match becomes finished (e.g. via realtime from another device)
watch(() => match.value?.status, (status) => {
  if (status === 'finished') {
    const mid = match.value?.match_id
    setTimeout(() => router.push(mid ? `/matches?open=${mid}` : '/matches'), 800)
  }
})

async function cancelMatch() {
  showCancelModal.value = false
  await supabase.from('live_matches').update({ status: 'cancelled' }).eq('id', liveId)
  router.push('/matches')
}

// ── SVG court helpers ─────────────────────────────────────────────────────────
// Get first letter of player name for avatar fallback
function initial(name) {
  return (name || '?')[0].toUpperCase()
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
    <div class="bg-[#0d1b2a] text-white px-3 py-2 flex items-center gap-3 shrink-0">
      <!-- Side B (left) -->
      <div class="flex-1 text-right">
        <div class="text-[11px] text-slate-400 truncate mb-0.5">{{ sideBPlayers.map(p => p.name).join(' / ') }}</div>
        <span class="text-4xl font-black text-violet-400 leading-none">{{ currentScoreB }}</span>
      </div>
      <!-- Center divider -->
      <div class="text-slate-500 text-xl font-bold shrink-0">–</div>
      <!-- Side A (right) -->
      <div class="flex-1 text-left">
        <div class="text-[11px] text-slate-400 truncate mb-0.5">{{ sideAPlayers.map(p => p.name).join(' / ') }}</div>
        <span class="text-4xl font-black text-cyan-400 leading-none">{{ currentScoreA }}</span>
      </div>
    </div>

    <!-- Finished / cancelled banner -->
    <div v-if="match?.status !== 'active'" class="bg-white px-4 py-3 text-center shrink-0 space-y-2">
      <p v-if="match?.status === 'finished'" class="text-emerald-600 font-semibold text-sm">
        ✅ Match finished · Scores recorded · Redirecting…
      </p>
      <p v-else class="text-slate-500 text-sm">Match cancelled</p>
      <button class="btn-primary text-sm px-6 py-2" @click="router.push('/matches')">
        Go to Matches →
      </button>
    </div>

    <!-- Court area (flex-1) -->
    <div class="flex-1 flex items-stretch p-2 gap-2 min-h-0">

      <!-- Left rail: Side B score tap -->
      <button @click="scoreBySide('B')" :disabled="!isManager() || match?.status !== 'active' || isMatchWon"
              class="w-12 flex flex-col items-center justify-center rounded-xl bg-violet-900/20 border border-violet-500/30 shrink-0 transition-all"
              :class="!isManager() ? 'opacity-50 cursor-default' : 'active:bg-violet-900/40'">
        <span class="text-violet-400 text-xs font-medium">+1</span>
        <span class="text-violet-400 text-2xl font-bold">{{ currentScoreB }}</span>
      </button>

      <!-- SVG Court -->
      <div class="flex-1 relative rounded-2xl overflow-hidden">
        <svg
          viewBox="0 0 61 134"
          class="w-full h-full"
          preserveAspectRatio="xMidYMid meet"
          xmlns="http://www.w3.org/2000/svg"
        >
          <defs>
            <!-- Court gradient -->
            <linearGradient id="courtGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="#1e6b1e"/>
              <stop offset="100%" stop-color="#165016"/>
            </linearGradient>

            <!-- Avatar clip paths -->
            <clipPath id="clipB0"><circle cx="15" cy="35" r="6"/></clipPath>
            <clipPath id="clipB1"><circle cx="46" cy="35" r="6"/></clipPath>
            <clipPath id="clipA0"><circle cx="46" cy="99" r="6"/></clipPath>
            <clipPath id="clipA1"><circle cx="15" cy="99" r="6"/></clipPath>
          </defs>

          <!-- Court surface -->
          <rect x="0" y="0" width="61" height="134" fill="url(#courtGrad)"/>

          <!-- ── Court lines ── -->
          <!-- Outer doubles boundary -->
          <rect x="0.6" y="0.6" width="59.8" height="132.8"
                fill="none" stroke="white" stroke-width="1.2" stroke-opacity="0.75"/>

          <!-- Singles sidelines (inset 4.6 units each side) -->
          <line x1="4.6" y1="0.6" x2="4.6" y2="133.4" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>
          <line x1="56.4" y1="0.6" x2="56.4" y2="133.4" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>

          <!-- Net line at y=67 (center) — thicker and brighter -->
          <line x1="0.6" y1="67" x2="60.4" y2="67" stroke="white" stroke-width="1.4" stroke-opacity="0.9"/>
          <!-- Net shadow below -->
          <line x1="0.6" y1="67.7" x2="60.4" y2="67.7" stroke="white" stroke-width="0.4" stroke-opacity="0.3"/>

          <!-- Short service lines (19.8 units from net = y=47.2 and y=86.8) -->
          <line x1="0.6" y1="47.2" x2="60.4" y2="47.2" stroke="white" stroke-width="0.6" stroke-opacity="0.6"/>
          <line x1="0.6" y1="86.8" x2="60.4" y2="86.8" stroke="white" stroke-width="0.6" stroke-opacity="0.6"/>

          <!-- Long service lines for doubles (7.6 from baselines) -->
          <line x1="0.6" y1="7.6" x2="60.4" y2="7.6" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>
          <line x1="0.6" y1="126.4" x2="60.4" y2="126.4" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>

          <!-- Center service lines (x=30.5, between short service lines and net only) -->
          <line x1="30.5" y1="47.2" x2="30.5" y2="67" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>
          <line x1="30.5" y1="67" x2="30.5" y2="86.8" stroke="white" stroke-width="0.6" stroke-opacity="0.55"/>

          <!-- Net post indicators at the outer sideline -->
          <rect x="0" y="65.5" width="1.2" height="3" fill="white" fill-opacity="0.7" rx="0.3"/>
          <rect x="59.8" y="65.5" width="1.2" height="3" fill="white" fill-opacity="0.7" rx="0.3"/>

          <!-- ── Side B players (top half, y≈35) ── -->

          <!-- B0: top-left service box (cx=15, cy=35) -->
          <g @click="scoreByPlayer(sideBPlayers[0]?.id)"
             :style="isManager() && match?.status === 'active' && !isMatchWon && sideBPlayers[0] ? 'cursor:pointer' : 'cursor:default'"
             style="transition: opacity 0.15s">
            <!-- tap flash zone -->
            <rect x="0" y="0" width="30.5" height="67" fill="transparent"
                  :fill-opacity="tapping === sideBPlayers[0]?.id ? 0.18 : 0"
                  style="fill: #a855f7"/>

            <!-- avatar circle bg (violet) -->
            <circle cx="15" cy="35" r="6" fill="#7c3aed" fill-opacity="0.9"/>
            <!-- avatar photo (if available) -->
            <image v-if="sideBPlayers[0]?.avatar"
                   :href="sideBPlayers[0].avatar"
                   x="9" y="29" width="12" height="12"
                   clip-path="url(#clipB0)"
                   preserveAspectRatio="xMidYMid slice"/>
            <!-- initial fallback -->
            <text v-else x="15" y="38" text-anchor="middle"
                  fill="white" font-size="5.5" font-weight="bold" font-family="sans-serif">
              {{ initial(sideBPlayers[0]?.name) }}
            </text>

            <!-- player name -->
            <text x="15" y="44.5" text-anchor="middle"
                  fill="white" fill-opacity="0.9" font-size="3.2" font-family="sans-serif">
              {{ (sideBPlayers[0]?.name || '—').slice(0, 10) }}
            </text>

            <!-- serve indicator -->
            <g v-if="servingPlayerId === sideBPlayers[0]?.id">
              <circle cx="22" cy="28" r="1.8" fill="#22d3ee">
                <animate attributeName="r" values="1.8;2.6;1.8" dur="1.2s" repeatCount="indefinite"/>
                <animate attributeName="fill-opacity" values="1;0.5;1" dur="1.2s" repeatCount="indefinite"/>
              </circle>
            </g>
          </g>

          <!-- B1: top-right service box (cx=46, cy=35) -->
          <g @click="scoreByPlayer(sideBPlayers[1]?.id)"
             :style="isManager() && match?.status === 'active' && !isMatchWon && sideBPlayers[1] ? 'cursor:pointer' : 'cursor:default'">
            <rect x="30.5" y="0" width="30.5" height="67" fill="transparent"
                  :fill-opacity="tapping === sideBPlayers[1]?.id ? 0.18 : 0"
                  style="fill: #a855f7"/>

            <circle cx="46" cy="35" r="6" fill="#7c3aed" fill-opacity="0.9"/>
            <image v-if="sideBPlayers[1]?.avatar"
                   :href="sideBPlayers[1].avatar"
                   x="40" y="29" width="12" height="12"
                   clip-path="url(#clipB1)"
                   preserveAspectRatio="xMidYMid slice"/>
            <text v-else x="46" y="38" text-anchor="middle"
                  fill="white" font-size="5.5" font-weight="bold" font-family="sans-serif">
              {{ initial(sideBPlayers[1]?.name) }}
            </text>

            <text x="46" y="44.5" text-anchor="middle"
                  fill="white" fill-opacity="0.9" font-size="3.2" font-family="sans-serif">
              {{ (sideBPlayers[1]?.name || '—').slice(0, 10) }}
            </text>

            <g v-if="servingPlayerId === sideBPlayers[1]?.id">
              <circle cx="39" cy="28" r="1.8" fill="#22d3ee">
                <animate attributeName="r" values="1.8;2.6;1.8" dur="1.2s" repeatCount="indefinite"/>
                <animate attributeName="fill-opacity" values="1;0.5;1" dur="1.2s" repeatCount="indefinite"/>
              </circle>
            </g>
          </g>

          <!-- ── Side A players (bottom half, y≈99) ── -->

          <!-- A0: bottom-right service box (cx=46, cy=99) -->
          <g @click="scoreByPlayer(sideAPlayers[0]?.id)"
             :style="isManager() && match?.status === 'active' && !isMatchWon && sideAPlayers[0] ? 'cursor:pointer' : 'cursor:default'">
            <rect x="30.5" y="67" width="30.5" height="67" fill="transparent"
                  :fill-opacity="tapping === sideAPlayers[0]?.id ? 0.18 : 0"
                  style="fill: #0891b2"/>

            <circle cx="46" cy="99" r="6" fill="#0e7490" fill-opacity="0.9"/>
            <image v-if="sideAPlayers[0]?.avatar"
                   :href="sideAPlayers[0].avatar"
                   x="40" y="93" width="12" height="12"
                   clip-path="url(#clipA0)"
                   preserveAspectRatio="xMidYMid slice"/>
            <text v-else x="46" y="102" text-anchor="middle"
                  fill="white" font-size="5.5" font-weight="bold" font-family="sans-serif">
              {{ initial(sideAPlayers[0]?.name) }}
            </text>

            <text x="46" y="108.5" text-anchor="middle"
                  fill="white" fill-opacity="0.9" font-size="3.2" font-family="sans-serif">
              {{ (sideAPlayers[0]?.name || '—').slice(0, 10) }}
            </text>

            <g v-if="servingPlayerId === sideAPlayers[0]?.id">
              <circle cx="39" cy="92" r="1.8" fill="#22d3ee">
                <animate attributeName="r" values="1.8;2.6;1.8" dur="1.2s" repeatCount="indefinite"/>
                <animate attributeName="fill-opacity" values="1;0.5;1" dur="1.2s" repeatCount="indefinite"/>
              </circle>
            </g>
          </g>

          <!-- A1: bottom-left service box (cx=15, cy=99) -->
          <g @click="scoreByPlayer(sideAPlayers[1]?.id)"
             :style="isManager() && match?.status === 'active' && !isMatchWon && sideAPlayers[1] ? 'cursor:pointer' : 'cursor:default'">
            <rect x="0" y="67" width="30.5" height="67" fill="transparent"
                  :fill-opacity="tapping === sideAPlayers[1]?.id ? 0.18 : 0"
                  style="fill: #0891b2"/>

            <circle cx="15" cy="99" r="6" fill="#0e7490" fill-opacity="0.9"/>
            <image v-if="sideAPlayers[1]?.avatar"
                   :href="sideAPlayers[1].avatar"
                   x="9" y="93" width="12" height="12"
                   clip-path="url(#clipA1)"
                   preserveAspectRatio="xMidYMid slice"/>
            <text v-else x="15" y="102" text-anchor="middle"
                  fill="white" font-size="5.5" font-weight="bold" font-family="sans-serif">
              {{ initial(sideAPlayers[1]?.name) }}
            </text>

            <text x="15" y="108.5" text-anchor="middle"
                  fill="white" fill-opacity="0.9" font-size="3.2" font-family="sans-serif">
              {{ (sideAPlayers[1]?.name || '—').slice(0, 10) }}
            </text>

            <g v-if="servingPlayerId === sideAPlayers[1]?.id">
              <circle cx="22" cy="92" r="1.8" fill="#22d3ee">
                <animate attributeName="r" values="1.8;2.6;1.8" dur="1.2s" repeatCount="indefinite"/>
                <animate attributeName="fill-opacity" values="1;0.5;1" dur="1.2s" repeatCount="indefinite"/>
              </circle>
            </g>
          </g>

          <!-- Side labels -->
          <text x="30.5" y="18" text-anchor="middle"
                fill="white" fill-opacity="0.45" font-size="3" font-family="sans-serif" letter-spacing="0.5">
            SIDE B
          </text>
          <text x="30.5" y="120" text-anchor="middle"
                fill="white" fill-opacity="0.45" font-size="3" font-family="sans-serif" letter-spacing="0.5">
            SIDE A
          </text>
        </svg>

        <!-- Announcement overlay (absolute over the SVG container) -->
        <Transition name="announcement">
          <div v-if="announcement"
               class="absolute top-3 left-1/2 -translate-x-1/2 bg-black/70 text-white text-sm font-semibold px-4 py-1.5 rounded-full backdrop-blur-sm whitespace-nowrap z-10">
            {{ announcement }}
          </div>
        </Transition>

        <!-- Match Won overlay — blocks court, prompts to record -->
        <div v-if="isMatchWon && isManager() && match?.status === 'active'"
             class="absolute inset-0 flex flex-col items-center justify-center z-20"
             style="background:rgba(0,0,0,0.72); backdrop-filter:blur(2px)">
          <div class="text-5xl mb-3">🏆</div>
          <div class="text-white text-xl font-black mb-1">
            {{ matchWinner === 'A' ? sideAPlayers.map(p=>p.name).join(' & ') : sideBPlayers.map(p=>p.name).join(' & ') }}
          </div>
          <div class="text-slate-300 text-sm mb-6">
            Wins! &nbsp;{{ currentScoreA }} – {{ currentScoreB }}
          </div>
          <button class="btn-success text-base px-8 py-3 font-bold" @click="showFinishModal = true">
            ✅ Record Match
          </button>
          <button class="mt-3 text-slate-400 text-xs underline" @click="showCancelModal = true">
            Cancel match
          </button>
        </div>

        <!-- Spectator badge -->
        <div v-if="!isManager()"
             class="absolute bottom-2 left-1/2 -translate-x-1/2 bg-black/50 text-white/70 text-xs px-3 py-1 rounded-full">
          Live · View only
        </div>
      </div>

      <!-- Right rail: Side A score tap -->
      <button @click="scoreBySide('A')" :disabled="!isManager() || match?.status !== 'active' || isMatchWon"
              class="w-12 flex flex-col items-center justify-center rounded-xl bg-cyan-900/20 border border-cyan-500/30 shrink-0 transition-all"
              :class="!isManager() ? 'opacity-50 cursor-default' : 'active:bg-cyan-900/40'">
        <span class="text-cyan-400 text-xs font-medium">+1</span>
        <span class="text-cyan-400 text-2xl font-bold">{{ currentScoreA }}</span>
      </button>
    </div>

    <!-- Action bar -->
    <div class="flex items-center gap-3 px-4 py-3 bg-white border-t border-slate-200 shrink-0">
      <div v-if="isManager()" class="flex flex-col items-start">
        <button @click="undoPoint" :disabled="isMatchWon"
                class="btn-ghost flex items-center gap-1.5 text-sm"
                :class="isMatchWon ? 'opacity-40 cursor-default' : ''">
          ↩ Undo
        </button>
        <span v-if="undoError" class="text-rose-500 text-[10px] mt-0.5">{{ undoError }}</span>
      </div>
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
          </p>
          <p v-if="finishError" class="text-rose-500 text-xs">{{ finishError }}</p>
          <div class="flex gap-3">
            <button @click="showFinishModal = false" class="btn-ghost flex-1" :disabled="finishing">Cancel</button>
            <button @click="finishMatch" class="btn-success flex-1" :disabled="finishing">
              {{ finishing ? 'Saving…' : 'Yes, Record' }}
            </button>
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
