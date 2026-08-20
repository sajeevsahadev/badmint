<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import Avatar from './Avatar.vue'
import { generatePlan, defaultMatchCount, winnerStaysInit, winnerStaysAdvance } from '../utils/game-plan'

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

// Format: 'friendly' (fair rotation, default) | 'winner_stays' (King of the Court)
const chosenFormat = ref('friendly')   // what the generate control will produce
const showAdvanced = ref(false)
const showHistory  = ref(false)

const picked = ref(null) // { round, kind:'play'|'rest', matchId?, side?, index?, playerId }

const nameOf   = id => players.value[id]?.name || '—'
const eloOf    = id => players.value[id]?.elo ?? 1000
const avatarOf = id => players.value[id]?.avatar || null
const sideElo  = ids => ids.reduce((s, id) => s + eloOf(id), 0)

// Each court gets its own colour so games are instantly distinguishable.
const COURT_COLORS = [
  { line: '#00b4d8', soft: 'rgba(0,180,216,.10)', text: '#0891a8', chip: 'rgba(0,180,216,.14)' },
  { line: '#a855f7', soft: 'rgba(168,85,247,.10)', text: '#8b5cf6', chip: 'rgba(168,85,247,.14)' },
  { line: '#f59e0b', soft: 'rgba(245,158,11,.12)', text: '#c2740a', chip: 'rgba(245,158,11,.16)' },
  { line: '#10b981', soft: 'rgba(16,185,129,.10)', text: '#059669', chip: 'rgba(16,185,129,.14)' },
  { line: '#f43f5e', soft: 'rgba(244,63,94,.10)',  text: '#e11d48', chip: 'rgba(244,63,94,.14)' },
]
const courtStyle = c => COURT_COLORS[(Math.max(1, c || 1) - 1) % COURT_COLORS.length]

// Format picker options + the one-line description shown under it.
const FORMATS = [
  { v: 'friendly',     icon: '🔄', label: 'Fair play' },
  { v: 'winner_stays', icon: '👑', label: 'King court' },
  { v: 'tournament',   icon: '🏆', label: 'Tournament' },
]
const FORMAT_DESC = {
  friendly:     'Balanced teams · everyone plays an equal share. Great for casual sessions.',
  winner_stays: 'Winners keep the court; challengers rotate in. Auto-rotates so nobody hogs it.',
  tournament:   'Round-robin or knockout brackets with seeding, scores and a champion.',
}
const formatDesc = computed(() => FORMAT_DESC[chosenFormat.value] || '')

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

// ── Format-aware derived views ──
const format         = computed(() => plan.value?.format || 'friendly')
const isWinnerStays  = computed(() => format.value === 'winner_stays')
const planState      = computed(() => plan.value?.state || {})
const activeMatches  = computed(() => matches.value.filter(m => m.status !== 'done').sort((a, b) => a.court - b.court || a.seq - b.seq))
const historyMatches = computed(() => matches.value.filter(m => m.status === 'done').sort((a, b) => b.seq - a.seq))
const queueIds       = computed(() => planState.value.queue || [])
const maxSeq = () => matches.value.reduce((m, x) => Math.max(m, x.seq), 0)

