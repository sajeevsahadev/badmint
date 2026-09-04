<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { applySeo, setJsonLd, SEO_BASE } from '../lib/seo'
import { computeGroupStandings } from '../utils/tournament-draw'
import { championCard, announcementCard, downloadDataUrl } from '../utils/tournament-share'

const route = useRoute()
const data   = ref(null)
const loading = ref(true)
const notFound = ref(false)
const copied = ref(false)

const t     = computed(() => data.value?.tournament ?? null)
const teams = computed(() => data.value?.teams ?? [])
const matches   = computed(() => data.value?.matches ?? [])
const standings = computed(() => data.value?.standings ?? [])
const photos    = computed(() => data.value?.photos ?? [])
const isGroups     = computed(() => t.value?.draw_type === 'groups_knockout')
const isRoundRobin = computed(() => t.value?.draw_type === 'round_robin')

const byPos = (a, b) => a.position - b.position
const roundName = (r, total) => {
  const fromEnd = total - r
  if (fromEnd === 0) return 'Final'
  if (fromEnd === 1) return 'Semi-finals'
  if (fromEnd === 2) return 'Quarter-finals'
  return 'Round ' + r
}
const groupStandings = computed(() =>
  computeGroupStandings(matches.value).map(g => ({
    ...g, teams: g.teams.map(x => ({ ...x, name: teamName(x.id) })),
  })))
const matchSections = computed(() => {
  const ms = matches.value.filter(m => m.status !== 'bye')
  if (!ms.length) return []
  const rounds = (list) => {
    const total = Math.max(...list.map(m => m.round))
    const byR = {}
    list.forEach(m => { (byR[m.round] ||= []).push(m) })
    return Object.keys(byR).sort((a, b) => a - b)
      .map(r => ({ title: roundName(+r, total), matches: byR[r].slice().sort(byPos) }))
  }
  if (isRoundRobin.value) return [{ title: 'Matches', matches: ms.slice().sort((a, b) => a.round - b.round || byPos(a, b)) }]
  if (isGroups.value) {
    const secs = groupStandings.value.map(g => ({
      title: 'Group ' + g.label,
      matches: ms.filter(m => m.stage === 'group' && m.group_label === g.label).sort((a, b) => a.round - b.round || byPos(a, b)),
    })).filter(s => s.matches.length)
    const ko = ms.filter(m => m.stage && m.stage !== 'group')
    if (ko.length) secs.push(...rounds(ko))
    return secs
  }
  return rounds(ms)
})
const hasResults = computed(() => matches.value.some(m => m.status === 'completed'))

const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }) : null
const dateLabel = computed(() => {
  if (!t.value) return ''
  const s = fmtDate(t.value.start_date), e = fmtDate(t.value.end_date)
  return s && e && e !== s ? `${s} – ${e}` : (s || 'Date TBC')
})
const statusLabel = computed(() => ({
  draft: 'Draft', registration_open: 'Registration open', live: 'Live now', completed: 'Completed',
}[t.value?.status] || t.value?.status))
const statusClass = computed(() => ({
  registration_open: 'bg-emerald-50 text-emerald-600 border-emerald-200',
  live: 'bg-rose-50 text-rose-600 border-rose-200',
  completed: 'bg-slate-100 text-slate-500 border-slate-200',
}[t.value?.status] || 'bg-slate-100 text-slate-500 border-slate-200'))

const shareUrl = computed(() => t.value ? `${SEO_BASE}/t/${t.value.share_code}` : SEO_BASE)
const teamName = id => teams.value.find(x => x.id === id)?.team_name

// This page serves both /t/:code (share link) and /tournament/:id (in-app);
// get_public_tournament resolves either a share_code or a raw id.
const routeKey = () => route.params.code || route.params.id

