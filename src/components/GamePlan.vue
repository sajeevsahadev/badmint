<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import Avatar from './Avatar.vue'
import { generatePlan, defaultMatchCount, winnerStaysAdvance } from '../utils/game-plan'

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
// Duration is a convenience that seeds the match count; the user can still
// fine-tune matches. Only recompute on an actual user change (never on load),
// so restoring a saved plan keeps its exact match count.
function onHoursChange() {
  const h = Math.max(1, Math.round(Number(hours.value) || 1))
  hours.value = h
  matchCount.value = defaultMatchCount(h)
}

// Only "friendly" (fair rotation) is offered now. `chosenFormat` is kept so
// older saved plans (e.g. a legacy winner_stays plan) still render/regenerate
// correctly via load(), but new plans are always friendly.
const chosenFormat = ref('friendly')
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

// ── Export & share (PDF / Excel / link) ─────────────────────────────
const shareNote = ref('')
let noteTimer = null
function flashNote(msg) {
  shareNote.value = msg
  clearTimeout(noteTimer)
  noteTimer = setTimeout(() => { shareNote.value = '' }, 2500)
}

const fmtLabel = computed(() =>
  isWinnerStays.value ? 'King of the Court' : format.value === 'tournament' ? 'Tournament' : 'Fair rotation')
const planDateLabel = computed(() => {
  if (!props.date) return ''
  const d = new Date(props.date + 'T00:00:00')
  return isNaN(d) ? props.date : d.toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' })
})

// Ordered rows for export: play order (seq), each with names + status.
function exportRows() {
  return [...matches.value].sort((a, b) => a.seq - b.seq).map(m => ({
    game: m.seq,
    court: m.court,
    round: m.round,
    sideA: m.side_a.map(nameOf).join(' & '),
    sideB: m.side_b.map(nameOf).join(' & '),
    status: m.status === 'done'
      ? (m.winner_side ? `Played · Side ${m.winner_side} won` : 'Played')
      : (m.id === nextUpId.value ? 'Next up' : 'Upcoming'),
  }))
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url; a.download = filename
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

// Excel-friendly CSV (opens directly in Excel / Google Sheets / Numbers).
function downloadExcel() {
  const rows = [['Game', 'Court', 'Round', 'Side A', 'Side B', 'Status'],
    ...exportRows().map(r => [r.game, r.court, r.round, r.sideA, r.sideB, r.status])]
  const csv = rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\r\n')
  // BOM so Excel reads UTF-8 (names with accents) correctly.
  downloadBlob(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }),
    `game-plan-${props.date || 'session'}.csv`)
  flashNote('Excel file downloaded')
}

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

