<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { buildProfileMap } from '../lib/playerNames'
import { useAuth } from '../composables/useAuth'
import Avatar from '../components/Avatar.vue'
import PerfChart from '../components/PerfChart.vue'
import { sharePlayerCard, whatsappShareUrl } from '../utils/share-card'
import { tierFor, nextTier } from '../utils/tiers'
import { computeStreaks, computePointsDiff, computePartnerships, computeHeadToHead } from '../utils/insights'
import { evaluateAchievements, earnedCount } from '../utils/achievements'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()

const playerId = route.params.id
const adminView  = ref(false)

const player      = ref(null)
const profile     = ref(null)
const stats       = ref(null)
const honours     = ref([])
const displayRank = ref(null)   // position within games>0 board — matches /scoreboard
const matches     = ref([])

// Rank consistent with the leaderboard: position among players with games>0,
// ordered by club_rank — NOT the raw v_leaderboard.club_rank (which counts
// zero-game active players too and disagrees with what the user sees elsewhere).
function rankFromBoard(board, pid) {
  const ranked = (board ?? []).filter(r => (r.games ?? 0) > 0)
    .sort((a, b) => (a.club_rank ?? 0) - (b.club_rank ?? 0))
  const i = ranked.findIndex(r => r.id === pid)
  return i >= 0 ? i + 1 : null
}
const clubName    = ref('')
const emirates    = ref('')
const loading     = ref(true)
const visibleDateCount = ref(5)
const loadError     = ref(null)

const isOwnProfile = computed(() =>
  user.value && player.value?.user_id === user.value.id
)

const publicName = computed(() =>
  profile.value?.nickname || player.value?.display_name || '—'
)

const initials = computed(() => {
  const n = publicName.value
  return n.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
})