async function load(silent = false) {
  if (!silent) { loading.value = true; notFound.value = false }
  const { data: res } = await supabase.rpc('get_public_tournament', { p_code: routeKey() })
  if (!silent) loading.value = false
  if (!res) { if (!silent) notFound.value = true; return }
  data.value = res
  applySeo({
    title: `${t.value.name} — ${t.value.club_name} | Badminton 360`,
    description: `${t.value.name}, a badminton doubles tournament by ${t.value.club_name}${t.value.venue ? ' at ' + t.value.venue : ''}${dateLabel.value ? ' · ' + dateLabel.value : ''}. Teams, draw, live results and winners.`,
    image: t.value.cover_photo_url || undefined,
    path: `/t/${t.value.share_code}`,
    type: 'article',
  })
  setJsonLd('ld-tournament', {
    '@context': 'https://schema.org', '@type': 'SportsEvent',
    name: t.value.name, sport: 'Badminton',
    startDate: t.value.start_date || undefined, endDate: t.value.end_date || undefined,
    eventStatus: t.value.status === 'completed' ? 'https://schema.org/EventScheduled' : 'https://schema.org/EventScheduled',
    location: t.value.venue ? { '@type': 'Place', name: t.value.venue, address: t.value.venue_address || undefined } : undefined,
    organizer: { '@type': 'Organization', name: t.value.club_name },
    url: shareUrl.value,
  })
}
// Live: while the tournament is live, silently refresh so followers see scores
// update without a manual reload. Pauses when the tab is hidden.
let pollTimer = null
function tick() {
  if (document.visibilityState === 'visible' && t.value?.status === 'live') load(true)
}
onMounted(() => { load(); pollTimer = setInterval(tick, 12000) })
onUnmounted(() => clearInterval(pollTimer))
watch(() => routeKey(), () => load())

const canManage      = computed(() => !!data.value?.can_manage)
const myRegistration = computed(() => data.value?.my_registration ?? null)
const regOpen = computed(() => {
  if (t.value?.status !== 'registration_open') return false
  if (t.value.registration_end && t.value.registration_end < new Date().toISOString().slice(0, 10)) return false
  return true
})
const withdrawing = ref(false)
async function withdrawTeam() {
  if (!myRegistration.value || withdrawing.value) return
  if (!confirm('Withdraw your team from this tournament?')) return
  withdrawing.value = true
  const { error } = await supabase.rpc('withdraw_registration', { p_reg_id: myRegistration.value.id })
  withdrawing.value = false
  if (!error) load()
}

async function copyLink() {
  try { await navigator.clipboard.writeText(shareUrl.value); copied.value = true; setTimeout(() => copied.value = false, 1800) } catch { /* ignore */ }
}
const waShare = computed(() =>
  `https://wa.me/?text=${encodeURIComponent(`🏸 ${t.value?.name} — ${t.value?.club_name}\n${dateLabel.value}\nFollow the tournament: ${shareUrl.value}`)}`)

// ── Shareable images (Phase 4) ──
const makingImg = ref('')
async function ensureFonts() { try { await document.fonts.ready } catch { /* ignore */ } }
async function shareChampionCard() {
  makingImg.value = 'champ'; await ensureFonts()
  try {
    const url = championCard({
      name: t.value.name, clubName: t.value.club_name, dateLabel: dateLabel.value,
      winner: teamName(t.value.winner_registration_id),
      runnerUp: teamName(t.value.runner_up_registration_id),
      third: teamName(t.value.third_registration_id),
    })
    downloadDataUrl(url, `${t.value.name}-champions.png`)
  } finally { makingImg.value = '' }
}
const announceStatus = computed(() => ({
  registration_open: 'REGISTRATION OPEN', live: 'LIVE NOW', completed: 'CHAMPIONS CROWNED',
}[t.value?.status] || 'TOURNAMENT'))
async function shareAnnouncement() {
  makingImg.value = 'announce'; await ensureFonts()
  try {
    const url = announcementCard({
      name: t.value.name, clubName: t.value.club_name, dateLabel: dateLabel.value,
      venue: t.value.venue, entryFee: t.value.entry_fee ? `${t.value.currency} ${t.value.entry_fee}` : null, shareUrl: shareUrl.value,
      statusText: announceStatus.value,
    })
    downloadDataUrl(url, `${t.value.name}-announcement.png`)
  } finally { makingImg.value = '' }
}

