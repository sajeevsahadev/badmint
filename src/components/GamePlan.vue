<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import Avatar from './Avatar.vue'
import { generatePlan, defaultMatchCount } from '../utils/game-plan'

// Shared session game plan (friendly fair-rotation).
// - Managers pass canManage=true + present `attendees` to generate/edit.
// - Everyone sees a live read-only table.
// The FIRST unplayed match is the "Next up" — Start This Match feeds Add Match,
// so the plan is the single source of truth for what to play next.
const props = defineProps({
  scheduleId: { type: String, required: true },
  canManage:  { type: Boolean, default: false },
  attendees:  { type: Array,   default: () => [] },   // [{ id, name, elo }] — to generate
  date:       { type: String,  default: '' },          // yyyy-mm-dd for Start This Match
})
const emit = defineEmits(['plan-exists'])
const router = useRouter()

const plan     = ref(null)
const matches  = ref([])
const players  = ref({})
const loading  = ref(true)
const busy     = ref(false)
const errorMsg = ref(null)

const courts     = ref(1)
const hours      = ref(1)
const matchCount = ref(6)
watch(hours, h => { matchCount.value = defaultMatchCount(h) })

const picked = ref(null) // { round, kind:'play'|'rest', matchId?, side?, index?, playerId }

const nameOf   = id => players.value[id]?.name || '—'
const eloOf    = id => players.value[id]?.elo ?? 1000
const avatarOf = id => players.value[id]?.avatar || null
const sideElo  = ids => ids.reduce((s, id) => s + eloOf(id), 0)

const rosterIds = computed(() => {
  const s = new Set()
  for (const m of matches.value) for (const id of [...m.side_a, ...m.side_b]) s.add(id)
  return [...s]
})

// First not-yet-played match, by seq → the "Next up".
const nextUpId = computed(() => {
  const planned = matches.value.filter(m => m.status !== 'done').sort((a, b) => a.seq - b.seq)
  return planned.length ? planned[0].id : null
})

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

async function load() {
  const { data } = await supabase.rpc('get_session_plan', { p_schedule_id: props.scheduleId })
  if (data) {
    plan.value = data.plan; matches.value = data.matches || []; players.value = data.players || {}
    courts.value = data.plan.courts; matchCount.value = data.plan.match_count
  } else {
    plan.value = null; matches.value = []
  }
  loading.value = false
  emit('plan-exists', !!plan.value)
}