async function load() {
  loading.value = true
  loadError.value = null
  try {

  // Check for admin view
  const wantsAdmin = route.query.admin === '1' && !!user.value
  if (wantsAdmin) {
    const { data: roles } = await supabase.rpc('get_my_roles')
    adminView.value = (roles ?? []).some(r => r.role === 'app_admin')
  }

  if (adminView.value) {
    // ── Admin path: use SECURITY DEFINER RPCs that bypass RLS ──────────
    const [playerRes, matchRes] = await Promise.all([
      supabase.rpc('admin_get_player', { p_player_id: playerId }),
      supabase.rpc('admin_get_player_matches', { p_player_id: playerId, p_limit: 300 }),
    ])

    if (playerRes.error) {
      loadError.value = playerRes.error.code === 'PGRST202'
        ? 'Admin RPCs not deployed — run supabase/v34_schema.sql in Supabase SQL Editor.'
        : `Admin error: ${playerRes.error.message}`
      loading.value = false
      return
    }

    const p = playerRes.data?.[0] ?? null
    if (!p) { loadError.value = 'Player not found (admin path).'; loading.value = false; return }

    player.value   = { id: p.id, display_name: p.display_name, elo: p.elo, club_id: p.club_id, user_id: p.user_id }
    clubName.value = p.club_name ?? ''
    emirates.value = p.emirates ?? ''

    // Fetch public profile via existing SECURITY DEFINER RPC
    if (p.user_id) {
      const { data: profs } = await supabase.rpc('get_public_profiles', { p_user_ids: [p.user_id] })
      profile.value = profs?.[0] ?? null
    }

    // Stats from get_club_leaderboard (already SECURITY DEFINER)
    const { data: lb } = await supabase.rpc('get_club_leaderboard', { p_club_id: p.club_id })
    stats.value = (lb ?? []).find(r => r.id === playerId) ?? null
    displayRank.value = rankFromBoard(lb, playerId)

    // Map matches from admin RPC shape → same shape used by template
    const rawMatches = matchRes.data ?? []
    matches.value = rawMatches.map(m => {
      const sideA = m.side_a
      const sideB = m.side_b
      const playerInA = (sideA?.participants ?? []).some(mp => mp.player_id === playerId)
      const mySide  = playerInA ? sideA : sideB
      const oppSide = playerInA ? sideB : sideA
      const myMp = (mySide?.participants ?? []).find(mp => mp.player_id === playerId)
      return {
        id: m.match_id,
        date: m.played_on,
        name: m.display_name ?? `Match #${m.match_number}`,
        won: mySide?.is_winner ?? false,
        myScore:  mySide?.score  ?? 0,
        oppScore: oppSide?.score ?? 0,
        myTeam:  (mySide?.participants  ?? []).map(mp => ({ name: mp.display_name, avatar: null })).filter(t => t.name),
        oppTeam: (oppSide?.participants ?? []).map(mp => ({ name: mp.display_name, avatar: null })).filter(t => t.name),
        partners:  (mySide?.participants  ?? []).filter(mp => mp.player_id !== playerId)
          .map(mp => ({ id: mp.player_id, name: mp.display_name })).filter(t => t.id),
        opponents: (oppSide?.participants ?? [])
          .map(mp => ({ id: mp.player_id, name: mp.display_name })).filter(t => t.id),
        eloDelta: myMp?.elo_after != null ? Math.round(myMp.elo_after - myMp.elo_before) : null,
        eloAfter: myMp?.elo_after != null ? Math.round(myMp.elo_after) : null,
      }
    })

    loading.value = false
    return
  }

  // ── Normal member path ──────────────────────────────────────────────
  // 1. Player base row
  const { data: p } = await supabase
    .from('players')
    .select('id, display_name, elo, club_id, user_id')
    .eq('id', playerId)
    .single()
  player.value = p

  if (!p) { loading.value = false; return }

  // 2. Public profile (nickname + bio only — deliberately no phone/email)
  const [profRes, statsRes, clubRes, matchRes] = await Promise.all([
    p.user_id
      ? supabase.rpc('get_public_profiles', { p_user_ids: [p.user_id] })
          .then(({ data }) => ({ data: data?.[0] ?? null }))
      : { data: null },

    supabase.from('v_leaderboard')
      .select('elo, club_rank, games, wins, win_pct, days_played, composite')
      .eq('id', playerId)
      .maybeSingle(),

    supabase.from('clubs')
      .select('name, emirates')
      .eq('id', p.club_id)
      .single(),

    supabase.from('matches')
      .select(`
        id, played_on, display_name, match_number,
        match_sides(
          side, score, is_winner,
          match_participants(
            elo_before, elo_after,
            players(id, display_name, user_id)
          )
        )
      `)
      .eq('club_id', p.club_id)
      .order('created_at', { ascending: false })
      .limit(300)
  ])

  profile.value  = profRes.data
  stats.value    = statsRes.data
  clubName.value = clubRes.data?.name ?? ''
  emirates.value = profRes.data?.emirate ?? clubRes.data?.emirates ?? ''

  // Positional rank consistent with /scoreboard (public SECURITY DEFINER board)
  supabase.rpc('get_club_leaderboard', { p_club_id: p.club_id })
    .then(({ data }) => { displayRank.value = rankFromBoard(data, playerId) }, () => {})

  const allParticipantIds = [...new Set(
    (matchRes.data ?? []).flatMap(m =>
      (m.match_sides ?? []).flatMap(s =>
        (s.match_participants ?? []).map(mp => mp.players?.id)
      )
    ).filter(Boolean)
  )]
  const profileMap = await buildProfileMap(allParticipantIds)

  const rawMatches = matchRes.data ?? []
  const filtered = rawMatches
    .filter(m => m.match_sides?.some(s =>
      s.match_participants?.some(mp => mp.players?.id === playerId)
    ))
  matches.value = filtered.map(m => {
    const sideA = m.match_sides?.find(s => s.side === 'A')
    const sideB = m.match_sides?.find(s => s.side === 'B')
    const playerInA = sideA?.match_participants?.some(mp => mp.players?.id === playerId)
    const mySide  = playerInA ? sideA : sideB
    const oppSide = playerInA ? sideB : sideA
    return {
      id: m.id,
      date: m.played_on,
      name: m.display_name ?? `Match #${m.match_number}`,
      won: mySide?.is_winner ?? false,
      myScore:  mySide?.score  ?? 0,
      oppScore: oppSide?.score ?? 0,
      myTeam:  (mySide?.match_participants  ?? []).map(mp => ({
        name: profileMap[mp.players?.id]?.name || mp.players?.display_name,
        avatar: profileMap[mp.players?.id]?.avatar ?? null
      })).filter(t => t.name),
      oppTeam: (oppSide?.match_participants ?? []).map(mp => ({
        name: profileMap[mp.players?.id]?.name || mp.players?.display_name,
        avatar: profileMap[mp.players?.id]?.avatar ?? null
      })).filter(t => t.name),
      partners: (mySide?.match_participants ?? [])
        .filter(mp => mp.players?.id !== playerId)
        .map(mp => ({ id: mp.players?.id, name: profileMap[mp.players?.id]?.name || mp.players?.display_name }))
        .filter(t => t.id),
      opponents: (oppSide?.match_participants ?? [])
        .map(mp => ({ id: mp.players?.id, name: profileMap[mp.players?.id]?.name || mp.players?.display_name }))
        .filter(t => t.id),
      eloDelta: (() => {
        const mp = mySide?.match_participants?.find(p => p.players?.id === playerId)
        return mp?.elo_after != null ? Math.round(mp.elo_after - mp.elo_before) : null
      })(),
      eloAfter: (() => {
        const mp = mySide?.match_participants?.find(p => p.players?.id === playerId)
        return mp?.elo_after != null ? Math.round(mp.elo_after) : null
      })()
    }
  })

  loading.value = false
  } catch (e) {
    loadError.value = 'Failed to load profile. Please try again.'
    loading.value = false
  }
}

