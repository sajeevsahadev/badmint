<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { supabase } from '../lib/supabase'
import { generatePlan, defaultMatchCount } from '../utils/game-plan'

// Shared session game plan (friendly fair-rotation).
// - Managers pass canManage=true + the present `attendees` to generate/edit.
// - Everyone else sees a live read-only table (realtime).
const props = defineProps({
  scheduleId: { type: String, required: true },
  canManage:  { type: Boolean, default: false },
  // Present players for generation: [{ id, name, elo }] — only needed to manage.
  attendees:  { type: Array, default: () => [] },
})

const plan     = ref(null)          // { id, courts, match_count, format, version }
const matches  = ref([])            // [{ id, round, court, seq, side_a[], side_b[], status, match_id }]
const players  = ref({})            // { id: { name, elo } }
const loading  = ref(true)
const busy     = ref(false)
const errorMsg = ref(null)

// Manager inputs
const courts     = ref(1)
const hours       = ref(1)
const matchCount  = ref(6)
watch(hours, h => { matchCount.value = defaultMatchCount(h) })

// tap-to-swap selection: { round, kind:'play'|'rest', matchId?, side?, index?, playerId }
const picked = ref(null)

const nameOf = id => players.value[id]?.name || '—'
const eloOf  = id => players.value[id]?.elo ?? 1000

// All players who appear anywhere in the plan = the day's active roster.
const rosterIds = computed(() => {
  const s = new Set()
  for (const m of matches.value) for (const id of [...m.side_a, ...m.side_b]) s.add(id)
  return [...s]
})

// Group matches by round, and compute who rests each round.
const rounds = computed(() => {
  const byRound = {}
  for (const m of matches.value) (byRound[m.round] ||= []).push(m)
  return Object.keys(byRound).map(Number).sort((a, b) => a - b).map(r => {
    const ms = byRound[r].sort((a, b) => a.court - b.court)
    const playing = new Set()
    for (const m of ms) for (const id of [...m.side_a, ...m.side_b]) playing.add(id)
    const resting = rosterIds.value.filter(id => !playing.has(id))
    return { round: r, matches: ms, resting }
  })
})

const doneCount = computed(() => matches.value.filter(m => m.status === 'done').length)

// ── Load ──────────────────────────────────────────────────────────────
async function load() {
  const { data } = await supabase.rpc('get_session_plan', { p_schedule_id: props.scheduleId })
  if (data) {
    plan.value    = data.plan
    matches.value = data.matches || []
    players.value = data.players || {}
    courts.value  = data.plan.courts
    matchCount.value = data.plan.match_count
  } else {
    plan.value = null; matches.value = []
  }
  loading.value = false
}

