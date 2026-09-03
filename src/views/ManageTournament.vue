<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import DateField from '../components/DateField.vue'
import { generateDraw, buildKnockoutFromGroups, assignCourts, computeGroupStandings } from '../utils/tournament-draw'
import { championCard, announcementCard, downloadDataUrl } from '../utils/tournament-share'
import { uploadClubImage } from '../lib/r2Upload'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { isManager } = useClub()

const data    = ref(null)
const loading = ref(true)
const busy    = ref('')
const err     = ref('')
const ok      = ref('')
const tab     = ref('registrations') // registrations | bracket | settings

// Score recording
const scoreModal   = ref(null) // { match, scoreA: '', scoreB: '' }
const scoreBusy    = ref(false)
const scoreErr     = ref('')

// Settings edit
const settings = ref({})
const settingsBusy = ref(false)
const settingsOk   = ref(false)

async function load() {
  loading.value = true
  const { data: d, error } = await supabase.rpc('get_tournament_detail', {
    p_tournament_id: route.params.id
  })
  if (error || !d) { loading.value = false; return }
  data.value = d
  if (d.tournament) {
    settings.value = {
      name:             d.tournament.name,
      venue:            d.tournament.venue ?? '',
      venue_address:    d.tournament.venue_address ?? '',
      emirate:          d.tournament.emirate ?? '',
      entry_fee:        d.tournament.entry_fee ?? '',
      prize_info:       d.tournament.prize_info ?? '',
      description:      d.tournament.description ?? '',
      registration_end: d.tournament.registration_end ?? '',
      start_date:       d.tournament.start_date ?? '',
      end_date:         d.tournament.end_date ?? '',
      max_teams:        d.tournament.max_teams ?? 8,
    }
    media.value = {
      cover: d.tournament.cover_photo_url ?? '',
      group: d.tournament.group_photo_url ?? '',
    }
  }
  loading.value = false
}

// ── Live updates: reload (debounced) when matches/tournament change ──
let channel = null
let reloadTimer = null
function scheduleReload() {
  clearTimeout(reloadTimer)
  reloadTimer = setTimeout(() => { load() }, 400)
}
onMounted(() => {
  load()
  channel = supabase
    .channel('tour-manage-' + route.params.id)
    .on('postgres_changes',
      { event: '*', schema: 'public', table: 'tournament_matches', filter: 'tournament_id=eq.' + route.params.id },
      scheduleReload)
    .on('postgres_changes',
      { event: '*', schema: 'public', table: 'tournaments', filter: 'id=eq.' + route.params.id },
      scheduleReload)
    .subscribe()
})
onUnmounted(() => {
  clearTimeout(reloadTimer)
  if (channel) supabase.removeChannel(channel)
})

const tour          = computed(() => data.value?.tournament)
const registrations = computed(() => data.value?.registrations ?? [])
const matches       = computed(() => data.value?.matches ?? [])

const confirmed = computed(() => registrations.value.filter(r => r.status === 'confirmed'))
const pending   = computed(() => registrations.value.filter(r => r.status === 'pending'))

// ── Group stage (groups_knockout) ──
const isGroups        = computed(() => tour.value?.draw_type === 'groups_knockout')
const groupMatches    = computed(() => matches.value.filter(m => m.stage === 'group'))
const knockoutMatches = computed(() => matches.value.filter(m => m.stage && m.stage !== 'group'))
const knockoutExists  = computed(() => knockoutMatches.value.length > 0)
const groupStageDone  = computed(() =>
  groupMatches.value.length > 0 && groupMatches.value.every(m => m.status === 'completed' || m.status === 'bye'))
const nameFor = id => registrations.value.find(r => r.id === id)?.team_name || 'TBD'
const groupStandings = computed(() =>
  computeGroupStandings(matches.value).map(g => ({
    ...g,
    teams: g.teams.map(t => ({ ...t, name: nameFor(t.id) })),
  })))

// Sectioned match list for round_robin / groups_knockout rendering.
const flatSections = computed(() => {
  if (isGroups.value) {
    const secs = groupStandings.value.map(g => ({
      key: 'g-' + g.label, title: 'Group ' + g.label,
      matches: groupMatches.value.filter(m => m.group_label === g.label),
    }))
    if (knockoutExists.value) secs.push({ key: 'ko', title: 'Knockout', matches: knockoutMatches.value })
    return secs
  }
  return [{ key: 'all', title: '', matches: matches.value }]
})

const roundsMap = computed(() => {
  const m = {}
  matches.value.forEach(match => {
    if (!m[match.round]) m[match.round] = []
    m[match.round].push(match)
  })
  return m
})
const rounds = computed(() =>
  Object.entries(roundsMap.value).map(([r, ms]) => ({
    round: Number(r),
    matches: ms.sort((a, b) => a.position - b.position)
  })).sort((a, b) => a.round - b.round)
)
const totalRounds = computed(() => rounds.value.length)
const roundLabel = (r, total) => {
  if (tour.value?.format === 'round_robin') return 'All Matches'
  const fromEnd = total - r
  if (fromEnd === 0) return 'Final'
  if (fromEnd === 1) return 'Semi'
  if (fromEnd === 2) return 'Quarter'
  return `R${r}`
}