// Load tournament honours whenever the player's linked account resolves.
watch(() => player.value?.user_id, async (uid) => {
  honours.value = []
  if (!uid) return
  const { data } = await supabase.rpc('get_player_tournament_honours', { p_user_id: uid })
  honours.value = data ?? []
})
const medalFor = p => (p === 1 ? '🥇' : p === 2 ? '🥈' : p === 3 ? '🥉' : '🎖️')
const placeLabel = p => (p === 1 ? 'Champion' : p === 2 ? 'Runner-up' : p === 3 ? 'Third place' : 'Finalist')

onMounted(load)

function loadMoreDates() { visibleDateCount.value += 10 }

const fmt = d => new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short' })
const fmtDate = d => new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { weekday:'short', day:'numeric', month:'short', year:'numeric' })
const deltaColor = d => d > 0 ? 'text-emerald-400' : d < 0 ? 'text-rose-400' : 'text-slate-500'
const deltaText  = d => d > 0 ? `+${d}` : `${d}`

// ── Performance chart + form (matches are newest-first → reverse to chrono) ──
const eloSeries = computed(() =>
  [...matches.value].filter(m => m.eloAfter != null).reverse().map((m, i) => ({ i, elo: m.eloAfter, date: m.date }))
)
const formGuide = computed(() => [...matches.value].slice(0, 12).reverse().map(m => m.won))

// ── Insights (all derived from match history already in memory) ──────────────
const eloNow = computed(() => Math.round(stats.value?.elo ?? player.value?.elo ?? 1000))
const tier   = computed(() => tierFor(eloNow.value))
const toNext = computed(() => nextTier(eloNow.value))

const wonChrono   = computed(() => [...matches.value].reverse().map(m => m.won))
const streaks     = computed(() => computeStreaks(wonChrono.value))
const pointsDiff  = computed(() => computePointsDiff(matches.value))
const allPartners = computed(() => computePartnerships(matches.value))
const partnerships = computed(() => allPartners.value.slice(0, 3))
const headToHead  = computed(() => computeHeadToHead(matches.value).slice(0, 5))

const gamesCount = computed(() => stats.value?.games ?? matches.value.length)
const winsCount  = computed(() => stats.value?.wins ?? matches.value.filter(m => m.won).length)
const winPctVal  = computed(() => Math.round(stats.value?.win_pct ?? (gamesCount.value ? (winsCount.value / gamesCount.value) * 100 : 0)))

const achievements = computed(() => evaluateAchievements({
  games: gamesCount.value,
  wins:  winsCount.value,
  winPct: winPctVal.value,
  elo:   eloNow.value,
  streaks: streaks.value,
  pointsDiff: pointsDiff.value,
  partnerships: allPartners.value,
}))
const achievementsEarned = computed(() => earnedCount(achievements.value))
const diffText = d => d > 0 ? `+${d}` : `${d}`

// Tap an achievement to see what it is + how to earn it (progress if applicable).
const selectedAch = ref(null)
const achPct = a => a?.progress ? Math.min(100, Math.round((a.progress.cur / a.progress.goal) * 100))
  : (a?.earned ? 100 : 0)

// Newly-unlocked celebration — per-device, localStorage. On your OWN profile we
// diff the earned set against what this device last saw; a fresh unlock pops a
// toast. First visit seeds silently (no toast storm for already-earned badges).
const unlockToast = ref(null)      // { icon, label, more }
const earnedDates = ref({})        // { [achId]: isoDate } — first-seen on this device
let unlockTimer = null
const achKey = () => `b360_ach_${playerId}`
function loadAchStore() { try { return JSON.parse(localStorage.getItem(achKey()) || 'null') } catch { return null } }
function saveAchStore(s) { try { localStorage.setItem(achKey(), JSON.stringify(s)) } catch {} }
const fmtAchDate = d => { try { return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) } catch { return '' } }