// ── Realtime: refresh whenever the plan changes for anyone ──
let channel = null
onMounted(async () => {
  await load()
  channel = supabase
    .channel(`plan-${props.scheduleId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'session_plan_matches' }, load)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'session_plans' }, load)
    .subscribe()
})
onUnmounted(() => { if (channel) supabase.removeChannel(channel) })

// ── Generate / regenerate (manager) ───────────────────────────────────
function gamesPlayedFromDone() {
  const gp = {}
  for (const m of matches.value) if (m.status === 'done')
    for (const id of [...m.side_a, ...m.side_b]) gp[id] = (gp[id] || 0) + 1
  return gp
}

async function generate(regen = false) {
  errorMsg.value = null
  const present = props.attendees.map(a => ({ id: a.id, elo: a.elo ?? 1000 }))
  if (present.length < 4) { errorMsg.value = 'Need at least 4 saved attendees.'; return }

  let done = [], gp = {}, startSeq = 1, startRound = 1, remaining = matchCount.value
  if (regen && plan.value) {
    done = matches.value.filter(m => m.status === 'done')
    gp = gamesPlayedFromDone()
    startSeq   = done.length ? Math.max(...done.map(m => m.seq)) + 1 : 1
    startRound = done.length ? Math.max(...done.map(m => m.round)) + 1 : 1
    remaining  = Math.max(matchCount.value - done.length, 0)
  }
  if (remaining <= 0) { errorMsg.value = 'All matches are already played — raise the match count to add more.'; return }

  const { matches: future, error } = generatePlan({
    players: present, courts: courts.value, matchCount: remaining,
    gamesPlayed: gp, startSeq, startRound,
  })
  if (error) { errorMsg.value = error; return }

  const payload = [
    ...done.map(m => ({ round: m.round, court: m.court, seq: m.seq, side_a: m.side_a, side_b: m.side_b, status: 'done', match_id: m.match_id })),
    ...future.map(m => ({ round: m.round, court: m.court, seq: m.seq, side_a: m.sideA, side_b: m.sideB, status: 'planned' })),
  ]
  busy.value = true
  const { error: err } = await supabase.rpc('save_session_plan', {
    p_schedule_id: props.scheduleId, p_courts: courts.value, p_match_count: matchCount.value, p_matches: payload,
  })
  busy.value = false
  if (err) { errorMsg.value = err.message; return }
  picked.value = null
  await load()
}

async function clearPlan() {
  busy.value = true
  await supabase.rpc('delete_session_plan', { p_schedule_id: props.scheduleId })
  busy.value = false
  await load()
}

// ── Mark a match played / undo (manager) — advances fairness ──
async function toggleDone(m) {
  busy.value = true
  await supabase.rpc('set_plan_match_status', {
    p_plan_match_id: m.id, p_status: m.status === 'done' ? 'planned' : 'done', p_match_id: null,
  })
  busy.value = false
  await load()
}

// ── Tap-to-swap two players within the same round ─────────────────────
function playerSlot(round, m, side, index) {
  return { round, kind: 'play', matchId: m.id, side, index, playerId: m[side][index] }
}
function restSlot(round, playerId) {
  return { round, kind: 'rest', playerId }
}

async function tapSlot(slot) {
  if (!props.canManage) return
  if (!picked.value) { picked.value = slot; return }
  if (picked.value.playerId === slot.playerId) { picked.value = null; return }
  // Only swap within the same round.
  if (picked.value.round !== slot.round) { picked.value = slot; return }

  const a = picked.value, b = slot
  picked.value = null
  busy.value = true
  try {
    // Build updated side arrays per affected match, then persist.
    const updates = new Map() // matchId -> { side_a, side_b }
    const cur = id => matches.value.find(m => m.id === id)
    const ensure = id => {
      if (!updates.has(id)) { const m = cur(id); updates.set(id, { side_a: [...m.side_a], side_b: [...m.side_b] }) }
      return updates.get(id)
    }
    const put = (slotX, pid) => { const u = ensure(slotX.matchId); u[slotX.side][slotX.index] = pid }

    if (a.kind === 'play' && b.kind === 'play') {
      put(a, b.playerId); put(b, a.playerId)
    } else if (a.kind === 'play') {          // b is resting → move rest player in
      put(a, b.playerId)
    } else if (b.kind === 'play') {          // a is resting → move rest player in
      put(b, a.playerId)
    } else { busy.value = false; return }    // rest ↔ rest: nothing to do

    for (const [id, sides] of updates) {
      await supabase.rpc('update_plan_match', { p_plan_match_id: id, p_side_a: sides.side_a, p_side_b: sides.side_b })
    }
  } finally {
    busy.value = false
    await load()
  }
}

const isPicked = pid => picked.value?.playerId === pid
</script>

<template>
  <div class="card p-4">
    <div class="flex items-center justify-between mb-1">
      <div class="text-[10px] uppercase tracking-widest text-slate-500">🗺️ Game Plan</div>
      <span v-if="plan" class="text-[10px] text-slate-400">{{ doneCount }}/{{ matches.length }} played</span>
    </div>

    <div v-if="loading" class="text-center text-sm text-slate-400 py-4 animate-pulse">Loading plan…</div>

    <template v-else>
      <!-- ── Manager: generate controls ── -->
      <div v-if="canManage" class="rounded-xl border border-[rgba(15,23,42,0.08)] p-3 mb-3 space-y-3">
        <div class="grid grid-cols-3 gap-2">
          <label class="block">
            <span class="text-[10px] uppercase tracking-wide text-slate-500">Courts</span>
            <input type="number" min="1" max="8" v-model.number="courts"
              class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
          </label>
          <label class="block">
            <span class="text-[10px] uppercase tracking-wide text-slate-500">Duration</span>
            <select v-model.number="hours" class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700">
              <option :value="1">1 hour</option>
              <option :value="2">2 hours</option>
            </select>
          </label>
          <label class="block">
            <span class="text-[10px] uppercase tracking-wide text-slate-500">Matches</span>
            <input type="number" min="1" max="40" v-model.number="matchCount"
              class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
          </label>
        </div>
        <p class="text-[11px] text-slate-400">
          {{ attendees.length }} attendees · balanced friendly rotation — everyone plays a fair share.
        </p>
        <div class="flex gap-2">
          <button v-if="!plan" class="btn-primary flex-1 py-2 text-sm" :disabled="busy" @click="generate(false)">
            {{ busy ? 'Building…' : '✨ Generate Plan' }}
          </button>
          <template v-else>
            <button class="btn-primary flex-1 py-2 text-sm" :disabled="busy" @click="generate(true)">
              {{ busy ? 'Rebuilding…' : '↻ Regenerate remaining' }}
            </button>
            <button class="btn-ghost text-xs px-3" :disabled="busy" @click="clearPlan">Clear</button>
          </template>
        </div>
        <p v-if="errorMsg" class="text-xs text-rose-500">{{ errorMsg }}</p>
        <p v-if="plan && canManage" class="text-[11px] text-cyan-600">
          Tip: tap a player, then tap another (or a resting player) to swap them for that round.
        </p>
      </div>

      <!-- ── Empty ── -->
      <div v-if="!plan" class="text-center text-sm text-slate-400 py-3">
        <template v-if="canManage">No plan yet — set courts &amp; matches, then Generate.</template>
        <template v-else>The manager hasn't posted a game plan for this session yet.</template>
      </div>

      <!-- ── The plan table (rounds) ── -->
      <div v-else class="space-y-3">
        <div v-for="rd in rounds" :key="rd.round"
          class="rounded-xl border border-[rgba(15,23,42,0.08)] overflow-hidden">
          <div class="px-3 py-1.5 bg-[rgba(15,23,42,0.03)] text-[11px] font-bold uppercase tracking-wide text-slate-500">
            Round {{ rd.round }}
          </div>
          <div class="divide-y divide-[rgba(15,23,42,0.06)]">
            <div v-for="m in rd.matches" :key="m.id"
              class="p-3 flex items-center gap-2"
              :class="m.status === 'done' ? 'bg-emerald-50/60' : ''">
              <div v-if="rd.matches.length > 1 || courts > 1" class="text-[10px] text-slate-400 w-8 shrink-0">C{{ m.court }}</div>
              <div class="flex-1 min-w-0 grid grid-cols-[1fr_auto_1fr] items-center gap-2">
                <!-- Side A -->
                <div class="flex flex-col gap-1 items-start">
                  <button v-for="(pid, i) in m.side_a" :key="'a'+i"
                    :disabled="!canManage || m.status === 'done'"
                    @click="tapSlot(playerSlot(rd.round, m, 'side_a', i))"
                    class="text-xs font-semibold px-2 py-1 rounded-lg max-w-full truncate transition"
                    :class="isPicked(pid) ? 'bg-cyan-500 text-white' : 'bg-slate-100 text-slate-700'">
                    {{ nameOf(pid) }}
                  </button>
                </div>
                <span class="text-[10px] text-slate-400 font-bold">vs</span>
                <!-- Side B -->
                <div class="flex flex-col gap-1 items-end">
                  <button v-for="(pid, i) in m.side_b" :key="'b'+i"
                    :disabled="!canManage || m.status === 'done'"
                    @click="tapSlot(playerSlot(rd.round, m, 'side_b', i))"
                    class="text-xs font-semibold px-2 py-1 rounded-lg max-w-full truncate transition"
                    :class="isPicked(pid) ? 'bg-cyan-500 text-white' : 'bg-slate-100 text-slate-700'">
                    {{ nameOf(pid) }}
                  </button>
                </div>
              </div>
              <button v-if="canManage" class="shrink-0 text-xs px-2 py-1 rounded-lg transition"
                :class="m.status === 'done' ? 'bg-emerald-500 text-white' : 'border border-slate-200 text-slate-500'"
                :disabled="busy" @click="toggleDone(m)">
                {{ m.status === 'done' ? '✓' : 'Played' }}
              </button>
            </div>
            <!-- Resting -->
            <div v-if="rd.resting.length" class="px-3 py-2 flex flex-wrap items-center gap-1.5">
              <span class="text-[10px] uppercase tracking-wide text-slate-400 mr-1">Resting</span>
              <button v-for="pid in rd.resting" :key="'r'+pid"
                :disabled="!canManage"
                @click="tapSlot(restSlot(rd.round, pid))"
                class="text-[11px] px-2 py-0.5 rounded-full transition"
                :class="isPicked(pid) ? 'bg-cyan-500 text-white' : 'bg-slate-100 text-slate-500'">
                {{ nameOf(pid) }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
