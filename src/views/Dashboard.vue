<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import InfoTip from '../components/InfoTip.vue'
import Avatar from '../components/Avatar.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'

const router = useRouter()
const { avatarMap, loadAvatars } = usePlayerAvatars()
const { user } = useAuth()
const { clubs, currentClub, selectClub } = useClub()

// ── Data ──────────────────────────────────────────────────────────────
const board           = ref([])
const bestPairs       = ref([])
const myPlayer        = ref(null)
const nickName        = ref('')
const weeklyDelta     = ref(null)
const allTournaments  = ref([])   // every tournament returned (for club-own section)
const openTournaments = ref([])
const liveTournaments = ref([])
const loading         = ref(true)
const todayTomorrowSchedule = ref([])   // club_schedule rows for today/tomorrow — quick poll link
const chatUnread      = ref(0)          // unread club-chat messages for the current club

// ── Time-of-day greeting ──────────────────────────────────────────────
const h = new Date().getHours()
const greetText  = h < 12 ? 'Good morning'   : h < 17 ? 'Good afternoon' : 'Good evening'
const greetEmoji = h < 12 ? '☀️'             : h < 17 ? '⛅'             : '🌙'

// ── Load ──────────────────────────────────────────────────────────────
// Guard against stale loads when the user switches clubs quickly:
// each load() call captures an ID; if a newer call has started by the time
// async work completes, the older one discards its results.
let _loadKey = 0
async function load() {
  const key = ++_loadKey
  loading.value = true
  await Promise.all([loadProfile(), loadClubData(), loadTournaments(), loadTodayTomorrow(), loadChatUnread()])
  if (key !== _loadKey) return
  loading.value = false
}

async function loadChatUnread() {
  chatUnread.value = 0
  if (!currentClub.value) return
  const { data } = await supabase.rpc('get_chat_unread_count', { p_club_id: currentClub.value.club_id })
  chatUnread.value = data ?? 0
}

// "Who's playing today/tomorrow?" quick link — points straight at the
// existing poll for that date instead of making the user dig through Schedule.
function localDateStr(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
// Parse a YYYY-MM-DD as LOCAL date (not UTC) for the date badge.
const parseYmd = s => new Date(s + 'T00:00:00')
const dayNum   = s => parseYmd(s).getDate()
const monthAbbr = s => parseYmd(s).toLocaleDateString('en', { month: 'short' }).toUpperCase()

// Per-date "hide" for the who's-playing cards, persisted so a card the user
// dismisses (e.g. after today's game is done) stays hidden for that date.
// Keyed by scheduled_date; old entries (< today) are pruned so it never grows.
const HIDDEN_KEY = 'b360_hidden_schedules'
function loadHidden() {
  try {
    const raw = JSON.parse(localStorage.getItem(HIDDEN_KEY) || '[]')
    const today = localDateStr(new Date())
    const kept = (Array.isArray(raw) ? raw : []).filter(d => d >= today)
    if (kept.length !== raw.length) localStorage.setItem(HIDDEN_KEY, JSON.stringify(kept))
    return new Set(kept)
  } catch { return new Set() }
}
const hiddenDates = ref(loadHidden())
function hideSchedule(date) {
  hiddenDates.value = new Set([...hiddenDates.value, date])
  localStorage.setItem(HIDDEN_KEY, JSON.stringify([...hiddenDates.value]))
}
async function loadTodayTomorrow() {
  todayTomorrowSchedule.value = []
  if (!currentClub.value) return
  const today    = new Date()
  const tomorrow = new Date(Date.now() + 86400000)
  const { data } = await supabase
    .from('club_schedule')
    .select('id, scheduled_date')
    .eq('club_id', currentClub.value.club_id)
    .in('scheduled_date', [localDateStr(today), localDateStr(tomorrow)])
    .order('scheduled_date')
  todayTomorrowSchedule.value = data ?? []
}

async function loadProfile() {
  if (!user.value) return
  const { data } = await supabase
    .from('user_profiles')
    .select('nickname')
    .eq('user_id', user.value.id)
    .maybeSingle()
  nickName.value =
    data?.nickname ||
    user.value.user_metadata?.full_name?.split(' ')[0] ||
    user.value.email?.split('@')[0] ||
    'Player'
}

async function loadClubData() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id

  const [{ data: lb }, { data: bp }] = await Promise.all([
    supabase.from('v_leaderboard').select('*').eq('club_id', cid).gt('games', 0).order('club_rank'),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid)
      .order('win_pct', { ascending: false }).order('games', { ascending: false }).limit(3),
  ])
  board.value     = lb ?? []
  bestPairs.value = bp ?? []
  loadAvatars(board.value.map(p => p.user_id))

  // v_leaderboard already contains every active player for this club —
  // no second query needed. Inactive players are excluded from the view, so
  // the second query never produced a result they wouldn't have.
  myPlayer.value = board.value.find(p => p.user_id === user.value?.id) ?? null

  // Weekly Elo delta (last 7 days)
  if (myPlayer.value) {
    const sevenAgo = new Date(Date.now() - 7 * 86400000).toISOString().slice(0, 10)
    const { data: mps } = await supabase
      .from('match_participants')
      .select('elo_before, elo_after, match_sides!inner(matches!inner(played_on))')
      .eq('player_id', myPlayer.value.id)
    const weekMps = (mps ?? []).filter(mp =>
      (mp.match_sides?.matches?.played_on ?? '') >= sevenAgo
    )
    weeklyDelta.value = weekMps.length
      ? Math.round(weekMps.reduce((s, mp) => s + (mp.elo_after - mp.elo_before), 0))
      : null
  }
}