const emirates = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

async function setStatus(newStatus) {
  err.value = ''; ok.value = ''; busy.value = 'status'
  const { error } = await supabase.rpc('update_tournament_status', {
    p_tournament_id: tour.value.id,
    p_status: newStatus
  })
  busy.value = ''
  if (error) { err.value = error.message; return }
  ok.value = 'Status updated'
  await load()
}

async function approve(regId) {
  busy.value = 'reg-' + regId
  const { error } = await supabase.rpc('approve_registration', { p_reg_id: regId })
  busy.value = ''
  if (error) { err.value = error.message; return }
  await load()
}

async function reject(regId) {
  busy.value = 'reg-' + regId
  await supabase.rpc('reject_registration', { p_reg_id: regId })
  busy.value = ''
  await load()
}

async function setSeed(regId, seed) {
  await supabase.rpc('set_seed', { p_reg_id: regId, p_seed: Number(seed) })
  await load()
}

async function generateBracket() {
  err.value = ''; busy.value = 'bracket'
  const teams = confirmed.value.map(r => ({ id: r.id, seed: r.seed ?? 1 }))
  const { matches: drawn, error: derr } = generateDraw({
    teams,
    drawType:    tour.value.draw_type || 'knockout',
    groupsCount: tour.value.groups_count || 2,
    courts:      tour.value.courts || 1,
  })
  if (derr) { busy.value = ''; err.value = derr; return }
  const { error } = await supabase.rpc('save_generated_draw', {
    p_tournament_id: tour.value.id, p_matches: drawn, p_set_live: true,
  })
  busy.value = ''
  if (error) { err.value = error.message; return }
  ok.value = tour.value.draw_type === 'groups_knockout'
    ? 'Group stage generated! Tournament is now Live.'
    : 'Draw generated! Tournament is now Live.'
  tab.value = 'bracket'
  await load()
}

// ── Generate the knockout stage from finished group standings ──
async function generateKnockout() {
  err.value = ''; ok.value = ''; busy.value = 'knockout'
  const standings = computeGroupStandings(matches.value)
    .map(g => ({ label: g.label, teams: g.teams.map(t => ({ id: t.id })) }))
  const per = tour.value.advance_per_group || 2
  let ko = buildKnockoutFromGroups(standings, per, { stage: 'knockout' })
  if (!ko.length) { busy.value = ''; err.value = 'Not enough teams advanced to build a knockout.'; return }
  assignCourts(ko, tour.value.courts || 1)
  const { error } = await supabase.rpc('save_knockout_stage', {
    p_tournament_id: tour.value.id, p_matches: ko,
  })
  busy.value = ''
  if (error) { err.value = error.message; return }
  ok.value = 'Knockout stage generated from group standings!'
  await load()
}

