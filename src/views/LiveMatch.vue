<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { currentClub, isManager } = useClub()

const liveId  = route.params.id
const match   = ref(null)
const loading = ref(true)
const error   = ref(null)

// Player names resolved from players table
const nameMap = ref({})

// Point history for dot display (tracked client-side; resets on page load)
const pointHistory = ref([])  // 'A' | 'B' entries, last 10

const saving      = ref(false)
const showConfirm = ref(false)
const matchName   = ref('')
const cancelConfirm = ref(false)

// ── Load ──────────────────────────────────────────────────────────────────────
async function load() {
  loading.value = true
  const { data, error: e } = await supabase
    .from('live_matches')
    .select('*')
    .eq('id', liveId)
    .single()
  if (e || !data) { error.value = e?.message ?? 'Match not found'; loading.value = false; return }
  match.value = data

  // Resolve player names
  const allIds = [...new Set([...data.side_a, ...data.side_b])]
  const players = await supabase.from('players')
    .select('id, display_name, user_id')
    .in('id', allIds)
  const rows = await withNicknames(players.data ?? [])
  const m = {}
  rows.forEach(p => { m[p.id] = p.display_name })
  nameMap.value = m

  loading.value = false
}

// ── Realtime ──────────────────────────────────────────────────────────────────
let channel = null

onMounted(async () => {
  await load()

  channel = supabase.channel(`live_match_${liveId}`)
    .on('postgres_changes', {
      event: 'UPDATE',
      schema: 'public',
      table: 'live_matches',
      filter: `id=eq.${liveId}`
    }, payload => {
      const old = match.value
      match.value = { ...match.value, ...payload.new }
      // Detect which side scored for dot history
      if (payload.new.score_a > (old?.score_a ?? 0)) pointHistory.value.push('A')
      else if (payload.new.score_b > (old?.score_b ?? 0)) pointHistory.value.push('B')
      if (pointHistory.value.length > 10) pointHistory.value.shift()
    })
    .subscribe()
})

onUnmounted(() => {
  if (channel) supabase.removeChannel(channel)
})

// ── Score helpers ──────────────────────────────────────────────────────────────
const scoreA = computed(() => match.value?.score_a ?? 0)
const scoreB = computed(() => match.value?.score_b ?? 0)
const status = computed(() => match.value?.status ?? 'active')

const isDeuce = computed(() => scoreA.value >= 20 && scoreB.value >= 20 && scoreA.value === scoreB.value)
const matchPointA = computed(() => scoreA.value >= 20 && scoreA.value === scoreB.value + 1)
const matchPointB = computed(() => scoreB.value >= 20 && scoreB.value === scoreA.value + 1)

const statusBanner = computed(() => {
  if (isDeuce.value) return { text: 'DEUCE', cls: 'bg-amber-100 text-amber-700' }
  if (matchPointA.value) return { text: 'MATCH POINT · Side A', cls: 'bg-cyan-100 text-cyan-700' }
  if (matchPointB.value) return { text: 'MATCH POINT · Side B', cls: 'bg-violet-100 text-violet-700' }
  return null
})

function nameOf(id) { return nameMap.value[id] ?? '…' }

const namesA = computed(() => (match.value?.side_a ?? []).map(nameOf).join(' & '))
const namesB = computed(() => (match.value?.side_b ?? []).map(nameOf).join(' & '))

// Last 5 points for dots display
const recentPoints = computed(() => pointHistory.value.slice(-5))

// ── Manager actions ───────────────────────────────────────────────────────────
async function addPoint(side) {
  if (!isManager() || status.value !== 'active') return
  const { data } = await supabase.rpc('add_live_point', {
    p_live_match_id: liveId,
    p_side: side
  })
  // Realtime will update match.value; also update history immediately
  if (data) {
    pointHistory.value.push(side)
    if (pointHistory.value.length > 10) pointHistory.value.shift()
  }
}