function syncAchievements() {
  if (!isOwnProfile.value) return
  const earnedIds = achievements.value.filter(a => a.earned).map(a => a.id)
  if (!earnedIds.length) return
  const now = new Date().toISOString()
  let store = loadAchStore()
  if (!store || !store.earned) {
    store = { seededAt: now, earned: Object.fromEntries(earnedIds.map(id => [id, now])) }
    saveAchStore(store)
    earnedDates.value = store.earned
    return
  }
  const newIds = earnedIds.filter(id => !store.earned[id])
  for (const id of newIds) store.earned[id] = now
  if (newIds.length) {
    saveAchStore(store)
    const first = achievements.value.find(a => a.id === newIds[0])
    unlockToast.value = { icon: first.icon, label: first.label, more: newIds.length - 1 }
    if (unlockTimer) clearTimeout(unlockTimer)
    unlockTimer = setTimeout(() => { unlockToast.value = null }, 4500)
  }
  earnedDates.value = store.earned
}
watch([isOwnProfile, achievements], syncAchievements)
onUnmounted(() => { if (unlockTimer) clearTimeout(unlockTimer) })

// ── Share card ──
const sharing   = ref(false)
const shareNote = ref('')
const shareCode = ref(null)   // tiny link code → badminton360.app/p/<code>

// Fetch (or create) the short share code once, so shared links stay tidy.
async function ensureShareCode() {
  if (shareCode.value) return
  const { data } = await supabase.rpc('get_or_create_player_share_code', { p_player_id: playerId })
  if (data) shareCode.value = data
}
const shareUrl = () => shareCode.value
  ? `https://badminton360.app/p/${shareCode.value}`
  : `https://badminton360.app/player/${playerId}`

const cardData = () => ({
  name:      publicName.value,
  club:      clubName.value,
  city:      emirates.value,
  rank:      displayRank.value,
  elo:       Math.round(stats.value?.elo ?? player.value?.elo ?? 1000),
  games:     stats.value?.games ?? matches.value.length,
  winPct:    Math.round(stats.value?.win_pct ?? 0),
  form:      formGuide.value,
  eloSeries: eloSeries.value.map(p => p.elo),
  avatarUrl: profile.value?.avatar_url || null,
  url:       shareUrl(),
})
async function shareCard() {
  sharing.value = true; shareNote.value = ''
  try {
    await ensureShareCode()
    const res = await sharePlayerCard(cardData())
    if (res === 'downloaded') shareNote.value = '📥 Card saved — attach it in any app.'
  } catch {
    shareNote.value = 'Could not create the card. Please try again.'
  }
  sharing.value = false
}
async function shareWhatsApp() {
  // Pre-open a tab synchronously (avoids popup blockers), then set its URL once
  // the short code resolves.
  const w = window.open('', '_blank')
  await ensureShareCode()
  const url = whatsappShareUrl(cardData())
  if (w) w.location = url
  else window.open(url, '_blank')
}

const expandedDates = ref(new Set())
const allExpanded   = computed(() => groupedMatches.value.length > 0 && expandedDates.value.size === groupedMatches.value.length)

function toggleDate(date) {
  const s = new Set(expandedDates.value)
  s.has(date) ? s.delete(date) : s.add(date)
  expandedDates.value = s
}

function toggleAll() {
  if (allExpanded.value) {
    expandedDates.value = new Set()
  } else {
    expandedDates.value = new Set(groupedMatches.value.map(g => g.date))
  }
}

const groupedMatches = computed(() => {
  const groups = {}
  for (const m of matches.value) {
    if (!groups[m.date]) groups[m.date] = []
    groups[m.date].push(m)
  }
  return Object.entries(groups)
    .sort(([a], [b]) => b.localeCompare(a))
    .map(([date, items]) => ({
      date,
      items,
      total: items.length,
      wins: items.filter(m => m.won).length
    }))
})