let channel = null
onMounted(async () => {
  await load()
  channel = supabase.channel(`plan-${props.scheduleId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'session_plan_matches' }, load)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'session_plans' }, load)
    .subscribe()
})
onUnmounted(() => { if (channel) supabase.removeChannel(channel) })

// ── Generate / regenerate ──
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
  if (remaining <= 0) { errorMsg.value = 'All matches are played — raise the match count to add more.'; return }

  const { matches: future, error } = generatePlan({
    players: present, courts: courts.value, matchCount: remaining, gamesPlayed: gp, startSeq, startRound,
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
async function clearPlan() { busy.value = true; await supabase.rpc('delete_session_plan', { p_schedule_id: props.scheduleId }); busy.value = false; await load() }

async function toggleDone(m) {
  busy.value = true
  await supabase.rpc('set_plan_match_status', { p_plan_match_id: m.id, p_status: m.status === 'done' ? 'planned' : 'done', p_match_id: null })
  busy.value = false; await load()
}

// Start the next match → Add Match, prefilled + linked so it marks done on record.
function startPlanMatch(m) {
  const a = m.side_a.join(','), b = m.side_b.join(',')
  router.push(`/match?sideA=${a}&sideB=${b}&date=${props.date}&planMatch=${m.id}`)
}

// ── Tap-to-swap within a round ──
function playerSlot(round, m, side, index) { return { round, kind: 'play', matchId: m.id, side, index, playerId: m[side][index] } }
function restSlot(round, playerId) { return { round, kind: 'rest', playerId } }
async function tapSlot(slot) {
  if (!props.canManage) return
  if (!picked.value) { picked.value = slot; return }
  if (picked.value.playerId === slot.playerId) { picked.value = null; return }
  if (picked.value.round !== slot.round) { picked.value = slot; return }
  const a = picked.value, b = slot
  picked.value = null; busy.value = true
  try {
    const updates = new Map()
    const cur = id => matches.value.find(m => m.id === id)
    const ensure = id => { if (!updates.has(id)) { const m = cur(id); updates.set(id, { side_a: [...m.side_a], side_b: [...m.side_b] }) } return updates.get(id) }
    const put = (s, pid) => { const u = ensure(s.matchId); u[s.side][s.index] = pid }
    if (a.kind === 'play' && b.kind === 'play') { put(a, b.playerId); put(b, a.playerId) }
    else if (a.kind === 'play') { put(a, b.playerId) }
    else if (b.kind === 'play') { put(b, a.playerId) }
    else { busy.value = false; return }
    for (const [id, sides] of updates)
      await supabase.rpc('update_plan_match', { p_plan_match_id: id, p_side_a: sides.side_a, p_side_b: sides.side_b })
  } finally { busy.value = false; await load() }
}
const isPicked = pid => picked.value?.playerId === pid
</script>

<template>
  <div class="card overflow-hidden">
    <div class="flex items-center justify-between px-4 pt-4 pb-2">
      <div>
        <div class="text-sm font-bold text-slate-800">🗺️ Game Plan</div>
        <div class="text-[10px] text-slate-500 mt-0.5">Balanced rotation · everyone plays a fair share</div>
      </div>
      <span v-if="plan" class="text-[10px] font-semibold text-slate-400 bg-slate-100 rounded-full px-2 py-0.5">
        {{ doneCount }}/{{ matches.length }} played
      </span>
    </div>

    <div v-if="loading" class="text-center text-sm text-slate-400 py-6 animate-pulse">Loading plan…</div>

    <template v-else>
      <!-- Manager controls -->
      <div v-if="canManage" class="px-4 pb-3">
        <div class="rounded-2xl border border-[rgba(15,23,42,0.08)] p-3 space-y-3" style="background:rgba(0,229,255,.03)">
          <div class="grid grid-cols-3 gap-2">
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Courts</span>
              <input type="number" min="1" max="8" v-model.number="courts"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Duration</span>
              <select v-model.number="hours" class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700">
                <option :value="1">1 hour</option><option :value="2">2 hours</option>
              </select>
            </label>
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Matches</span>
              <input type="number" min="1" max="40" v-model.number="matchCount"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
          </div>
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
          <p v-if="plan" class="text-[11px] text-neon">Tip: tap a player, then tap another (or a resting player) to swap them for that round.</p>
        </div>
      </div>

      <!-- Empty -->
      <div v-if="!plan" class="px-4 pb-4 text-center text-sm text-slate-400">
        <template v-if="canManage">Set courts &amp; matches, then Generate a balanced rotation.</template>
        <template v-else>The manager hasn't posted a game plan for this session yet.</template>
      </div>

      <!-- Rounds -->
      <div v-else class="px-4 pb-4 space-y-4">
        <div v-for="rd in rounds" :key="rd.round">
          <div class="flex items-center gap-2 mb-2">
            <span class="text-[10px] font-bold uppercase tracking-widest text-slate-500">Round {{ rd.round }}</span>
            <span class="h-px flex-1 bg-[rgba(15,23,42,0.08)]"></span>
          </div>

          <div class="space-y-2">
            <div v-for="m in rd.matches" :key="m.id"
              class="rounded-2xl p-3 transition"
              :class="[
                m.status === 'done' ? 'bg-emerald-50 border border-emerald-200'
                : m.id === nextUpId ? 'card-neon' : 'border border-[rgba(15,23,42,0.08)]'
              ]">
              <div class="flex items-center justify-between mb-2">
                <span class="text-[9px] font-bold uppercase tracking-wider"
                  :class="m.id === nextUpId && m.status !== 'done' ? 'text-neon' : 'text-slate-400'">
                  {{ m.status === 'done' ? '✓ Played' : m.id === nextUpId ? '● Next up' : 'Upcoming' }}
                  <span v-if="courts > 1" class="text-slate-400"> · Court {{ m.court }}</span>
                </span>
                <button v-if="canManage" class="text-[10px] px-2 py-0.5 rounded-full transition"
                  :class="m.status === 'done' ? 'bg-emerald-500 text-white' : 'border border-slate-200 text-slate-500'"
                  :disabled="busy" @click="toggleDone(m)">
                  {{ m.status === 'done' ? 'Undo' : 'Mark played' }}
                </button>
              </div>

              <div class="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
                <!-- Side A -->
                <div class="rounded-xl p-2" style="background:rgba(0,180,216,.08);border:1px solid rgba(0,180,216,.18)">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-[9px] font-bold text-neon uppercase tracking-wider">Side A</span>
                    <span class="text-[9px] text-slate-400">{{ sideElo(m.side_a) }}</span>
                  </div>
                  <button v-for="(pid, i) in m.side_a" :key="'a'+i"
                    :disabled="!canManage || m.status === 'done'"
                    @click="tapSlot(playerSlot(rd.round, m, 'side_a', i))"
                    class="w-full flex items-center gap-1.5 rounded-lg px-1 py-1 mb-0.5 last:mb-0 transition"
                    :class="isPicked(pid) ? 'bg-cyan-500' : 'active:bg-cyan-100'">
                    <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="22" />
                    <span class="text-[11px] font-semibold truncate" :class="isPicked(pid) ? 'text-white' : 'text-slate-700'">{{ nameOf(pid) }}</span>
                  </button>
                </div>

                <span class="text-[10px] font-black text-slate-300">VS</span>

                <!-- Side B -->
                <div class="rounded-xl p-2" style="background:rgba(168,85,247,.08);border:1px solid rgba(168,85,247,.18)">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-[9px] text-slate-400">{{ sideElo(m.side_b) }}</span>
                    <span class="text-[9px] font-bold text-violet uppercase tracking-wider">Side B</span>
                  </div>
                  <button v-for="(pid, i) in m.side_b" :key="'b'+i"
                    :disabled="!canManage || m.status === 'done'"
                    @click="tapSlot(playerSlot(rd.round, m, 'side_b', i))"
                    class="w-full flex items-center gap-1.5 rounded-lg px-1 py-1 mb-0.5 last:mb-0 transition"
                    :class="isPicked(pid) ? 'bg-violet-500' : 'active:bg-violet-100'">
                    <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="22" />
                    <span class="text-[11px] font-semibold truncate" :class="isPicked(pid) ? 'text-white' : 'text-slate-700'">{{ nameOf(pid) }}</span>
                  </button>
                </div>
              </div>

              <!-- Start This Match (manager, on the next-up match) -->
              <button v-if="canManage && m.id === nextUpId && m.status !== 'done'"
                class="btn-primary w-full mt-2 py-2 text-sm" @click="startPlanMatch(m)">
                ✅ Start This Match
              </button>
            </div>

            <!-- Resting -->
            <div v-if="rd.resting.length" class="flex flex-wrap items-center gap-1.5 pt-1">
              <span class="text-[10px] uppercase tracking-wide text-slate-400 mr-0.5">Resting</span>
              <button v-for="pid in rd.resting" :key="'r'+pid" :disabled="!canManage"
                @click="tapSlot(restSlot(rd.round, pid))"
                class="flex items-center gap-1 rounded-full pl-0.5 pr-2 py-0.5 transition"
                :class="isPicked(pid) ? 'bg-cyan-500' : 'bg-slate-100'">
                <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="18" />
                <span class="text-[10px] font-medium" :class="isPicked(pid) ? 'text-white' : 'text-slate-500'">{{ nameOf(pid) }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