async function undoPoint() {
  if (!isManager() || status.value !== 'active') return
  await supabase.rpc('undo_live_point', { p_live_match_id: liveId })
  // Remove last history entry (best-effort)
  pointHistory.value.pop()
}

async function finishMatch() {
  if (!isManager()) return
  saving.value = true
  const { data: matchId, error: e } = await supabase.rpc('finish_live_match', {
    p_live_match_id: liveId,
    p_display_name: matchName.value.trim() || null
  })
  saving.value = false
  showConfirm.value = false
  if (e) { error.value = e.message; return }

  // Update rotation stats after finishing
  const playedIds = [...(match.value?.side_a ?? []), ...(match.value?.side_b ?? [])]
  if (currentClub.value) {
    supabase.rpc('update_rotation_stats', {
      p_club_id:      currentClub.value.club_id,
      p_session_date: match.value?.played_on ?? new Date().toISOString().slice(0, 10),
      p_played_ids:   playedIds,
      p_bench_ids:    []
    }).catch(() => null)
  }

  router.push('/matches')
}

async function cancelMatch() {
  if (!isManager()) return
  await supabase.from('live_matches').update({ status: 'cancelled' }).eq('id', liveId)
  cancelConfirm.value = false
  router.push('/matches')
}
</script>

<template>
  <div>
    <!-- Back -->
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-4"
      @click="router.push('/matches')">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
      </svg>
      Match History
    </button>

    <div v-if="loading" class="text-center py-16 text-slate-400">Loading…</div>

    <div v-else-if="error" class="card p-6 text-center text-rose-500">{{ error }}</div>

    <template v-else-if="match">

      <!-- Finished / cancelled banner -->
      <div v-if="status !== 'active'" class="card p-4 text-center mb-4">
        <p v-if="status === 'finished'" class="text-emerald-600 font-semibold">
          Match finished · Scores recorded
        </p>
        <p v-else class="text-slate-500">Match cancelled</p>
      </div>

      <!-- Spectator banner for non-managers -->
      <div v-if="!isManager() && status === 'active'"
        class="rounded-xl px-4 py-2 mb-4 flex items-center gap-2 text-xs"
        style="background:rgba(0,180,216,.08); border:1px solid rgba(0,180,216,.2)">
        <span class="relative flex h-2 w-2">
          <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-75"></span>
          <span class="relative inline-flex rounded-full h-2 w-2 bg-cyan-500"></span>
        </span>
        <span class="text-slate-600 font-medium">Live · Watching in real time</span>
      </div>

      <!-- Status deuce/match-point banner -->
      <div v-if="statusBanner && status === 'active'"
        class="rounded-xl px-4 py-2.5 mb-4 text-center font-bold text-sm tracking-widest"
        :class="statusBanner.cls">
        {{ statusBanner.text }}
      </div>

      <!-- Score display -->
      <div class="card mb-4 overflow-hidden">
        <div class="grid grid-cols-3 items-center">

          <!-- Side A -->
          <div class="p-5 text-center">
            <div class="flex items-center justify-center gap-1 mb-1">
              <span v-if="match.serving_side === 'A'" class="text-base">🏸</span>
              <span class="text-[10px] font-bold uppercase tracking-wider text-neon">Side A</span>
            </div>
            <div class="font-display text-7xl font-black text-neon leading-none">{{ scoreA }}</div>
            <div class="mt-2 text-[11px] text-slate-500 leading-tight">{{ namesA }}</div>
          </div>

          <!-- VS -->
          <div class="text-center">
            <div class="text-slate-300 font-bold text-lg">VS</div>
            <div class="mt-1 text-[10px] text-slate-400">
              {{ match.played_on }}
            </div>
          </div>

          <!-- Side B -->
          <div class="p-5 text-center">
            <div class="flex items-center justify-center gap-1 mb-1">
              <span class="text-[10px] font-bold uppercase tracking-wider text-violet">Side B</span>
              <span v-if="match.serving_side === 'B'" class="text-base">🏸</span>
            </div>
            <div class="font-display text-7xl font-black text-violet leading-none">{{ scoreB }}</div>
            <div class="mt-2 text-[11px] text-slate-500 leading-tight">{{ namesB }}</div>
          </div>
        </div>

        <!-- Point history dots -->
        <div v-if="recentPoints.length" class="border-t border-slate-100 px-4 py-2.5 flex items-center gap-1.5 justify-center">
          <span class="text-[10px] text-slate-400 mr-1">Last {{ recentPoints.length }}</span>
          <span v-for="(pt, i) in recentPoints" :key="i"
            class="w-3 h-3 rounded-full"
            :class="pt === 'A' ? 'bg-cyan-400' : 'bg-violet-400'">
          </span>
        </div>
      </div>

      <!-- Manager controls -->
      <template v-if="isManager() && status === 'active'">
        <!-- +1 buttons -->
        <div class="grid grid-cols-2 gap-3 mb-3">
          <button
            class="py-6 rounded-2xl text-2xl font-black text-white active:scale-95 transition-transform disabled:opacity-40"
            style="background:#00b4d8; min-height:80px"
            :disabled="scoreA >= 30"
            @click="addPoint('A')">
            +1 Side A
          </button>
          <button
            class="py-6 rounded-2xl text-2xl font-black text-white active:scale-95 transition-transform disabled:opacity-40"
            style="background:#a855f7; min-height:80px"
            :disabled="scoreB >= 30"
            @click="addPoint('B')">
            +1 Side B
          </button>
        </div>

        <!-- Undo -->
        <div class="flex justify-center mb-4">
          <button class="btn-ghost px-5 py-2 text-sm" @click="undoPoint">
            ↩ Undo Last Point
          </button>
        </div>

        <!-- Finish / Cancel -->
        <div class="grid grid-cols-2 gap-3">
          <button class="btn-danger py-3 text-sm font-semibold"
            @click="cancelConfirm = true">
            Cancel Match
          </button>
          <button class="btn-success py-3 text-sm font-semibold"
            :disabled="scoreA === scoreB"
            @click="showConfirm = true">
            🏁 Finish & Record
          </button>
        </div>
        <p v-if="scoreA === scoreB" class="text-center text-xs text-amber-500 mt-2">
          Scores must differ before finishing
        </p>
      </template>

    </template>

    <!-- Finish confirmation modal -->
    <Teleport to="body">
      <div v-if="showConfirm"
        class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4 pb-6 sm:pb-0">
        <div class="card w-full max-w-sm p-6 space-y-4">
          <h3 class="font-display text-lg font-bold text-slate-800">Record this match?</h3>
          <p class="text-sm text-slate-500">
            Side A <strong>{{ scoreA }}</strong> – <strong>{{ scoreB }}</strong> Side B
            will be saved and Elo ratings updated.
          </p>
          <div>
            <label class="text-xs text-slate-500 block mb-1">Match name (optional)</label>
            <input v-model="matchName" class="input" placeholder="Auto-generated" maxlength="40" />
          </div>
          <div class="grid grid-cols-2 gap-2 pt-1">
            <button class="btn-ghost py-2.5 text-sm" @click="showConfirm = false">Cancel</button>
            <button class="btn-success py-2.5 text-sm font-semibold"
              :disabled="saving" @click="finishMatch">
              {{ saving ? 'Saving…' : 'Yes, Record' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Cancel confirmation modal -->
    <Teleport to="body">
      <div v-if="cancelConfirm"
        class="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4 pb-6 sm:pb-0">
        <div class="card w-full max-w-sm p-6 space-y-4">
          <h3 class="font-display text-lg font-bold text-slate-800">Cancel this match?</h3>
          <p class="text-sm text-slate-500">The live session will end. No scores will be saved.</p>
          <div class="grid grid-cols-2 gap-2 pt-1">
            <button class="btn-ghost py-2.5 text-sm" @click="cancelConfirm = false">Keep Playing</button>
            <button class="btn-danger py-2.5 text-sm font-semibold" @click="cancelMatch">
              Yes, Cancel
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