async function load() {
  const { data } = await supabase.rpc('get_session_plan', { p_schedule_id: props.scheduleId })
  if (data) {
    plan.value = data.plan; matches.value = data.matches || []; players.value = data.players || {}
    courts.value = data.plan.courts; matchCount.value = data.plan.match_count
    chosenFormat.value = data.plan.format || 'friendly'
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
  if (chosenFormat.value === 'tournament') { router.push('/tournaments'); return }
  if (chosenFormat.value === 'winner_stays') return generateWinnerStays()
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

// ── Winner-stays (King of the Court) ──
async function generateWinnerStays() {
  errorMsg.value = null
  const present = props.attendees.map(a => ({ id: a.id, elo: a.elo ?? 1000 }))
  const { matches: starts, state, error } = winnerStaysInit({ players: present, courts: courts.value })
  if (error) { errorMsg.value = error; return }
  const payload = starts.map(m => ({ round: m.round, court: m.court, seq: m.seq, side_a: m.sideA, side_b: m.sideB, status: 'planned' }))
  busy.value = true
  const { error: err } = await supabase.rpc('save_session_plan', {
    p_schedule_id: props.scheduleId, p_courts: courts.value, p_match_count: 0,
    p_matches: payload, p_format: 'winner_stays', p_state: state,
  })
  busy.value = false
  if (err) { errorMsg.value = err.message; return }
  picked.value = null; await load()
}

// Tap the winner → winners stay, losers + next-up rotate. Advances the queue.
async function markWinner(m, side) {
  const winnerIds = side === 'A' ? m.side_a : m.side_b
  const loserIds  = side === 'A' ? m.side_b : m.side_a
  const present = props.attendees.map(a => ({ id: a.id, elo: a.elo ?? 1000 }))
  const { nextMatch, state } = winnerStaysAdvance({
    court: m.court, winnerIds, loserIds, state: planState.value, players: present,
    seq: maxSeq() + 1, round: m.round,
  })
  const payload = matches.value.map(x => ({
    round: x.round, court: x.court, seq: x.seq, side_a: x.side_a, side_b: x.side_b,
    status: x.id === m.id ? 'done' : x.status,
    winner_side: x.id === m.id ? side : x.winner_side,
    match_id: x.match_id,
  }))
  payload.push({ round: nextMatch.round, court: nextMatch.court, seq: nextMatch.seq, side_a: nextMatch.sideA, side_b: nextMatch.sideB, status: 'planned' })
  busy.value = true
  const { error: err } = await supabase.rpc('save_session_plan', {
    p_schedule_id: props.scheduleId, p_courts: courts.value, p_match_count: 0,
    p_matches: payload, p_format: 'winner_stays', p_state: state,
  })
  busy.value = false
  if (err) { errorMsg.value = err.message; return }
  await load()
}

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
        <div class="text-sm font-bold text-slate-800">
          {{ plan && isWinnerStays ? '👑 King of the Court' : '🗺️ Game Plan' }}
        </div>
        <div class="text-[10px] text-slate-500 mt-0.5">
          {{ plan && isWinnerStays ? 'Winners stay on · challengers rotate in' : 'Balanced rotation · everyone plays a fair share' }}
        </div>
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
          <!-- How do you want to play today? — always visible, compact -->
          <div>
            <div class="grid grid-cols-3 gap-1 p-1 rounded-2xl bg-slate-100">
              <button v-for="opt in FORMATS" :key="opt.v" type="button" @click="chosenFormat = opt.v"
                class="py-1.5 rounded-xl text-[11px] font-bold transition flex flex-col items-center gap-0.5"
                :class="chosenFormat === opt.v ? 'bg-white shadow-sm text-slate-800' : 'text-slate-500 hover:text-slate-700'">
                <span class="text-base leading-none">{{ opt.icon }}</span>{{ opt.label }}
              </button>
            </div>
            <p class="text-[10px] text-slate-500 text-center mt-1.5 leading-relaxed">{{ formatDesc }}</p>
          </div>

          <!-- Courts / duration / matches — only where relevant -->
          <div v-if="chosenFormat !== 'tournament'" class="grid gap-2"
            :class="chosenFormat === 'friendly' ? 'grid-cols-3' : 'grid-cols-1'">
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Courts</span>
              <input type="number" min="1" max="8" v-model.number="courts"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
            <template v-if="chosenFormat === 'friendly'">
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
            </template>
          </div>

          <div class="flex gap-2">
            <button v-if="chosenFormat === 'tournament'" class="btn-primary flex-1 py-2 text-sm gap-1.5" @click="router.push('/tournaments')">
              🏆 Set up a tournament →
            </button>
            <template v-else-if="!plan">
              <button class="btn-primary flex-1 py-2 text-sm" :disabled="busy" @click="generate(false)">
                {{ busy ? 'Building…' : (chosenFormat === 'winner_stays' ? '👑 Start King of the Court' : '✨ Generate Plan') }}
              </button>
            </template>
            <template v-else>
              <button class="btn-primary flex-1 py-2 text-sm" :disabled="busy"
                @click="generate(chosenFormat === 'friendly' && format === 'friendly')">
                {{ busy ? 'Rebuilding…' : (chosenFormat === 'winner_stays' ? '↻ Reshuffle &amp; restart'
                   : format !== 'friendly' ? '✨ Switch to fair rotation' : '↻ Regenerate remaining') }}
              </button>
              <button class="btn-ghost text-xs px-3" :disabled="busy" @click="clearPlan">Clear</button>
            </template>
          </div>
          <p v-if="errorMsg" class="text-xs text-rose-500">{{ errorMsg }}</p>
          <p v-if="plan && !isWinnerStays" class="text-[11px] text-neon">Tip: tap a player, then tap another (or a resting player) to swap them for that round.</p>
        </div>
      </div>

      <!-- Empty -->
      <div v-if="!plan" class="px-4 pb-4 text-center text-sm text-slate-400">
        <template v-if="canManage">Set courts &amp; matches, then Generate a balanced rotation.</template>
        <template v-else>The manager hasn't posted a game plan for this session yet.</template>
      </div>

      <!-- ══ Winner stays (King of the Court) ══ -->
      <div v-else-if="isWinnerStays" class="px-4 pb-4 space-y-4">
        <!-- On court now -->
        <div>
          <div class="text-[10px] font-bold uppercase tracking-widest text-slate-500 mb-2">👑 On court now</div>
          <div class="space-y-2.5">
            <div v-for="m in activeMatches" :key="m.id" class="rounded-2xl p-3"
              :style="{
                borderLeft: '5px solid ' + courtStyle(m.court).line,
                background: 'radial-gradient(130% 130% at 100% 0%, ' + courtStyle(m.court).soft + ', #ffffff 58%)',
                boxShadow: '0 0 0 1.5px ' + courtStyle(m.court).line + ', 0 8px 24px ' + courtStyle(m.court).soft
              }">
              <div class="flex items-center gap-1.5 mb-2">
                <span class="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full"
                  :style="{ background: courtStyle(m.court).chip, color: courtStyle(m.court).text }">Court {{ m.court }}</span>
                <span v-if="(planState.streak && planState.streak[m.court]) > 0"
                  class="text-[9px] font-bold text-amber-600">🔥 {{ planState.streak[m.court] }}-win streak</span>
              </div>
              <div class="grid grid-cols-[1fr_auto_1fr] items-center gap-2">
                <div class="rounded-xl p-2" style="background:rgba(0,180,216,.08);border:1px solid rgba(0,180,216,.18)">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-[9px] font-bold text-neon uppercase tracking-wider">Side A</span>
                    <span class="text-[9px] text-slate-400">{{ sideElo(m.side_a) }}</span>
                  </div>
                  <div v-for="(pid, i) in m.side_a" :key="'wa'+i" class="flex items-center gap-1.5 px-1 py-1">
                    <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="22" />
                    <span class="text-[11px] font-semibold text-slate-700 truncate">{{ nameOf(pid) }}</span>
                  </div>
                </div>
                <span class="text-[10px] font-black text-slate-300">VS</span>
                <div class="rounded-xl p-2" style="background:rgba(168,85,247,.08);border:1px solid rgba(168,85,247,.18)">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-[9px] text-slate-400">{{ sideElo(m.side_b) }}</span>
                    <span class="text-[9px] font-bold text-violet uppercase tracking-wider">Side B</span>
                  </div>
                  <div v-for="(pid, i) in m.side_b" :key="'wb'+i" class="flex items-center gap-1.5 px-1 py-1">
                    <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="22" />
                    <span class="text-[11px] font-semibold text-slate-700 truncate">{{ nameOf(pid) }}</span>
                  </div>
                </div>
              </div>
              <div v-if="canManage" class="grid grid-cols-2 gap-2 mt-2">
                <button class="py-2 text-xs font-bold rounded-xl text-white transition active:scale-[.98]"
                  style="background:#0099b8" :disabled="busy" @click="markWinner(m, 'A')">🏆 Side A won</button>
                <button class="py-2 text-xs font-bold rounded-xl text-white transition active:scale-[.98]"
                  style="background:#8b5cf6" :disabled="busy" @click="markWinner(m, 'B')">🏆 Side B won</button>
              </div>
            </div>
          </div>
        </div>

        <!-- Up next queue -->
        <div v-if="queueIds.length">
          <div class="text-[10px] font-bold uppercase tracking-widest text-slate-500 mb-2">⏳ Up next ({{ queueIds.length }})</div>
          <div class="flex flex-wrap gap-1.5">
            <span v-for="(pid, i) in queueIds" :key="'q'+pid"
              class="flex items-center gap-1 rounded-full pl-0.5 pr-2 py-0.5 bg-slate-100">
              <span class="text-[9px] font-bold text-slate-400 w-4 text-center">{{ i + 1 }}</span>
              <Avatar :name="nameOf(pid)" :src="avatarOf(pid)" :size="18" />
              <span class="text-[10px] font-medium text-slate-600">{{ nameOf(pid) }}</span>
            </span>
          </div>
        </div>

        <!-- History -->
        <div v-if="historyMatches.length">
          <button class="text-[11px] font-semibold text-slate-500 hover:text-slate-700" @click="showHistory = !showHistory">
            {{ showHistory ? '▾' : '▸' }} History · {{ historyMatches.length }} played
          </button>
          <div v-if="showHistory" class="space-y-1 mt-2">
            <div v-for="m in historyMatches" :key="'h'+m.id"
              class="text-[11px] flex items-center gap-1.5 rounded-lg bg-slate-50 px-2.5 py-1.5">
              <span class="truncate" :class="m.winner_side === 'A' ? 'font-bold text-emerald-700' : 'text-slate-400'">{{ m.side_a.map(nameOf).join(' & ') }}</span>
              <span class="text-slate-300 shrink-0">vs</span>
              <span class="truncate" :class="m.winner_side === 'B' ? 'font-bold text-emerald-700' : 'text-slate-400'">{{ m.side_b.map(nameOf).join(' & ') }}</span>
              <span class="ml-auto shrink-0 text-[10px]">🏆</span>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ Friendly · rounds ══ -->
      <div v-else class="px-4 pb-4 space-y-5">
        <div v-for="rd in rounds" :key="rd.round">
          <!-- Round divider -->
          <div class="flex items-center gap-3 mb-2.5">
            <span class="h-px flex-1 bg-[rgba(15,23,42,0.10)]"></span>
            <span class="text-[10px] font-black uppercase tracking-[0.22em] text-slate-500 flex items-center gap-1">
              🏸 Round {{ rd.round }}
            </span>
            <span class="h-px flex-1 bg-[rgba(15,23,42,0.10)]"></span>
          </div>

          <div class="space-y-2.5">
            <div v-for="m in rd.matches" :key="m.id"
              class="relative rounded-2xl overflow-hidden transition"
              :style="{
                borderLeft: '5px solid ' + courtStyle(m.court).line,
                background: m.status === 'done'
                  ? 'linear-gradient(120% 120% at 100% 0%, rgba(16,185,129,.12), #ffffff 55%)'
                  : 'radial-gradient(130% 130% at 100% 0%, ' + courtStyle(m.court).soft + ', #ffffff 58%)',
                boxShadow: m.id === nextUpId && m.status !== 'done'
                  ? '0 0 0 1.5px ' + courtStyle(m.court).line + ', 0 8px 24px ' + courtStyle(m.court).soft
                  : '0 1px 2px rgba(15,23,42,.04)'
              }">
              <div class="p-3">
                <!-- Header: game number + court chip + status -->
                <div class="flex items-center justify-between mb-2">
                  <div class="flex items-center gap-1.5 min-w-0">
                    <span class="text-xs font-black" :style="{ color: courtStyle(m.court).text }">GAME {{ m.seq }}</span>
                    <span class="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full shrink-0"
                      :style="{ background: courtStyle(m.court).chip, color: courtStyle(m.court).text }">
                      Court {{ m.court }}
                    </span>
                    <span v-if="m.id === nextUpId && m.status !== 'done'"
                      class="text-[8px] font-black uppercase tracking-wider px-1.5 py-0.5 rounded-full text-white shrink-0"
                      :style="{ background: courtStyle(m.court).line }">▶ Next</span>
                    <span v-if="m.status === 'done'" class="text-[9px] font-bold text-emerald-600 shrink-0">✓ Played</span>
                  </div>
                  <button v-if="canManage" class="text-[10px] px-2 py-0.5 rounded-full transition shrink-0"
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
            </div>

            <!-- Resting -->
            <div v-if="rd.resting.length" class="flex flex-wrap items-center gap-1.5 pt-0.5">
              <span class="text-[10px] uppercase tracking-wide text-slate-400 mr-0.5">😴 Resting</span>
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