const visibleGroups = computed(() => groupedMatches.value.slice(0, visibleDateCount.value))
const hasMoreDates  = computed(() => visibleDateCount.value < groupedMatches.value.length)
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <div v-else-if="loadError" class="card p-6 text-center">
    <div class="text-2xl mb-2">⚠️</div>
    <p class="text-sm text-rose-400">{{ loadError }}</p>
    <button class="btn-ghost mt-3 text-sm" @click="load">Try Again</button>
  </div>

  <div v-else-if="!player" class="card p-8 text-center text-slate-400">
    <div class="text-3xl mb-3">❓</div>
    <p class="font-semibold mb-2">Player not found</p>
    <button class="btn-ghost px-6 text-sm" @click="router.back()">← Go Back</button>
  </div>

  <template v-else>

    <!-- Admin view banner -->
    <div v-if="adminView" class="mb-4 rounded-2xl bg-amber-50 border border-amber-300 px-4 py-3 flex items-center gap-3 fade-up">
      <span class="text-xl shrink-0">👑</span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-bold text-amber-800">You are viewing this player as Super Admin</p>
        <p class="text-xs text-amber-600">Full match history and stats visible. This view is admin-only.</p>
      </div>
      <button class="shrink-0 text-xs text-amber-700 underline hover:no-underline" @click="router.back()">← Back</button>
    </div>

    <!-- Back button (non-admin) -->
    <button v-else class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4 fade-up"
      @click="router.back()">
      ← Back
    </button>

    <!-- Header card -->
    <div class="card-neon p-5 mb-4 fade-up">
      <div class="flex items-center gap-4">
        <!-- Avatar -->
        <Avatar :name="publicName" :src="profile?.avatar_url" :size="64" class="rounded-2xl" />

        <div class="flex-1 min-w-0">
          <h2 class="font-display text-xl font-extrabold gradient-text leading-tight truncate">
            {{ publicName }}
          </h2>
          <!-- Club + emirate -->
          <div class="flex items-center gap-2 mt-1 flex-wrap">
            <span class="text-xs text-slate-300">{{ clubName }}</span>
            <span v-if="emirates" class="badge-member text-[9px]">{{ emirates }}</span>
            <span class="text-[10px] font-bold px-2 py-0.5 rounded-full"
              :style="{ color: tier.color, background: tier.color + '1a', border: '1px solid ' + tier.color + '55' }">
              {{ tier.emoji }} {{ tier.label }}
            </span>
          </div>
          <!-- Bio -->
          <p v-if="profile?.bio" class="text-xs text-slate-400 mt-1.5 italic">{{ profile.bio }}</p>
        </div>
      </div>

      <!-- Own profile edit link -->
      <RouterLink v-if="isOwnProfile" to="/profile"
        class="mt-3 block text-center text-xs text-neon hover:opacity-80 transition border border-cyan-500/25 rounded-xl py-2">
        ✏️ Edit My Profile
      </RouterLink>

      <!-- Share this player's card as an image (Instagram / anywhere) + a
           direct WhatsApp link so the badminton360.app URL always tags along -->
      <div class="mt-2 flex gap-2">
        <button class="flex-1 btn-primary py-2.5 text-sm gap-1.5" :disabled="sharing" @click="shareCard">
          {{ sharing ? 'Creating card…' : '📤 Share Card' }}
        </button>
        <button class="py-2.5 px-4 rounded-xl text-sm font-semibold transition shrink-0"
          style="background:rgba(37,211,102,0.14); border:1px solid rgba(37,211,102,0.35); color:#15803d"
          @click="shareWhatsApp">💬 WhatsApp</button>
      </div>
      <p v-if="shareNote" class="text-center text-[11px] text-slate-500 mt-1.5">{{ shareNote }}</p>
    </div>

    <!-- Stats row -->
    <div v-if="stats" class="grid grid-cols-4 gap-2 mb-4 fade-up">
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold" :class="stats.games > 0 ? 'text-gold' : 'text-slate-600'">
          {{ stats.games > 0 ? '#' + (displayRank ?? stats.club_rank) : '—' }}
        </div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Rank</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-neon">{{ stats.elo }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Elo</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-slate-200">{{ stats.games }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Games</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-violet">{{ stats.win_pct }}%</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Win%</div>
      </div>
    </div>

    <!-- Tournament honours -->
    <div v-if="honours.length" class="card p-4 mb-4 fade-up">
      <div class="text-xs font-bold text-slate-700 mb-2">🏆 Tournament honours</div>
      <div class="space-y-1.5">
        <RouterLink v-for="h in honours" :key="h.tournament_id + '-' + h.placement"
          :to="'/t/' + h.share_code"
          class="flex items-center gap-2.5 no-underline rounded-lg px-2 py-1.5 hover:bg-slate-50 transition">
          <span class="text-lg shrink-0">{{ medalFor(h.placement) }}</span>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-slate-800 truncate">{{ h.tournament_name }}</p>
            <p class="text-[11px] text-slate-400 truncate">{{ placeLabel(h.placement) }} · {{ h.club_name }}</p>
          </div>
        </RouterLink>
      </div>
    </div>

    <!-- Performance chart + recent form -->
    <div v-if="stats && stats.games > 0" class="card p-4 mb-4 fade-up">
      <div class="flex items-center justify-between mb-2">
        <div class="text-xs font-bold text-slate-700">📈 Elo Progression</div>
        <div v-if="formGuide.length" class="flex items-center gap-1" title="Recent form">
          <span v-for="(w, i) in formGuide" :key="i" class="w-2.5 h-2.5 rounded-full"
            :class="w ? 'bg-emerald-500' : 'bg-rose-400'"></span>
        </div>
      </div>
      <PerfChart :series="eloSeries" :height="130" />
      <div v-if="eloSeries.length >= 2" class="flex justify-between text-[10px] text-slate-400 mt-1">
        <span>{{ eloSeries[0].elo }}</span>
        <span class="text-slate-500">{{ eloSeries.length }} matches</span>
        <span :class="eloSeries[eloSeries.length-1].elo >= eloSeries[0].elo ? 'text-emerald-500' : 'text-rose-400'">
          {{ eloSeries[eloSeries.length-1].elo }}
        </span>
      </div>
    </div>

    <!-- Form & streaks + points differential -->
    <div v-if="gamesCount > 0" class="card p-4 mb-4 fade-up">
      <div class="text-xs font-bold text-slate-700 mb-3">🔥 Form & Streaks</div>
      <div class="grid grid-cols-4 gap-2 text-center">
        <div>
          <div class="text-lg font-extrabold"
            :class="streaks.type === 'win' ? 'text-emerald-500' : streaks.type === 'loss' ? 'text-rose-400' : 'text-slate-400'">
            {{ streaks.current }}
          </div>
          <div class="text-[9px] text-slate-500 uppercase tracking-wider mt-0.5">{{ streaks.type === 'loss' ? 'Loss' : 'Win' }} Streak</div>
        </div>
        <div>
          <div class="text-lg font-extrabold text-emerald-500">{{ streaks.longestWin }}</div>
          <div class="text-[9px] text-slate-500 uppercase tracking-wider mt-0.5">Longest Win</div>
        </div>
        <div>
          <div class="text-lg font-extrabold text-rose-400">{{ streaks.longestLoss }}</div>
          <div class="text-[9px] text-slate-500 uppercase tracking-wider mt-0.5">Longest Loss</div>
        </div>
        <div>
          <div class="text-lg font-extrabold" :class="pointsDiff >= 0 ? 'text-neon' : 'text-rose-400'">{{ diffText(pointsDiff) }}</div>
          <div class="text-[9px] text-slate-500 uppercase tracking-wider mt-0.5">Points Diff</div>
        </div>
      </div>
      <div v-if="toNext" class="mt-3 pt-3 border-t border-slate-100 flex items-center justify-between text-[11px]">
        <span class="text-slate-500">{{ toNext.needed }} Elo to
          <span class="font-semibold" :style="{ color: toNext.color }">{{ toNext.emoji }} {{ toNext.label }}</span>
        </span>
        <span class="text-slate-400">now {{ tier.emoji }} {{ tier.label }}</span>
      </div>
    </div>

    <!-- Best partnerships -->
    <div v-if="partnerships.length" class="card p-4 mb-4 fade-up">
      <div class="text-xs font-bold text-slate-700 mb-2">🤝 Best Partnerships</div>
      <div class="space-y-1.5">
        <RouterLink v-for="p in partnerships" :key="p.id" :to="'/player/' + p.id"
          class="flex items-center gap-2.5 no-underline rounded-lg px-2 py-1.5 hover:bg-slate-50 transition">
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-slate-800 truncate">{{ p.name }}</p>
            <p class="text-[11px] text-slate-400">{{ p.games }} {{ p.games === 1 ? 'game' : 'games' }} together</p>
          </div>
          <div class="text-right shrink-0">
            <p class="text-sm font-extrabold text-emerald-500">{{ p.winPct }}%</p>
            <p v-if="p.avgElo != null" class="text-[10px] font-semibold"
              :class="p.avgElo >= 0 ? 'text-slate-400' : 'text-rose-400'">{{ diffText(p.avgElo) }} avg Elo</p>
          </div>
        </RouterLink>
      </div>
    </div>

    <!-- Head-to-head -->
    <div v-if="headToHead.length" class="card p-4 mb-4 fade-up">
      <div class="text-xs font-bold text-slate-700 mb-2">⚔️ Head-to-Head</div>
      <div class="space-y-1.5">
        <RouterLink v-for="o in headToHead" :key="o.id" :to="'/player/' + o.id"
          class="flex items-center gap-2.5 no-underline rounded-lg px-2 py-1.5 hover:bg-slate-50 transition">
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-slate-800 truncate">{{ o.name }}</p>
            <p class="text-[11px] text-slate-400">{{ o.games }} played</p>
          </div>
          <div class="text-right shrink-0">
            <p class="text-sm font-extrabold" :class="o.winPct >= 50 ? 'text-emerald-500' : 'text-rose-400'">{{ o.winPct }}%</p>
            <p class="text-[10px] text-slate-400">win rate</p>
          </div>
        </RouterLink>
      </div>
    </div>

    <!-- Achievements -->
    <div v-if="gamesCount > 0" class="card p-4 mb-4 fade-up">
      <div class="flex items-center justify-between mb-3">
        <div class="text-xs font-bold text-slate-700">🏆 Achievements</div>
        <span class="badge-member text-[10px]">{{ achievementsEarned }} / {{ achievements.length }}</span>
      </div>
      <div class="grid grid-cols-2 gap-2">
        <button v-for="a in achievements" :key="a.id" type="button" @click="selectedAch = a"
          class="text-left rounded-xl px-3 py-2.5 flex items-center gap-2.5 transition hover:brightness-95 active:scale-[0.98]"
          :class="a.earned ? 'bg-gradient-to-br from-amber-50 to-cyan-50 border border-amber-200' : 'bg-slate-50 border border-slate-100'">
          <span class="text-xl shrink-0" :class="a.earned ? '' : 'grayscale opacity-40'">{{ a.icon }}</span>
          <div class="min-w-0 flex-1">
            <p class="text-[12px] font-bold truncate" :class="a.earned ? 'text-slate-800' : 'text-slate-400'">{{ a.label }}</p>
            <p v-if="a.earned" class="text-[10px] text-emerald-500 font-semibold">✓ Unlocked</p>
            <p v-else-if="a.progress" class="text-[10px] text-slate-400 font-medium">{{ a.progress.cur }} / {{ a.progress.goal }}</p>
            <p v-else class="text-[10px] text-slate-400">Tap to see how</p>
            <div v-if="a.progress" class="mt-1 h-1 rounded-full bg-slate-200 overflow-hidden">
              <div class="h-full bg-cyan-400 rounded-full" :style="{ width: achPct(a) + '%' }"></div>
            </div>
          </div>
        </button>
      </div>
    </div>

    <!-- Match history -->
    <div class="card overflow-hidden fade-up">
      <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)] flex items-center justify-between">
        <div>
          <span class="text-xs font-bold text-slate-200">Recent Matches</span>
          <span class="text-[10px] text-slate-600 ml-2">(last {{ matches.length }})</span>
        </div>
        <button v-if="groupedMatches.length" @click="toggleAll"
                class="text-[11px] font-semibold text-neon hover:underline transition">
          {{ allExpanded ? 'Collapse All' : 'Expand All' }}
        </button>
      </div>

      <div v-if="!matches.length" class="px-4 py-6 text-center text-sm text-slate-500">
        No matches recorded yet.
      </div>

      <template v-for="group in visibleGroups" :key="group.date">
        <!-- Date header row — tap to expand/collapse -->
        <button class="w-full px-4 py-2.5 flex items-center justify-between bg-slate-50 border-b border-[rgba(15,23,42,0.06)] hover:bg-slate-100 transition-colors"
                @click="toggleDate(group.date)">
          <div class="flex items-center gap-2">
            <span class="text-xs transition-transform duration-200"
                  :style="expandedDates.has(group.date) ? 'transform:rotate(90deg)' : ''">▶</span>
            <span class="text-xs font-semibold text-slate-600">{{ fmtDate(group.date) }}</span>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-[11px] text-slate-400">{{ group.total }} {{ group.total === 1 ? 'game' : 'games' }}</span>
            <span class="text-[11px] font-semibold text-emerald-500">{{ group.wins }} won</span>
          </div>
        </button>
        <!-- Match rows — shown only when expanded -->
        <template v-if="expandedDates.has(group.date)">
          <button v-for="m in group.items" :key="m.id"
            class="w-full text-left px-4 py-3 border-b border-[rgba(15,23,42,0.04)] last:border-0
                   hover:bg-[rgba(15,23,42,0.03)] transition-colors duration-150 group"
            @click="router.push('/matches?open=' + m.id)">
            <div class="flex items-center justify-between mb-1">
              <span class="text-xs text-slate-500">{{ m.name }}</span>
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold"
                  :class="m.won ? 'text-neon' : 'text-rose-400'">
                  {{ m.won ? '🏆 Won' : 'Lost' }}
                </span>
                <span v-if="m.eloDelta != null" class="text-[11px] font-semibold"
                  :class="deltaColor(m.eloDelta)">
                  {{ deltaText(m.eloDelta) }}
                </span>
                <span class="text-slate-700 group-hover:text-slate-400 transition text-xs">›</span>
              </div>
            </div>
            <div class="flex items-center gap-1.5 text-xs text-slate-400 flex-wrap">
              <span class="flex items-center gap-1 text-slate-200 font-medium">
                <template v-for="(t, ti) in m.myTeam" :key="'my' + ti">
                  <Avatar :name="t.name" :src="t.avatar" :size="20" />
                  <span>{{ t.name }}</span>
                  <span v-if="ti < m.myTeam.length - 1" class="text-slate-500">+</span>
                </template>
              </span>
              <span class="mx-0.5 text-slate-600">{{ m.myScore }}–{{ m.oppScore }}</span>
              <span class="flex items-center gap-1">
                <template v-for="(t, ti) in m.oppTeam" :key="'opp' + ti">
                  <Avatar :name="t.name" :src="t.avatar" :size="20" />
                  <span>{{ t.name }}</span>
                  <span v-if="ti < m.oppTeam.length - 1" class="text-slate-500">+</span>
                </template>
              </span>
            </div>
          </button>
        </template>
      </template>
      <!-- Load more dates -->
      <div v-if="hasMoreDates" class="px-4 py-3 border-t border-[rgba(15,23,42,0.05)]">
        <button class="btn-ghost w-full text-sm" @click="loadMoreDates">
          Load More Dates ({{ groupedMatches.length - visibleDateCount }} more days)
        </button>
      </div>
    </div>

    <!-- Achievement detail sheet -->
    <Teleport to="body">
      <div v-if="selectedAch" class="fixed inset-0 z-[200] flex items-end sm:items-center justify-center px-4"
        style="background:rgba(15,23,42,0.45)" @click.self="selectedAch = null">
        <div class="w-full max-w-sm bg-white rounded-3xl p-6 text-center shadow-2xl mb-4 sm:mb-0 fade-up">
          <div class="text-5xl mb-3" :class="selectedAch.earned ? '' : 'grayscale opacity-40'">{{ selectedAch.icon }}</div>
          <span class="badge-member text-[10px] mb-2 inline-block">{{ selectedAch.category }}</span>
          <h3 class="font-display text-lg font-extrabold text-slate-800">{{ selectedAch.label }}</h3>

          <p v-if="selectedAch.earned" class="mt-1 text-sm font-semibold text-emerald-500">✓ Unlocked</p>
          <p v-if="selectedAch.earned && earnedDates[selectedAch.id]" class="text-[11px] text-slate-400">Earned {{ fmtAchDate(earnedDates[selectedAch.id]) }}</p>
          <p v-if="!selectedAch.earned" class="mt-1 text-xs text-slate-400 uppercase tracking-wider">Locked</p>

          <div class="mt-4 rounded-2xl bg-slate-50 border border-slate-100 px-4 py-3 text-left">
            <p class="text-[11px] font-bold text-slate-500 uppercase tracking-wider mb-1">How to earn it</p>
            <p class="text-sm text-slate-700">{{ selectedAch.desc }}</p>
          </div>

          <div v-if="!selectedAch.earned && selectedAch.progress" class="mt-4">
            <div class="flex items-center justify-between text-[11px] mb-1">
              <span class="text-slate-500">Your progress</span>
              <span class="font-semibold text-slate-700">{{ selectedAch.progress.cur }} / {{ selectedAch.progress.goal }}</span>
            </div>
            <div class="h-2 rounded-full bg-slate-200 overflow-hidden">
              <div class="h-full bg-cyan-400 rounded-full transition-all" :style="{ width: achPct(selectedAch) + '%' }"></div>
            </div>
          </div>

          <button class="btn-primary w-full mt-5 py-2.5 text-sm" @click="selectedAch = null">Got it</button>
        </div>
      </div>
    </Teleport>

    <!-- Achievement unlocked toast (own profile, newly earned) -->
    <Teleport to="body">
      <Transition name="ach-pop">
        <div v-if="unlockToast"
          class="fixed left-1/2 -translate-x-1/2 z-[300] px-5 py-3 rounded-2xl shadow-2xl flex items-center gap-3"
          style="bottom:calc(env(safe-area-inset-bottom,0px) + 5.5rem); background:linear-gradient(135deg,#fbbf24,#a855f7); color:#fff; box-shadow:0 12px 40px rgba(168,85,247,.4)">
          <span class="text-3xl">{{ unlockToast.icon }}</span>
          <div>
            <div class="text-[11px] font-bold uppercase tracking-wider opacity-90">🏆 Achievement unlocked</div>
            <div class="text-sm font-extrabold leading-tight">{{ unlockToast.label }}</div>
            <div v-if="unlockToast.more" class="text-[11px] opacity-90">+{{ unlockToast.more }} more unlocked</div>
          </div>
        </div>
      </Transition>
    </Teleport>

  </template>
</template>

<style scoped>
.ach-pop-enter-active, .ach-pop-leave-active { transition: all .4s cubic-bezier(.34,1.56,.64,1); }
.ach-pop-enter-from, .ach-pop-leave-to { opacity: 0; transform: translate(-50%, 28px) scale(.9); }
</style>