// PDF via a branded print window → the browser's "Save as PDF" (zero extra deps,
// works on desktop and mobile). Also prints nicely on paper.
function downloadPdf() {
  const rowsHtml = exportRows().map(r => `
    <tr class="${r.status.startsWith('Played') ? 'done' : ''}">
      <td class="num">${r.game}</td>
      <td><span class="court c${((r.court - 1) % 5) + 1}">Court ${r.court}</span></td>
      <td class="team">${esc(r.sideA)}</td>
      <td class="vs">vs</td>
      <td class="team">${esc(r.sideB)}</td>
      <td class="st">${esc(r.status)}</td>
    </tr>`).join('')
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>Game Plan${props.date ? ' · ' + props.date : ''}</title>
<style>
  *{box-sizing:border-box} body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a;margin:32px;background:#fff}
  .head{display:flex;align-items:center;gap:12px;border-bottom:3px solid #00b4d8;padding-bottom:14px;margin-bottom:6px}
  .logo{width:40px;height:40px;border-radius:10px;background:linear-gradient(135deg,#00b4d8,#a855f7);color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px}
  h1{font-size:22px;margin:0} .sub{color:#64748b;font-size:13px;margin:2px 0 18px}
  table{width:100%;border-collapse:collapse;font-size:14px}
  th{text-align:left;color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.5px;border-bottom:2px solid #e2e8f0;padding:8px 6px}
  td{padding:10px 6px;border-bottom:1px solid #eef2f7;vertical-align:middle}
  tr.done{color:#94a3b8} tr.done .team{text-decoration:line-through}
  .num{font-weight:800;color:#0891a8;width:44px} .vs{color:#94a3b8;text-align:center;width:34px} .team{font-weight:600}
  .st{color:#64748b;font-size:12px;white-space:nowrap} .court{font-weight:700;font-size:12px;padding:2px 8px;border-radius:999px}
  .c1{background:rgba(0,180,216,.14);color:#0891a8} .c2{background:rgba(168,85,247,.14);color:#8b5cf6}
  .c3{background:rgba(245,158,11,.16);color:#c2740a} .c4{background:rgba(16,185,129,.14);color:#059669} .c5{background:rgba(244,63,94,.14);color:#e11d48}
  .foot{margin-top:22px;color:#94a3b8;font-size:11px;border-top:1px solid #eef2f7;padding-top:10px}
  @media print{body{margin:14mm} .noprint{display:none}}
</style></head><body>
  <div class="head"><div class="logo">🏸</div><div><h1>Game Plan</h1></div></div>
  <div class="sub">${esc(planDateLabel.value || props.date || '')} · ${plan.value?.courts || 1} court(s) · ${esc(fmtLabel.value)} · ${matches.value.length} games</div>
  <table><thead><tr><th>#</th><th>Court</th><th>Side A</th><th></th><th>Side B</th><th>Status</th></tr></thead>
  <tbody>${rowsHtml}</tbody></table>
  <div class="foot">Generated by Badminton 360 · badminton360.app</div>
  <script>window.onload=function(){setTimeout(function(){window.print()},250)}<\/script>
</body></html>`
  const w = window.open('', '_blank')
  if (!w) { flashNote('Allow pop-ups to save the PDF'); return }
  w.document.write(html); w.document.close()
  flashNote('Opening print / Save as PDF…')
}

// Share the live plan link + a text summary (everyone can share; the plan is
// already live for members on the poll page).
function planSummaryText() {
  const lines = [`🏸 Game Plan${props.date ? ' — ' + planDateLabel.value : ''}`, '']
  for (const r of exportRows().filter(r => !r.status.startsWith('Played'))) {
    lines.push(`Game ${r.game} (Court ${r.court}): ${r.sideA} vs ${r.sideB}`)
  }
  return lines.join('\n')
}
async function sharePlan() {
  const url = `https://badminton360.app/poll/${props.scheduleId}`
  const text = planSummaryText() + `\n\nLive plan → ${url}`
  if (navigator.share) {
    try { await navigator.share({ title: 'Game Plan', text }); return } catch (e) { if (e?.name === 'AbortError') return }
  }
  try { await navigator.clipboard.writeText(text); flashNote('Plan copied — paste into WhatsApp') }
  catch { flashNote('Could not share on this device') }
}

async function load() {
  const { data } = await supabase.rpc('get_session_plan', { p_schedule_id: props.scheduleId })
  if (data) {
    plan.value = data.plan; matches.value = data.matches || []; players.value = data.players || {}
    courts.value = data.plan.courts; matchCount.value = data.plan.match_count
    hours.value = Math.max(1, Math.round((data.plan.match_count || 6) / 6))   // reflect saved duration
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
onUnmounted(() => { if (channel) supabase.removeChannel(channel); clearTimeout(noteTimer) })

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

// ── Winner-stays (King of the Court) ──
// Tap the winner → winners stay, losers + next-up rotate. Advances the queue.
// (Retained so any previously-saved "King of the Court" plan still advances;
//  new plans are always fair-play.)
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
          <!-- Courts / duration / matches -->
          <div class="grid grid-cols-3 gap-2">
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Courts</span>
              <input type="number" min="1" max="8" v-model.number="courts"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Hours</span>
              <input type="number" min="1" max="8" step="0.5" v-model.number="hours" @change="onHoursChange"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
            <label class="block">
              <span class="text-[10px] uppercase tracking-wide text-slate-500">Matches</span>
              <input type="number" min="1" max="40" v-model.number="matchCount"
                class="w-full rounded-lg border border-slate-200 px-2 py-1.5 text-sm bg-white text-slate-700" />
            </label>
          </div>

          <div class="flex gap-2">
            <template v-if="!plan">
              <button class="btn-primary flex-1 py-2 text-sm" :disabled="busy" @click="generate(false)">
                {{ busy ? 'Building…' : '✨ Generate Plan' }}
              </button>
            </template>
            <template v-else>
              <button class="btn-primary flex-1 py-2 text-sm" :disabled="busy" @click="generate(true)">
                {{ busy ? 'Rebuilding…' : '↻ Regenerate remaining' }}
              </button>
              <button class="btn-ghost text-xs px-3" :disabled="busy" @click="clearPlan">Clear</button>
            </template>
          </div>
          <p v-if="errorMsg" class="text-xs text-rose-500">{{ errorMsg }}</p>
          <p v-if="plan && !isWinnerStays" class="text-[11px] text-neon">Tip: tap a player, then tap another (or a resting player) to swap them for that round.</p>
        </div>
      </div>

      <!-- Share / export the plan -->
      <div v-if="plan" class="px-4 pb-3">
        <div class="flex items-center gap-2">
          <button class="btn-ghost flex-1 py-1.5 text-xs gap-1" @click="sharePlan" title="Share the live plan">
            <span>📤</span> Share
          </button>
          <template v-if="canManage">
            <button class="btn-ghost flex-1 py-1.5 text-xs gap-1" @click="downloadPdf" title="Save as PDF">
              <span>📄</span> PDF
            </button>
            <button class="btn-ghost flex-1 py-1.5 text-xs gap-1" @click="downloadExcel" title="Download for Excel">
              <span>📊</span> Excel
            </button>
          </template>
        </div>
        <p v-if="shareNote" class="text-[11px] text-neon text-center mt-1.5 fade-up">{{ shareNote }}</p>
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