const lightbox = ref(null)
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff">
    <div v-if="loading" class="max-w-3xl mx-auto px-4 py-10 space-y-3">
      <div class="h-40 shimmer rounded-2xl" /><div class="h-24 shimmer rounded-2xl" /><div class="h-40 shimmer rounded-2xl" />
    </div>

    <div v-else-if="notFound" class="max-w-md mx-auto px-4 py-20 text-center">
      <div class="text-4xl mb-3">🏸</div>
      <p class="font-bold text-slate-700 mb-1">Tournament not found</p>
      <p class="text-sm text-slate-400 mb-5">This link may be wrong or the tournament was removed.</p>
      <RouterLink to="/" class="btn-primary inline-flex px-5 py-2.5">Badminton 360 →</RouterLink>
    </div>

    <template v-else>
      <!-- Hero -->
      <header class="relative overflow-hidden text-white"
        style="background:linear-gradient(135deg,#0b1220 0%,#0f2a4a 55%,#0a5b74 100%)">
        <div class="absolute inset-0 opacity-20" aria-hidden="true"
          style="background-image:radial-gradient(circle at 20% 30%,#22d3ee55,transparent 40%),radial-gradient(circle at 80% 20%,#a855f755,transparent 40%)"></div>

        <!-- Badminton rally illustration -->
        <svg class="pointer-events-none absolute right-0 bottom-0 h-full w-auto opacity-50 sm:opacity-70"
          viewBox="0 0 420 280" fill="none" aria-hidden="true" preserveAspectRatio="xMaxYMax meet">
          <defs>
            <linearGradient id="tpPlayer" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#67e8f9" /><stop offset="1" stop-color="#c084fc" />
            </linearGradient>
          </defs>
          <!-- court net -->
          <path d="M210 250 L210 120" stroke="#ffffff" stroke-width="2" opacity="0.12" />
          <path d="M188 250 L232 250" stroke="#ffffff" stroke-width="2" opacity="0.12" />
          <!-- shuttle flight arc -->
          <path d="M120 150 Q245 20 345 60" stroke="#fde68a" stroke-width="2" stroke-dasharray="3 9"
            stroke-linecap="round" opacity="0.7" />
          <circle cx="150" cy="118" r="2" fill="#fde68a" opacity="0.5" />
          <circle cx="205" cy="70" r="2" fill="#fde68a" opacity="0.6" />
          <circle cx="270" cy="52" r="2" fill="#fde68a" opacity="0.7" />

          <!-- shuttlecock near the smasher -->
          <g transform="translate(338 44) rotate(35)">
            <path d="M0 0 L-7 -16 M0 0 L-2 -17 M0 0 L3 -17 M0 0 L8 -15" stroke="#fef3c7" stroke-width="2" stroke-linecap="round" />
            <circle cx="0" cy="2" r="4.5" fill="#fef9c3" />
          </g>

          <!-- Player A — ready/defence (left) -->
          <g stroke="url(#tpPlayer)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" fill="none">
            <circle cx="120" cy="112" r="11" fill="url(#tpPlayer)" stroke="none" />
            <path d="M120 124 L128 172" />
            <path d="M124 138 L100 146 L82 150" />       <!-- racket arm -->
            <path d="M124 138 L142 152" />
            <path d="M128 172 L110 206 L100 230" />       <!-- back leg -->
            <path d="M128 172 L152 202 L162 228" />       <!-- front leg -->
            <ellipse cx="74" cy="150" rx="12" ry="8" transform="rotate(-28 74 150)" stroke-width="4" />
          </g>

          <!-- Player B — jump smash (right) -->
          <g stroke="url(#tpPlayer)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" fill="none">
            <circle cx="300" cy="78" r="12" fill="url(#tpPlayer)" stroke="none" />
            <path d="M300 90 L296 150" />
            <path d="M300 104 L322 82 L338 58" />         <!-- raised racket arm -->
            <path d="M300 108 L282 128" />
            <path d="M296 150 L282 188 L276 214" />        <!-- landing leg -->
            <path d="M296 150 L318 172 L330 156" />        <!-- tucked leg -->
            <ellipse cx="343" cy="49" rx="13" ry="9" transform="rotate(38 343 49)" stroke-width="4" />
          </g>
        </svg>

        <div class="relative max-w-3xl mx-auto px-5 sm:px-8 pt-16 sm:pt-9 pb-9 safe-area-pt">
          <div class="flex items-center gap-2 mb-3 text-white/70 text-xs">
            <span class="inline-flex items-center rounded-full border px-2.5 py-0.5 font-semibold" :class="statusClass">{{ statusLabel }}</span>
            <span>🏆 Doubles Tournament</span>
          </div>
          <h1 class="font-display text-3xl sm:text-4xl font-extrabold leading-tight">{{ t.name }}</h1>
          <p class="text-white/80 mt-2 font-medium">{{ t.club_name }}</p>
          <div class="flex flex-wrap gap-x-5 gap-y-1 mt-3 text-sm text-white/70">
            <span>📅 {{ dateLabel }}</span>
            <span v-if="t.venue">📍 {{ t.venue }}</span>
            <a v-if="t.maps_url" :href="t.maps_url" target="_blank" rel="noopener" class="text-cyan-300 hover:underline">Open in Maps ↗</a>
          </div>
        </div>
      </header>

      <main class="max-w-3xl mx-auto px-4 sm:px-8 py-6 space-y-4">
        <!-- Share -->
        <div class="card p-4 flex flex-wrap items-center gap-2">
          <span class="text-xs font-semibold text-slate-500 mr-auto">Share this tournament</span>
          <a :href="waShare" target="_blank" rel="noopener" class="btn-ghost text-xs px-3 py-1.5">🟢 WhatsApp</a>
          <button class="btn-ghost text-xs px-3 py-1.5" @click="copyLink">{{ copied ? '✓ Copied' : '🔗 Copy link' }}</button>
          <button class="btn-ghost text-xs px-3 py-1.5" :disabled="makingImg" @click="shareAnnouncement">
            {{ makingImg === 'announce' ? '…' : '📣 Poster' }}
          </button>
          <button v-if="t.status === 'completed' && t.winner_registration_id"
            class="btn-ghost text-xs px-3 py-1.5" :disabled="makingImg" @click="shareChampionCard">
            {{ makingImg === 'champ' ? '…' : '🏆 Champion card' }}
          </button>
        </div>

        <!-- Director manage bar -->
        <RouterLink v-if="canManage" :to="`/tournament/${t.id}/manage`"
          class="card card-violet p-4 flex items-center gap-3 no-underline hover:shadow-lg transition-all active:scale-[0.99]">
          <div class="text-2xl shrink-0">⚙️</div>
          <div class="flex-1 min-w-0">
            <p class="font-display font-bold text-violet">Manage tournament</p>
            <p class="text-xs text-slate-500 mt-0.5">Approvals, draw, live scores & results</p>
          </div>
          <span class="text-violet text-sm shrink-0">→</span>
        </RouterLink>

        <!-- My registration status -->
        <div v-if="myRegistration" class="card p-4">
          <div class="flex items-center gap-3">
            <div class="text-2xl shrink-0">📝</div>
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-slate-800 text-sm truncate">Your team: {{ myRegistration.team_name }}</p>
              <p class="text-xs mt-0.5"
                :class="myRegistration.status === 'confirmed' ? 'text-emerald-600' : 'text-amber-600'">
                {{ myRegistration.status === 'confirmed' ? '✓ Confirmed' : '⏳ Awaiting approval' }}
                <span v-if="myRegistration.payment_status !== 'confirmed'" class="text-slate-400"> · payment pending</span>
              </p>
            </div>
            <button v-if="['registration_open','draft'].includes(t.status)"
              class="btn-ghost text-xs px-3 py-1.5 shrink-0" :disabled="withdrawing" @click="withdrawTeam">
              {{ withdrawing ? '…' : 'Withdraw' }}
            </button>
          </div>
        </div>

        <!-- Register CTA -->
        <RouterLink v-if="regOpen && !myRegistration" :to="`/tournament/${t.id}/register`"
          class="card-neon p-5 flex items-center gap-4 no-underline hover:shadow-lg transition-all active:scale-[0.99]">
          <div class="text-3xl shrink-0">📝</div>
          <div class="flex-1 min-w-0">
            <p class="font-display font-bold gradient-text">Register your team</p>
            <p class="text-xs text-slate-500 mt-0.5">
              {{ data.confirmed_count }}/{{ t.max_teams }} teams confirmed{{ t.entry_fee ? ` · Entry ${t.currency} ${t.entry_fee}` : '' }}
            </p>
            <p v-if="t.registration_end" class="text-[11px] text-amber-600 mt-0.5">Registration closes {{ fmtDate(t.registration_end) }}</p>
          </div>
          <span class="btn-primary text-sm px-4 py-2 shrink-0">Register →</span>
        </RouterLink>

        <!-- Key info -->
        <div class="grid sm:grid-cols-2 gap-3">
          <div v-if="t.entry_fee" class="card p-4">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Entry fee</p>
            <p class="text-lg font-extrabold text-slate-800">{{ t.currency }} {{ t.entry_fee }}</p>
            <p class="text-[11px] text-slate-400">per team</p>
          </div>
          <div v-if="t.prize_info" class="card p-4">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Prizes</p>
            <p class="text-sm font-semibold text-slate-700">{{ t.prize_info }}</p>
          </div>
          <div v-if="t.venue_address" class="card p-4 sm:col-span-2">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Venue</p>
            <p class="text-sm font-semibold text-slate-700">{{ t.venue }}</p>
            <p class="text-xs text-slate-500">{{ t.venue_address }}</p>
            <a v-if="t.maps_url" :href="t.maps_url" target="_blank" rel="noopener" class="text-xs text-neon font-semibold mt-1 inline-block">Get directions ↗</a>
          </div>
        </div>

        <div v-if="t.description" class="card p-4">
          <p class="text-sm text-slate-600 whitespace-pre-wrap leading-relaxed">{{ t.description }}</p>
        </div>

        <!-- Podium (once results are in) -->
        <div v-if="t.winner_registration_id" class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100 text-xs font-bold text-slate-600">🏆 Results</div>
          <div class="divide-y divide-slate-50">
            <div class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥇</span><span class="font-bold text-slate-800">{{ teamName(t.winner_registration_id) || 'Champion' }}</span></div>
            <div v-if="t.runner_up_registration_id" class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥈</span><span class="font-semibold text-slate-700">{{ teamName(t.runner_up_registration_id) }}</span></div>
            <div v-if="t.third_registration_id" class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥉</span><span class="font-semibold text-slate-700">{{ teamName(t.third_registration_id) }}</span></div>
          </div>
        </div>

        <!-- Group standings (groups_knockout) -->
        <div v-if="isGroups && groupStandings.length" class="space-y-3">
          <p class="label">Group standings</p>
          <div v-for="g in groupStandings" :key="'g' + g.label" class="card p-3">
            <div class="text-[11px] font-bold uppercase tracking-wide text-slate-500 mb-2">Group {{ g.label }}</div>
            <div class="space-y-1">
              <div v-for="(tm, i) in g.teams" :key="tm.id" class="flex items-center gap-2 text-xs"
                :class="i < (t.advance_per_group || 2) ? 'text-slate-800 font-semibold' : 'text-slate-500'">
                <span class="w-4 text-center text-slate-400">{{ i + 1 }}</span>
                <span class="flex-1 min-w-0 truncate">{{ tm.name }}</span>
                <span class="tabular-nums">{{ tm.wins }}W–{{ tm.losses }}L</span>
                <span class="tabular-nums text-slate-400 w-10 text-right">{{ tm.setDiff >= 0 ? '+' : '' }}{{ tm.setDiff }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Standings (round robin) -->
        <div v-else-if="isRoundRobin && standings.length && hasResults" class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100 text-xs font-bold text-slate-600">📊 Standings</div>
          <div class="divide-y divide-slate-50">
            <div v-for="(s, i) in standings" :key="s.registration_id" class="flex items-center gap-3 px-4 py-2.5 text-sm">
              <span class="w-5 text-center text-xs font-bold" :class="i === 0 ? 'text-amber-500' : 'text-slate-400'">{{ i + 1 }}</span>
              <span class="flex-1 min-w-0 truncate font-semibold text-slate-700">{{ s.team_name }}</span>
              <span class="text-xs tabular-nums text-slate-500">{{ s.wins }}W–{{ s.losses }}L</span>
              <span class="text-xs tabular-nums text-slate-400 w-12 text-right">{{ (s.sets_for - s.sets_against) >= 0 ? '+' : '' }}{{ s.sets_for - s.sets_against }}</span>
            </div>
          </div>
        </div>

        <!-- Live results / draw -->
        <div v-if="matchSections.length">
          <div class="flex items-center gap-2 mb-2">
            <p class="label mb-0">{{ hasResults ? 'Results & fixtures' : 'Draw' }}</p>
            <span v-if="t.status === 'live'" class="inline-flex items-center gap-1 text-[10px] font-bold text-rose-500">
              <span class="w-1.5 h-1.5 rounded-full bg-rose-500 animate-ping" /> LIVE
            </span>
          </div>
          <div class="space-y-4">
            <div v-for="sec in matchSections" :key="sec.title" class="space-y-1.5">
              <p class="text-[11px] font-bold uppercase tracking-wide text-slate-400">{{ sec.title }}</p>
              <div v-for="m in sec.matches" :key="m.id" class="card px-3 py-2.5"
                :class="m.status === 'completed' ? 'border-emerald-100' : ''">
                <div class="flex items-center gap-2">
                  <span v-if="m.court" class="text-[9px] text-slate-400 w-10 shrink-0">Court {{ m.court }}</span>
                  <span class="flex-1 min-w-0 truncate text-xs font-semibold"
                    :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-700'">
                    {{ m.team_a_name || 'TBD' }}<span v-if="m.winner_id === m.team_a_id"> 🏆</span>
                  </span>
                  <span class="shrink-0 flex items-center gap-1.5 font-extrabold text-sm tabular-nums">
                    <span :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-400'">{{ m.score_a ?? '–' }}</span>
                    <span class="text-slate-300 font-normal text-[10px]">vs</span>
                    <span :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-400'">{{ m.score_b ?? '–' }}</span>
                  </span>
                  <span class="flex-1 min-w-0 truncate text-right text-xs font-semibold"
                    :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-700'">
                    <span v-if="m.winner_id === m.team_b_id">🏆 </span>{{ m.team_b_name || 'TBD' }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Teams -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="label">Confirmed teams</p>
            <span class="text-xs text-slate-400">{{ teams.length }}/{{ t.max_teams }}</span>
          </div>
          <div v-if="!teams.length" class="card p-6 text-center text-sm text-slate-400">
            No teams confirmed yet — check back soon.
          </div>
          <div v-else class="grid sm:grid-cols-2 gap-2">
            <div v-for="(tm, i) in teams" :key="tm.id" class="card p-3 flex items-center gap-3">
              <div class="w-8 h-8 rounded-lg flex items-center justify-center text-xs font-black text-slate-950 shrink-0"
                style="background:linear-gradient(135deg,#00e5ff,#a855f7)">{{ tm.seed && tm.seed > 1 ? tm.seed : (i + 1) }}</div>
              <div class="min-w-0">
                <p class="text-sm font-bold text-slate-800 truncate">{{ tm.team_name }}</p>
                <p class="text-xs text-slate-500 truncate">{{ [tm.player_a_name, tm.player_b_name].filter(Boolean).join(' & ') }}</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Photos -->
        <div v-if="t.group_photo_url || photos.length">
          <p class="label mb-2">📸 Photos</p>
          <img v-if="t.group_photo_url" :src="t.group_photo_url" alt="Group photo"
            class="w-full rounded-2xl mb-2 cursor-zoom-in object-cover" loading="lazy"
            @click="lightbox = t.group_photo_url" />
          <div v-if="photos.length" class="grid grid-cols-3 gap-2">
            <button v-for="p in photos" :key="p.id" class="aspect-square rounded-xl overflow-hidden bg-slate-100"
              @click="lightbox = p.url">
              <img :src="p.url" :alt="p.caption || 'Tournament photo'" class="w-full h-full object-cover cursor-zoom-in" loading="lazy" />
            </button>
          </div>
        </div>

        <div class="text-center py-6">
          <RouterLink to="/" class="text-xs text-slate-400 hover:text-neon transition">Powered by <span class="font-semibold gradient-text">Badminton 360</span> →</RouterLink>
        </div>
      </main>
    </template>

    <!-- Photo lightbox -->
    <div v-if="lightbox" class="fixed inset-0 z-50 flex items-center justify-center p-4"
      style="background:rgba(0,0,0,.85)" @click="lightbox = null">
      <img :src="lightbox" alt="" class="max-w-full max-h-full rounded-lg" />
      <button class="absolute top-4 right-4 text-white/80 text-2xl">✕</button>
    </div>
  </div>
</template>