// ── Export the game plan (PDF via print, Excel via CSV) ──
function drawRows() {
  return [...matches.value]
    .sort((a, b) => (a.stage === 'group' ? 0 : 1) - (b.stage === 'group' ? 0 : 1)
      || (a.group_label || '').localeCompare(b.group_label || '') || a.round - b.round || a.position - b.position)
    .map(m => ({
      stage: m.stage === 'group' ? `Group ${m.group_label}` : `Round ${m.round}`,
      court: m.court || '',
      a: m.team_a_name || 'TBD', b: m.team_b_name || 'TBD',
      score: (m.score_a != null && m.score_b != null) ? `${m.score_a} – ${m.score_b}` : '',
      winner: m.winner_name || '',
    }))
}
function downloadBlob(blob, name) {
  const u = URL.createObjectURL(blob); const a = document.createElement('a')
  a.href = u; a.download = name; document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(u), 1000)
}
function exportDrawExcel() {
  const rows = [['Stage', 'Court', 'Team A', 'Team B', 'Score', 'Winner'],
    ...drawRows().map(r => [r.stage, r.court, r.a, r.b, r.score, r.winner])]
  const csv = rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\r\n')
  downloadBlob(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }), `${(tour.value.name || 'tournament')}-draw.csv`)
}
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
function exportDrawPdf() {
  const body = drawRows().map(r => `<tr><td>${esc(r.stage)}</td><td>${esc(r.court)}</td><td class="t">${esc(r.a)}</td><td class="vs">vs</td><td class="t">${esc(r.b)}</td><td>${esc(r.score)}</td><td>${esc(r.winner)}</td></tr>`).join('')
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(tour.value.name)} — Draw</title><style>
    *{box-sizing:border-box}body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a;margin:28px}
    .h{display:flex;align-items:center;gap:12px;border-bottom:3px solid #00b4d8;padding-bottom:12px}
    .logo{width:40px;height:40px;border-radius:10px;background:linear-gradient(135deg,#00b4d8,#a855f7);color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px}
    h1{font-size:20px;margin:0}.sub{color:#64748b;font-size:13px;margin:2px 0 16px}
    table{width:100%;border-collapse:collapse;font-size:13px}th{text-align:left;color:#64748b;font-size:11px;text-transform:uppercase;border-bottom:2px solid #e2e8f0;padding:8px 6px}
    td{padding:9px 6px;border-bottom:1px solid #eef2f7}.t{font-weight:600}.vs{color:#94a3b8;text-align:center}
    .foot{margin-top:20px;color:#94a3b8;font-size:11px}@media print{body{margin:12mm}}
  </style></head><body>
    <div class="h"><div class="logo">🏸</div><h1>${esc(tour.value.name)} — Game Plan</h1></div>
    <div class="sub">${esc(tour.value.club_name || '')} · ${esc(String(tour.value.draw_type || '').replace(/_/g,' '))}</div>
    <table><thead><tr><th>Stage</th><th>Court</th><th>Team A</th><th></th><th>Team B</th><th>Score</th><th>Winner</th></tr></thead><tbody>${body}</tbody></table>
    <div class="foot">Generated by Badminton 360 · badminton360.app</div>
    <script>window.onload=function(){setTimeout(function(){window.print()},250)}<\/script>
  </body></html>`
  const w = window.open('', '_blank'); if (!w) { err.value = 'Allow pop-ups to export the PDF'; return }
  w.document.write(html); w.document.close()
}

function openScoreModal(m) {
  scoreErr.value = ''
  scoreModal.value = { match: m, scoreA: '', scoreB: '' }
}

async function submitScore() {
  scoreErr.value = ''
  const m = scoreModal.value
  if (!m.scoreA || !m.scoreB) { scoreErr.value = 'Enter both scores'; return }
  if (Number(m.scoreA) === Number(m.scoreB)) { scoreErr.value = 'Scores cannot be equal'; return }
  scoreBusy.value = true
  const { error } = await supabase.rpc('record_tournament_result', {
    p_match_id: m.match.id,
    p_score_a:  Number(m.scoreA),
    p_score_b:  Number(m.scoreB),
  })
  scoreBusy.value = false
  if (error) { scoreErr.value = error.message; return }
  scoreModal.value = null
  await load()
}

async function saveSettings() {
  settingsBusy.value = true; settingsOk.value = false; err.value = ''
  const { error } = await supabase.rpc('update_tournament_details', {
    p_tournament_id:   tour.value.id,
    p_name:            settings.value.name || null,
    p_description:     settings.value.description || null,
    p_entry_fee:       settings.value.entry_fee ? Number(settings.value.entry_fee) : null,
    p_prize_info:      settings.value.prize_info || null,
    p_venue:           settings.value.venue || null,
    p_venue_address:   settings.value.venue_address || null,
    p_emirate:         settings.value.emirate || null,
    p_registration_end: settings.value.registration_end || null,
    p_start_date:      settings.value.start_date || null,
    p_end_date:        settings.value.end_date || null,
    p_max_teams:       Number(settings.value.max_teams) || null,
  })
  settingsBusy.value = false
  if (error) { err.value = error.message; return }
  settingsOk.value = true
  await load()
}

const statusFlow = computed(() => {
  const s = tour.value?.status
  const options = []
  if (s === 'draft')                 options.push({ v: 'registration_open', l: '📬 Open Registration' })
  if (s === 'registration_open')     options.push({ v: 'registration_closed', l: '🔒 Close Registration' })
  if (s === 'registration_closed')   options.push({ v: 'registration_open', l: '📬 Re-open Registration' })
  if (!['live','completed','cancelled'].includes(s))
    options.push({ v: 'cancelled', l: '🚫 Cancel' })
  return options
})

const matchStatusClass = s => ({
  completed: 'border-emerald-200 bg-emerald-50',
  bye: 'border-slate-100 bg-slate-50 opacity-60',
  scheduled: 'border-cyan-200/50 bg-white',
}[s] ?? 'border-slate-200 bg-white')

// ── Photos & media (Cloudflare R2 upload, compressed like chat) ──
const photos       = computed(() => data.value?.photos ?? [])
const media        = ref({ cover: '', group: '' })
const photoCaption = ref('')
const photoBusy    = ref(false)
const mediaBusy    = ref('')   // '' | 'cover' | 'group'

async function onPickPhoto(e) {
  const file = e.target.files?.[0]; e.target.value = ''
  if (!file) return
  photoBusy.value = true; err.value = ''
  try {
    const { url, thumbUrl } = await uploadClubImage(file, tour.value.club_id)
    const { error } = await supabase.rpc('add_tournament_photo', {
      p_tournament_id: tour.value.id, p_url: url, p_thumb_url: thumbUrl,
      p_caption: photoCaption.value.trim() || null, p_kind: 'gallery',
    })
    if (error) throw new Error(error.message)
    photoCaption.value = ''
    await load()
  } catch (e2) { err.value = e2.message || 'Upload failed' }
  finally { photoBusy.value = false }
}
async function removePhoto(id) {
  const { error } = await supabase.rpc('delete_tournament_photo', { p_photo_id: id })
  if (error) { err.value = error.message; return }
  await load()
}
async function onPickMedia(e, which) {
  const file = e.target.files?.[0]; e.target.value = ''
  if (!file) return
  mediaBusy.value = which; err.value = ''; ok.value = ''
  try {
    const { url } = await uploadClubImage(file, tour.value.club_id)
    const { error } = await supabase.rpc('set_tournament_media', {
      p_tournament_id: tour.value.id,
      p_cover_url: which === 'cover' ? url : (media.value.cover || null),
      p_group_url: which === 'group' ? url : (media.value.group || null),
    })
    if (error) throw new Error(error.message)
    media.value[which] = url
    ok.value = (which === 'cover' ? 'Cover' : 'Group') + ' photo saved'
    await load()
  } catch (e2) { err.value = e2.message || 'Upload failed' }
  finally { mediaBusy.value = '' }
}

// ── Share images ──
const makingImg = ref('')
async function makeAnnouncement() {
  makingImg.value = 'announce'; try { await document.fonts.ready } catch { /* ignore */ }
  try {
    const url = announcementCard({
      name: tour.value.name, clubName: tour.value.club_name,
      dateLabel: tour.value.start_date || 'Date TBC', venue: tour.value.venue,
      entryFee: tour.value.entry_fee, shareUrl: `https://badminton360.app/t/${tour.value.share_code}`,
      statusText: tour.value.status === 'registration_open' ? 'REGISTRATION OPEN' : 'TOURNAMENT',
    })
    downloadDataUrl(url, `${tour.value.name}-announcement.png`)
  } finally { makingImg.value = '' }
}
async function makeChampionCard() {
  makingImg.value = 'champ'; try { await document.fonts.ready } catch { /* ignore */ }
  const nm = id => registrations.value.find(r => r.id === id)?.team_name
  try {
    const url = championCard({
      name: tour.value.name, clubName: tour.value.club_name, dateLabel: tour.value.start_date || '',
      winner: nm(tour.value.winner_registration_id),
      runnerUp: nm(tour.value.runner_up_registration_id),
      third: nm(tour.value.third_registration_id),
    })
    downloadDataUrl(url, `${tour.value.name}-champions.png`)
  } finally { makingImg.value = '' }
}

// ── Delete tournament ──
const showDeleteModal   = ref(false)
const deleteConfirmText = ref('')
const deletingTour      = ref(false)

async function deleteTournament() {
  deletingTour.value = true
  const { error } = await supabase.rpc('delete_tournament', {
    p_tournament_id: tour.value.id
  })
  deletingTour.value = false
  if (error) { err.value = error.message; showDeleteModal.value = false; return }
  router.push('/tournaments')
}
</script>

<template>
  <div>
    <!-- Back -->
    <button class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4"
      @click="router.push('/tournament/' + route.params.id)">
      ← Back to Tournament
    </button>

    <div v-if="loading" class="space-y-3">
      <div class="h-24 shimmer rounded-2xl" />
      <div class="h-48 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!data" class="card p-8 text-center text-slate-500">
      Tournament not found or access denied.
    </div>

    <template v-else>
      <!-- Header -->
      <div class="mb-4">
        <h1 class="font-display text-xl font-bold gradient-text">{{ tour.name }}</h1>
        <p class="text-xs text-slate-400 mt-0.5">Tournament Director Panel</p>
      </div>

      <!-- Alerts -->
      <div v-if="err" class="rounded-xl px-4 py-3 mb-3 text-sm text-rose-600 bg-rose-50 border border-rose-200">
        ⚠️ {{ err }}
      </div>
      <div v-if="ok" class="rounded-xl px-4 py-3 mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200">
        ✅ {{ ok }}
      </div>

      <!-- Status card -->
      <div class="card p-4 mb-4">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <div>
            <p class="text-xs text-slate-400">Status</p>
            <p class="font-bold text-slate-800 capitalize mt-0.5">{{ tour.status.replace(/_/g,' ') }}</p>
          </div>
          <div class="flex gap-2 flex-wrap">
            <button v-for="opt in statusFlow" :key="opt.v"
              class="btn-ghost text-xs px-3 py-1.5"
              :disabled="busy === 'status'"
              @click="setStatus(opt.v)">
              {{ busy === 'status' ? '…' : opt.l }}
            </button>
          </div>
        </div>

        <!-- Generate bracket button (shown when closed or draft and has teams) -->
        <div v-if="['draft','registration_open','registration_closed'].includes(tour.status) && confirmed.length >= 2"
          class="mt-3 pt-3 border-t border-slate-100">
          <p class="text-xs text-slate-500 mb-2">
            {{ confirmed.length }} confirmed team{{ confirmed.length > 1 ? 's' : '' }}.
            Ready to generate bracket.
          </p>
          <button class="btn-primary w-full py-2.5 text-sm"
            :disabled="busy === 'bracket'"
            @click="generateBracket">
            {{ busy === 'bracket' ? '⏳ Generating…' : '🎯 Generate Bracket & Go Live' }}
          </button>
        </div>
      </div>

      <!-- Results + share images -->
      <div v-if="tour.status === 'completed' && tour.winner_registration_id" class="card card-amber p-4 mb-4">
        <p class="text-xs font-bold text-slate-600 mb-2">🏆 Final results</p>
        <div class="space-y-1 text-sm">
          <p class="font-bold text-slate-800">🥇 {{ tour.winner_team_name || registrations.find(r => r.id === tour.winner_registration_id)?.team_name }}</p>
        </div>
        <button class="btn-primary w-full mt-3 py-2 text-sm" :disabled="makingImg" @click="makeChampionCard">
          {{ makingImg === 'champ' ? '…' : '🏆 Download champion card' }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2 mb-4">
        <button class="btn-ghost text-xs px-3 py-1.5" :disabled="makingImg" @click="makeAnnouncement">
          {{ makingImg === 'announce' ? '…' : '📣 Announcement image' }}
        </button>
        <a class="btn-ghost text-xs px-3 py-1.5" :href="'/t/' + tour.share_code" target="_blank" rel="noopener">🔗 Public page ↗</a>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 mb-4 border border-slate-200 rounded-2xl p-1 bg-white">
        <button v-for="t in [{v:'registrations',l:'Teams'},{v:'bracket',l:'Bracket'},{v:'settings',l:'Settings'}]"
          :key="t.v"
          class="flex-1 py-2 text-xs font-semibold rounded-xl transition-all relative"
          :class="tab === t.v ? 'bg-cyan-600 text-white shadow-sm' : 'text-slate-500 hover:text-slate-700'"
          @click="tab = t.v">
          {{ t.l }}
          <span v-if="t.v === 'registrations' && pending.length"
            class="absolute -top-1 -right-1 badge-dot text-[8px]">
            {{ pending.length }}
          </span>
        </button>
      </div>

      <!-- ── REGISTRATIONS TAB ── -->
      <div v-if="tab === 'registrations'" class="space-y-4 fade-up">

        <!-- Pending -->
        <div v-if="pending.length">
          <h3 class="label mb-2">Pending Approval ({{ pending.length }})</h3>
          <div class="space-y-2">
            <div v-for="r in pending" :key="r.id" class="card p-4">
              <div class="flex items-start justify-between gap-2">
                <div class="flex-1 min-w-0">
                  <p class="font-semibold text-slate-800">{{ r.team_name }}</p>
                  <p class="text-xs text-slate-500 mt-0.5">
                    {{ r.player_a_name }}<span v-if="r.player_b_name"> · {{ r.player_b_name }}</span>
                  </p>
                  <p v-if="r.contact_phone" class="text-xs text-slate-500 mt-1">
                    📞 <a :href="'tel:' + r.contact_phone" class="text-neon">{{ r.contact_phone }}</a>
                  </p>
                  <p v-if="r.notes" class="text-xs text-slate-400 mt-1 italic">{{ r.notes }}</p>
                  <span class="inline-block mt-1.5 text-[10px] font-bold uppercase tracking-wide rounded px-1.5 py-0.5"
                    :class="r.payment_status === 'confirmed' ? 'text-emerald-600 bg-emerald-50' : 'text-amber-600 bg-amber-50'">
                    {{ r.payment_status === 'confirmed' ? 'Paid' : 'Payment pending' }}
                  </span>
                </div>
                <div class="flex gap-2 shrink-0">
                  <button class="btn-success text-xs px-3 py-1.5"
                    :disabled="busy === 'reg-' + r.id"
                    @click="approve(r.id)">✓ Approve</button>
                  <button class="btn-danger text-xs px-3 py-1.5"
                    :disabled="busy === 'reg-' + r.id"
                    @click="reject(r.id)">✗</button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Confirmed -->
        <div v-if="confirmed.length">
          <h3 class="label mb-2">Confirmed Teams ({{ confirmed.length }})</h3>
          <div class="card overflow-hidden">
            <div v-for="(r, i) in confirmed" :key="r.id"
              class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
              <!-- Seed input -->
              <input type="number" min="1" :max="confirmed.length"
                :value="r.seed ?? (i+1)"
                class="w-10 text-center rounded-lg border border-slate-200 py-1 text-xs font-bold"
                @change="setSeed(r.id, $event.target.value)" />
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-slate-800 text-sm truncate">{{ r.team_name }}</p>
                <p class="text-xs text-slate-400">
                  {{ r.player_a_name }}<span v-if="r.player_b_name"> · {{ r.player_b_name }}</span>
                </p>
              </div>
              <span class="badge-approved">confirmed</span>
            </div>
          </div>
          <p class="text-xs text-slate-400 mt-2 text-center">
            Seed numbers are used for bracket seeding. Edit inline.
          </p>
        </div>

        <div v-if="!registrations.length" class="card p-8 text-center text-slate-400 text-sm">
          No registrations yet. Share the tournament link to get sign-ups.
        </div>
      </div>

      <!-- ── BRACKET TAB ── -->
      <div v-if="tab === 'bracket'" class="fade-up">
        <!-- Export + regenerate the game plan -->
        <div v-if="matches.length" class="flex flex-wrap items-center gap-2 mb-3">
          <span class="text-xs font-semibold text-slate-500 mr-auto">Game plan</span>
          <button class="btn-ghost text-xs px-3 py-1.5" @click="exportDrawPdf">📄 PDF</button>
          <button class="btn-ghost text-xs px-3 py-1.5" @click="exportDrawExcel">📊 Excel</button>
          <button v-if="tour.status !== 'completed'" class="btn-ghost text-xs px-3 py-1.5" :disabled="busy === 'bracket'" @click="generateBracket">
            {{ busy === 'bracket' ? '…' : '↻ Regenerate' }}
          </button>
        </div>

        <div v-if="!matches.length" class="card p-8 text-center text-sm text-slate-500">
          <p class="mb-4">Bracket not generated yet.</p>
          <p v-if="confirmed.length < 2" class="text-amber-600">
            Need at least 2 confirmed teams to generate.
          </p>
          <button v-else-if="['draft','registration_open','registration_closed'].includes(tour.status)"
            class="btn-primary px-6" :disabled="busy === 'bracket'"
            @click="generateBracket">
            {{ busy === 'bracket' ? '⏳ Generating…' : '🎯 Generate Bracket' }}
          </button>
        </div>

        <!-- Round-robin / group-stage list with score entry -->
        <div v-else-if="tour.draw_type === 'round_robin' || tour.draw_type === 'groups_knockout'" class="space-y-4">

          <!-- Group standings (groups_knockout) -->
          <div v-if="isGroups && groupStandings.length" class="space-y-3">
            <div v-for="g in groupStandings" :key="'st-' + g.label" class="card p-3">
              <div class="text-[11px] font-bold uppercase tracking-wide text-slate-500 mb-2">Group {{ g.label }} · Standings</div>
              <div class="space-y-1">
                <div v-for="(t, i) in g.teams" :key="t.id"
                  class="flex items-center gap-2 text-xs"
                  :class="i < (tour.advance_per_group || 2) ? 'text-slate-800 font-semibold' : 'text-slate-400'">
                  <span class="w-4 text-center">{{ i + 1 }}</span>
                  <span v-if="i < (tour.advance_per_group || 2)" class="text-emerald-500">▲</span>
                  <span v-else class="w-3" />
                  <span class="flex-1 min-w-0 truncate">{{ t.name }}</span>
                  <span class="tabular-nums">{{ t.wins }}W–{{ t.losses }}L</span>
                  <span class="tabular-nums text-slate-400 w-10 text-right">{{ t.setDiff >= 0 ? '+' : '' }}{{ t.setDiff }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Generate knockout when groups are done -->
          <div v-if="isGroups && groupStageDone && !knockoutExists" class="card card-violet p-4 text-center">
            <p class="text-sm font-semibold text-slate-700 mb-1">Group stage complete 🎉</p>
            <p class="text-xs text-slate-500 mb-3">Top {{ tour.advance_per_group || 2 }} of each group advance.</p>
            <button class="btn-primary w-full py-2.5 text-sm" :disabled="busy === 'knockout'" @click="generateKnockout">
              {{ busy === 'knockout' ? '⏳ Generating…' : '🏆 Generate Knockout Bracket' }}
            </button>
          </div>

          <!-- Match sections -->
          <div v-for="sec in flatSections" :key="sec.key" class="space-y-2">
            <h3 v-if="sec.title" class="label">{{ sec.title }}</h3>
            <div v-for="m in sec.matches" :key="m.id"
              class="card p-3 border transition"
              :class="m.status === 'completed' ? 'border-emerald-200 bg-emerald-50' : 'border-cyan-200/40'">
              <div class="text-[10px] uppercase tracking-wide text-slate-400 mb-1">
                {{ m.stage === 'group' ? 'Group ' + m.group_label : 'Round ' + m.round }}<span v-if="m.court"> · Court {{ m.court }}</span>
              </div>
              <div class="flex items-center gap-3">
                <div class="flex-1 min-w-0 text-xs font-semibold text-slate-700 truncate">
                  {{ m.team_a_name ?? 'TBD' }}
                </div>
                <div class="shrink-0 flex items-center gap-2 font-extrabold text-sm">
                  <span :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-400'">
                    {{ m.score_a ?? '—' }}
                  </span>
                  <span class="text-slate-300 font-normal text-xs">vs</span>
                  <span :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-400'">
                    {{ m.score_b ?? '—' }}
                  </span>
                </div>
                <div class="flex-1 min-w-0 text-right text-xs font-semibold text-slate-700 truncate">
                  {{ m.team_b_name ?? 'TBD' }}
                </div>
                <button v-if="m.team_a_id && m.team_b_id && m.status !== 'completed' && m.status !== 'bye'"
                  class="shrink-0 btn-ghost text-xs px-2 py-1"
                  @click="openScoreModal(m)">
                  Score
                </button>
                <span v-else-if="m.status === 'completed'"
                  class="shrink-0 text-[10px] text-emerald-600 font-bold">Done</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Single elimination bracket with score entry -->
        <div v-else>
          <div v-for="rd in rounds" :key="rd.round" class="mb-6">
            <h3 class="label mb-2">{{ roundLabel(rd.round, totalRounds) }}</h3>
            <div class="space-y-2">
              <div v-for="m in rd.matches" :key="m.id"
                class="card border p-3 transition"
                :class="matchStatusClass(m.status)">

                <div v-if="m.status === 'bye'" class="text-xs text-slate-400 italic text-center py-1">
                  BYE — auto advance
                </div>
                <template v-else>
                  <div class="flex items-center gap-3">
                    <!-- Team A -->
                    <div class="flex-1 min-w-0">
                      <p class="text-xs font-semibold truncate"
                        :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-700'">
                        {{ m.team_a_name ?? 'TBD' }}
                        <span v-if="m.winner_id === m.team_a_id" class="ml-1">🏆</span>
                      </p>
                    </div>
                    <!-- Scores -->
                    <div class="shrink-0 flex items-center gap-2 font-bold text-sm">
                      <span :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-400'">
                        {{ m.score_a ?? '—' }}
                      </span>
                      <span class="text-slate-300 text-xs font-normal">vs</span>
                      <span :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-400'">
                        {{ m.score_b ?? '—' }}
                      </span>
                    </div>
                    <!-- Team B -->
                    <div class="flex-1 min-w-0 text-right">
                      <p class="text-xs font-semibold truncate"
                        :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-700'">
                        <span v-if="m.winner_id === m.team_b_id" class="mr-1">🏆</span>
                        {{ m.team_b_name ?? 'TBD' }}
                      </p>
                    </div>
                    <!-- Score button -->
                    <button v-if="m.status === 'scheduled' && m.team_a_id && m.team_b_id"
                      class="shrink-0 btn-ghost text-xs px-2 py-1"
                      @click="openScoreModal(m)">
                      Score
                    </button>
                  </div>
                </template>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── SETTINGS TAB ── -->
      <div v-if="tab === 'settings'" class="fade-up space-y-4">
        <div class="card p-4 space-y-4">
          <div>
            <label class="label">Name</label>
            <input v-model="settings.name" class="input" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Max Teams</label>
              <select v-model="settings.max_teams" class="input">
                <option v-for="n in [4,8,12,16,24,32]" :key="n" :value="n">{{ n }}</option>
              </select>
            </div>
            <div>
              <label class="label">Emirate</label>
              <select v-model="settings.emirate" class="input">
                <option value="">— Any —</option>
                <option v-for="e in emirates" :key="e" :value="e">{{ e }}</option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Entry Fee (AED)</label>
              <input v-model="settings.entry_fee" type="number" min="0" class="input" />
            </div>
            <div>
              <label class="label">Reg. Closes</label>
              <DateField v-model="settings.registration_end" />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Start Date</label>
              <DateField v-model="settings.start_date" />
            </div>
            <div>
              <label class="label">End Date</label>
              <DateField v-model="settings.end_date" />
            </div>
          </div>
          <div>
            <label class="label">Venue</label>
            <input v-model="settings.venue" class="input" placeholder="Venue name" />
          </div>
          <div>
            <label class="label">Venue Address</label>
            <input v-model="settings.venue_address" class="input" placeholder="Full address" />
          </div>
          <div>
            <label class="label">Prize Info</label>
            <input v-model="settings.prize_info" class="input" placeholder="1st: AED 500…" />
          </div>
          <div>
            <label class="label">Description</label>
            <textarea v-model="settings.description" class="input resize-none" rows="3" />
          </div>
        </div>

        <p v-if="err" class="text-rose-500 text-sm">{{ err }}</p>
        <p v-if="settingsOk" class="text-emerald-600 text-sm">✅ Saved</p>
        <button class="btn-primary w-full" :disabled="settingsBusy" @click="saveSettings">
          {{ settingsBusy ? 'Saving…' : 'Save Changes' }}
        </button>

        <!-- Photos & media (uploaded to Cloudflare R2, compressed) -->
        <div class="card p-4 space-y-4">
          <p class="text-xs font-bold text-slate-600">📸 Photos & Media</p>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Cover image</label>
              <div class="aspect-video rounded-xl bg-slate-100 overflow-hidden mb-2 flex items-center justify-center">
                <img v-if="media.cover" :src="media.cover" alt="Cover" class="w-full h-full object-cover" />
                <span v-else class="text-2xl text-slate-300">🖼️</span>
              </div>
              <label class="btn-ghost w-full text-xs text-center cursor-pointer block">
                {{ mediaBusy === 'cover' ? 'Uploading…' : (media.cover ? 'Replace' : 'Upload') }}
                <input type="file" accept="image/*" class="hidden" :disabled="mediaBusy === 'cover'" @change="e => onPickMedia(e, 'cover')" />
              </label>
            </div>
            <div>
              <label class="label">Group photo</label>
              <div class="aspect-video rounded-xl bg-slate-100 overflow-hidden mb-2 flex items-center justify-center">
                <img v-if="media.group" :src="media.group" alt="Group" class="w-full h-full object-cover" />
                <span v-else class="text-2xl text-slate-300">👥</span>
              </div>
              <label class="btn-ghost w-full text-xs text-center cursor-pointer block">
                {{ mediaBusy === 'group' ? 'Uploading…' : (media.group ? 'Replace' : 'Upload') }}
                <input type="file" accept="image/*" class="hidden" :disabled="mediaBusy === 'group'" @change="e => onPickMedia(e, 'group')" />
              </label>
            </div>
          </div>

          <div class="border-t border-slate-100 pt-3">
            <label class="label">Gallery photos</label>
            <input v-model="photoCaption" class="input mb-2" placeholder="Caption for the next photo (optional)" />
            <label class="btn-primary w-full text-sm text-center cursor-pointer block">
              {{ photoBusy ? '⏳ Uploading…' : '＋ Add photo' }}
              <input type="file" accept="image/*" class="hidden" :disabled="photoBusy" @change="onPickPhoto" />
            </label>
            <p class="text-[10px] text-slate-400 mt-1">Photos are compressed automatically before upload.</p>
          </div>

          <div v-if="photos.length" class="grid grid-cols-3 gap-2">
            <div v-for="p in photos" :key="p.id" class="relative aspect-square rounded-lg overflow-hidden bg-slate-100">
              <img :src="p.thumb_url || p.url" :alt="p.caption || ''" class="w-full h-full object-cover" loading="lazy" />
              <button class="absolute top-1 right-1 w-6 h-6 rounded-full bg-black/60 text-white text-xs flex items-center justify-center"
                @click="removePhoto(p.id)">✕</button>
            </div>
          </div>
        </div>

        <!-- Danger zone -->
        <div class="border-t border-red-100 pt-4 mt-2">
          <p class="text-[10px] uppercase tracking-widest text-rose-400 font-bold mb-2">Danger Zone</p>
          <button class="w-full rounded-xl border border-rose-200 text-rose-500 text-sm py-2.5
                         hover:bg-rose-50 hover:border-rose-300 transition"
            @click="deleteConfirmText = ''; showDeleteModal = true">
            🗑 Delete Tournament
          </button>
        </div>
      </div>
    </template>
  </div>

  <!-- ── Delete Tournament Modal ── -->
  <Teleport to="body">
    <div v-if="showDeleteModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.6); backdrop-filter:blur(4px)"
      @click.self="showDeleteModal = false">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc; border:1px solid rgba(239,68,68,.3)">

        <div class="flex items-center gap-3 mb-4">
          <div class="w-10 h-10 rounded-2xl flex items-center justify-center text-xl shrink-0"
            style="background:rgba(239,68,68,.1); border:1px solid rgba(239,68,68,.2)">🗑</div>
          <div>
            <h3 class="font-display font-bold text-slate-800">Delete Tournament</h3>
            <p class="text-xs text-rose-500">This cannot be undone</p>
          </div>
          <button class="ml-auto text-slate-400 hover:text-slate-700 text-xl"
            @click="showDeleteModal = false">✕</button>
        </div>

        <div class="rounded-xl px-4 py-3 mb-4 text-sm space-y-1"
          style="background:rgba(239,68,68,.06); border:1px solid rgba(239,68,68,.15)">
          <p class="font-semibold text-slate-700">{{ tour.name }}</p>
          <p class="text-xs text-slate-500">All registrations and match results will be permanently deleted.</p>
        </div>

        <label class="text-xs text-slate-500 block mb-1">
          Type <strong class="text-slate-700">{{ tour.name }}</strong> to confirm
        </label>
        <input v-model="deleteConfirmText" class="input mb-4"
          :placeholder="tour.name" @keyup.enter="deleteConfirmText === tour.name && deleteTournament()" />

        <div class="flex gap-3">
          <button class="btn-ghost flex-1" @click="showDeleteModal = false">Cancel</button>
          <button class="flex-1 rounded-xl py-2.5 text-sm font-semibold transition-all"
            :class="deleteConfirmText === tour.name && !deletingTour
              ? 'bg-rose-600 hover:bg-rose-500 text-white'
              : 'bg-rose-100 text-rose-300 cursor-not-allowed'"
            :disabled="deleteConfirmText !== tour.name || deletingTour"
            @click="deleteTournament">
            {{ deletingTour ? 'Deleting…' : '🗑 Delete Permanently' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- ── Score Modal ── -->
  <Teleport to="body">
    <div v-if="scoreModal"
      class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.6); backdrop-filter:blur(4px)"
      @click.self="scoreModal = null">
      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#f8fafc; border:1px solid rgba(0,168,204,.25)">

        <h3 class="font-display font-bold text-slate-800 text-lg mb-1">Record Result</h3>
        <p class="text-xs text-slate-500 mb-5">
          {{ scoreModal.match.team_a_name ?? 'Team A' }} vs {{ scoreModal.match.team_b_name ?? 'Team B' }}
        </p>

        <div class="grid grid-cols-2 gap-4 mb-4">
          <div>
            <label class="label">{{ scoreModal.match.team_a_name ?? 'Team A' }}</label>
            <input v-model="scoreModal.scoreA" type="number" min="0" class="input text-center text-xl font-bold"
              placeholder="0" />
          </div>
          <div>
            <label class="label">{{ scoreModal.match.team_b_name ?? 'Team B' }}</label>
            <input v-model="scoreModal.scoreB" type="number" min="0" class="input text-center text-xl font-bold"
              placeholder="0" />
          </div>
        </div>

        <p v-if="scoreErr" class="text-rose-500 text-sm mb-3">{{ scoreErr }}</p>

        <div class="flex gap-3">
          <button class="btn-ghost flex-1" @click="scoreModal = null">Cancel</button>
          <button class="btn-primary flex-1" :disabled="scoreBusy" @click="submitScore">
            {{ scoreBusy ? 'Saving…' : 'Save Result' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