async function loadTournaments() {
  const { data } = await supabase.rpc('get_tournaments', {
    p_club_id: null, p_status: null, p_emirate: null
  })
  const all = data ?? []
  allTournaments.value  = all
  openTournaments.value = all.filter(t => t.status === 'registration_open').slice(0, 2)
  liveTournaments.value = all.filter(t => t.status === 'live').slice(0, 3)
}


onMounted(load)
watch(currentClub, load)

// ── Computed ──────────────────────────────────────────────────────────
const isMe = p => p.user_id === user.value?.id

// Top 3 + me if I'm not in top 3
const miniBoard = computed(() => {
  const top3 = board.value.slice(0, 3)
  const inTop3 = top3.some(isMe)
  if (!inTop3 && myPlayer.value) {
    return [...top3, { ...myPlayer.value, _gap: true }]
  }
  return top3
})

const medals = ['🥇','🥈','🥉']
const trendColor = elo => elo >= 1050 ? 'text-neon' : elo <= 950 ? 'text-rose-400' : 'text-slate-400'

// Displayed rank = position within the games>0 leaderboard (same as /scoreboard).
// NOT v_leaderboard.club_rank, which ranks ALL active players incl. zero-game ones
// and so disagrees with the leaderboard the user actually sees.
const myRank = computed(() => {
  const i = board.value.findIndex(isMe)
  return i >= 0 ? i + 1 : null
})

// Tournaments for THIS club (all statuses, so draft ones are visible to manager)
const myClubTournaments = computed(() =>
  allTournaments.value
    .filter(t => t.club_id === currentClub.value?.club_id)
    .slice(0, 5)
)

const clubName = computed(() => currentClub.value?.clubs?.name ?? '')

// Today/tomorrow schedule entries, labelled — powers the Dashboard quick link
const todayStr = localDateStr(new Date())
const upcomingSchedule = computed(() =>
  todayTomorrowSchedule.value
    .filter(s => !hiddenDates.value.has(s.scheduled_date))
    .map(s => ({
      ...s,
      label: s.scheduled_date === todayStr ? 'today' : 'tomorrow',
    }))
)

const fmtDate = d => d
  ? new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short' })
  : '—'
</script>

<template>
  <!-- Loading skeleton -->
  <div v-if="loading" class="space-y-3 fade-up">
    <div class="h-28 shimmer rounded-2xl" />
    <div class="h-20 shimmer rounded-2xl" />
    <div class="grid grid-cols-2 gap-2">
      <div class="h-16 shimmer rounded-2xl" />
      <div class="h-16 shimmer rounded-2xl" />
      <div class="h-16 shimmer rounded-2xl" />
      <div class="h-16 shimmer rounded-2xl" />
    </div>
    <div class="h-40 shimmer rounded-2xl" />
  </div>

  <div v-else class="space-y-4 fade-up">

    <!-- ── 1. Greeting card ──────────────────────────────────────────── -->
    <div class="card-neon p-4">
      <div class="flex items-start justify-between gap-2">
        <div class="flex-1 min-w-0">
          <p class="text-sm text-slate-500 mb-0.5">{{ greetText }}, {{ greetEmoji }}</p>
          <h1 class="font-display text-2xl font-extrabold gradient-text truncate">
            {{ nickName }}
          </h1>

          <!-- My rank + Elo -->
          <div v-if="myPlayer" class="mt-2 flex flex-wrap items-center gap-3">
            <div>
              <p class="text-xs text-slate-400 uppercase tracking-widest">Your Rank</p>
              <p class="text-lg font-extrabold text-neon leading-none">
                #{{ myRank ?? myPlayer.club_rank }}
                <span class="text-xs text-slate-400 font-normal ml-0.5">in {{ clubName }}</span>
              </p>
            </div>
            <div>
              <p class="text-xs text-slate-400 uppercase tracking-widest">Elo</p>
              <p class="text-lg font-extrabold text-slate-700 leading-none">
                {{ myPlayer.elo }}
                <span v-if="weeklyDelta !== null"
                  class="text-xs font-semibold ml-1"
                  :class="weeklyDelta >= 0 ? 'text-emerald-600' : 'text-rose-500'">
                  {{ weeklyDelta >= 0 ? '+' : '' }}{{ weeklyDelta }} this week
                </span>
              </p>
            </div>
            <div>
              <p class="text-xs text-slate-400 uppercase tracking-widest">W%</p>
              <p class="text-lg font-extrabold text-slate-700 leading-none">{{ myPlayer.win_pct }}%</p>
            </div>
          </div>

          <div v-else class="mt-2 text-sm text-slate-400">
            <span v-if="currentClub">Play your first match to appear on the leaderboard!</span>
            <span v-else>Join a club to see your stats here.</span>
          </div>
        </div>

        <!-- Club profile link -->
        <RouterLink v-if="currentClub" :to="'/club/' + currentClub.club_id"
          class="shrink-0 text-xs text-neon hover:opacity-75 transition mt-1">
          Club Profile →
        </RouterLink>
      </div>
    </div>

    <!-- ── 1a. Club chat quick link ─────────────────────────────────────── -->
    <RouterLink v-if="currentClub" to="/chat"
      class="card p-4 flex items-center gap-3 fade-up hover:border-violet-400/50 transition-all active:scale-[0.99]">
      <div class="relative shrink-0">
        <div class="icon-tile icon-tile-violet w-11 h-11 text-xl">💬</div>
        <span v-if="chatUnread > 0"
          class="absolute -top-1.5 -right-1.5 min-w-[20px] h-5 px-1.5 rounded-full bg-rose-500 text-white text-[11px] font-bold flex items-center justify-center ring-2 ring-white">
          {{ chatUnread > 99 ? '99+' : chatUnread }}
        </span>
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-bold text-slate-800">Club Chat</p>
        <p class="text-xs" :class="chatUnread > 0 ? 'text-rose-500 font-semibold' : 'text-slate-400'">
          {{ chatUnread > 0 ? `${chatUnread} new message${chatUnread > 1 ? 's' : ''}` : 'Message your club members' }}
        </p>
      </div>
      <span class="text-slate-300 shrink-0">→</span>
    </RouterLink>

    <!-- ── 1b. Who's playing today/tomorrow? — quick link straight to the poll ── -->
    <RouterLink v-for="s in upcomingSchedule" :key="s.id"
      :to="`/schedule?date=${s.scheduled_date}`"
      class="card-amber p-4 flex items-center gap-3 fade-up">
      <!-- Real date badge (day + month) instead of a static calendar emoji -->
      <div class="icon-tile icon-tile-amber w-11 h-11 flex-col leading-none">
        <span class="text-base font-extrabold text-amber-700">{{ dayNum(s.scheduled_date) }}</span>
        <span class="text-[8px] font-bold text-amber-600 tracking-wide">{{ monthAbbr(s.scheduled_date) }}</span>
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-bold text-slate-800">See who's playing {{ s.label }}</p>
        <p class="text-xs text-slate-400">Tap to view or cast your attendance vote</p>
      </div>
      <button class="shrink-0 w-7 h-7 rounded-lg flex items-center justify-center text-slate-300
                     hover:text-rose-500 hover:bg-rose-50 transition"
        title="Hide this" aria-label="Hide"
        @click.stop.prevent="hideSchedule(s.scheduled_date)">✕</button>
    </RouterLink>

    <!-- ── 2. Getting Started — shown until this club has its first match ──
         Directly addresses "where do I start" confusion after login: a clear,
         prioritized 3-step path instead of a flat grid of equal-weight actions.
         Disappears on its own once board.length > 0 (first match recorded). -->
    <div v-if="currentClub && !board.length" class="card-neon p-4 fade-up">
      <p class="text-sm font-bold text-slate-800 mb-0.5">👋 New here? Start with these steps</p>
      <p class="text-xs text-slate-400 mb-3">This card goes away once your club's first match is recorded.</p>
      <div class="space-y-1">
        <RouterLink to="/players"
          class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-cyan-50/60 transition-colors">
          <div class="icon-tile icon-tile-cyan w-9 h-9 text-sm font-extrabold text-cyan-700">1</div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-slate-800">Add your players</p>
            <p class="text-xs text-slate-400">Roster + invite teammates by email</p>
          </div>
          <span class="text-slate-300 shrink-0">→</span>
        </RouterLink>
        <RouterLink to="/match"
          class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-violet-50/60 transition-colors">
          <div class="icon-tile icon-tile-violet w-9 h-9 text-sm font-extrabold text-violet-700">2</div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-slate-800">Record your first match</p>
            <p class="text-xs text-slate-400">Pick 4 players, enter the score — Elo updates instantly</p>
          </div>
          <span class="text-slate-300 shrink-0">→</span>
        </RouterLink>
        <RouterLink to="/splits"
          class="flex items-center gap-3 p-2.5 rounded-xl hover:bg-emerald-50/60 transition-colors">
          <div class="icon-tile icon-tile-emerald w-9 h-9 text-sm font-extrabold text-emerald-700">3</div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-slate-800">Split court costs</p>
            <p class="text-xs text-slate-400">Track expenses fairly with Split Pay</p>
          </div>
          <span class="text-slate-300 shrink-0">→</span>
        </RouterLink>
      </div>
    </div>

    <!-- ── 3. Quick Actions ──────────────────────────────────────────── -->
    <div>
      <p class="label mb-2">⚡ Quick Actions</p>
      <div class="grid grid-cols-2 gap-2">
        <button class="card p-4 flex items-center gap-3 hover:border-cyan-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/match')">
          <div class="icon-tile icon-tile-cyan w-11 h-11 text-xl">➕</div>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Record Match</p>
            <p class="text-xs text-slate-400">Log a doubles result</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-violet-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/matches')">
          <div class="icon-tile icon-tile-violet w-11 h-11 text-xl">📋</div>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Matches</p>
            <p class="text-xs text-slate-400">Match history</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-emerald-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/splits?tab=balance')">
          <div class="icon-tile icon-tile-emerald w-11 h-11 text-xl">💰</div>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Split Pay</p>
            <p class="text-xs text-slate-400">Your balance</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-amber-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/schedule')">
          <div class="icon-tile icon-tile-amber w-11 h-11 text-xl">📅</div>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Who's Playing?</p>
            <p class="text-xs text-slate-400">Match day attendance poll</p>
          </div>
        </button>
      </div>
    </div>

    <!-- ── 4. Your Club mini-leaderboard ────────────────────────────── -->
    <div v-if="currentClub">
      <div class="flex items-center justify-between mb-2">
        <p class="label">🏸 {{ clubName }}</p>
        <RouterLink to="/scoreboard" class="text-xs text-neon hover:opacity-75 transition">
          See Full Rankings →
        </RouterLink>
      </div>

      <div v-if="!board.length" class="card p-6 text-center text-sm text-slate-400">
        No matches yet — record one to start the leaderboard.
      </div>

      <div v-else class="card overflow-hidden">
        <!-- Mini top 3 + me -->
        <div v-for="(p, i) in miniBoard" :key="p.id">
          <!-- Gap separator before "you" if not in top 3 -->
          <div v-if="p._gap" class="px-4 py-1 text-center text-xs text-slate-400 border-t border-slate-100 tracking-widest">
            · · ·
          </div>
          <RouterLink :to="'/player/' + p.id"
            class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0 transition-colors"
            :class="isMe(p) ? 'bg-cyan-50/80' : 'hover:bg-slate-50'">
            <span class="w-7 text-center text-base shrink-0">
              {{ p._gap ? `#${myRank ?? p.club_rank}` : (medals[i] ?? `#${i+1}`) }}
            </span>
            <Avatar :name="p.display_name" :src="avatarMap[p.user_id]" :size="32" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold truncate"
                :class="isMe(p) ? 'text-cyan-700' : 'text-slate-800'">
                {{ p.display_name }}
                <span v-if="isMe(p)" class="text-xs font-normal text-cyan-500 ml-1">you</span>
              </p>
            </div>
            <div class="text-right shrink-0">
              <p class="text-sm font-extrabold text-neon">{{ p.elo }} <span class="text-[10px] font-semibold text-slate-400">Elo</span></p>
              <p class="text-xs text-slate-400">{{ p.win_pct }}% win</p>
            </div>
          </RouterLink>
        </div>
      </div>
    </div>

    <!-- ── 5b. Live Tournaments ──────────────────────────────────────── -->
    <div v-if="liveTournaments.length">
      <p class="label mb-2">🔴 Live Tournaments</p>
      <div class="space-y-2">
        <div v-for="t in liveTournaments" :key="t.id"
          class="card p-4 cursor-pointer hover:border-cyan-400/40 transition-all active:scale-[0.99]"
          @click="router.push('/tournament/' + t.id)">
          <div class="flex items-center justify-between gap-2">
            <div class="flex-1 min-w-0">
              <p class="font-bold text-slate-800 text-sm truncate">{{ t.name }}</p>
              <p class="text-xs text-slate-500 mt-0.5">
                {{ t.club_name }}
                <span v-if="t.format === 'single_elimination'"> · Knock-out</span>
                <span v-else> · Round Robin</span>
              </p>
            </div>
            <div class="shrink-0 flex items-center gap-2">
              <span class="badge bg-rose-50 text-rose-600 border border-rose-200">🔴 Live</span>
              <span class="text-slate-300 text-sm">→</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── 7. Your Clubs ────────────────────────────────────────────── -->
    <div>
      <div class="flex items-center justify-between mb-2">
        <p class="label">👥 Your Clubs</p>
        <RouterLink to="/join" class="text-xs text-neon hover:opacity-75 transition">
          + Join
        </RouterLink>
      </div>

      <div v-if="!clubs.length" class="card p-6 text-center text-sm text-slate-400">
        You're not in any club yet.
        <RouterLink to="/explore" class="text-neon underline ml-1">Browse clubs →</RouterLink>
      </div>

      <div v-else class="space-y-2">
        <div v-for="c in clubs" :key="c.club_id"
          class="card p-4 flex items-center gap-3 cursor-pointer transition-all active:scale-[0.99]"
          :class="currentClub?.club_id === c.club_id
            ? 'border-cyan-400/50 bg-cyan-50/30'
            : 'hover:border-slate-300'"
          @click="router.push('/club/' + c.club_id)">
          <div class="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
            :class="currentClub?.club_id === c.club_id ? 'bg-cyan-100' : 'bg-slate-100'">
            🏸
          </div>
          <div class="flex-1 min-w-0">
            <p class="font-semibold text-slate-800 text-sm truncate">{{ c.clubs?.name }}</p>
            <p class="text-xs text-slate-400 capitalize">{{ c.role }}</p>
          </div>
          <span v-if="currentClub?.club_id === c.club_id"
            class="shrink-0 text-xs font-bold text-cyan-600">Active</span>
          <span v-else class="shrink-0 text-slate-300 text-sm">→</span>
        </div>
      </div>
    </div>

  </div>
</template>
