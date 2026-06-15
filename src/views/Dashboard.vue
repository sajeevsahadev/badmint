<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import InfoTip from '../components/InfoTip.vue'

const router = useRouter()
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
const facilities      = ref([])
const loading         = ref(true)

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
  await Promise.all([loadProfile(), loadClubData(), loadTournaments(), loadFacilities()])
  if (key !== _loadKey) return
  loading.value = false
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

async function loadFacilities() {
  const { data } = await supabase.rpc('get_facilities', { p_emirate: null, p_search: null })
  facilities.value = (data ?? []).slice(0, 3)
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

// Tournaments for THIS club (all statuses, so draft ones are visible to manager)
const myClubTournaments = computed(() =>
  allTournaments.value
    .filter(t => t.club_id === currentClub.value?.club_id)
    .slice(0, 5)
)

const clubName = computed(() => currentClub.value?.clubs?.name ?? '')

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
                #{{ myPlayer.club_rank }}
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

    <!-- ── 3. Quick Actions ──────────────────────────────────────────── -->
    <div>
      <p class="label mb-2">⚡ Quick Actions</p>
      <div class="grid grid-cols-2 gap-2">
        <button class="card p-4 flex items-center gap-3 hover:border-cyan-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/match')">
          <span class="text-2xl">➕</span>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Record Match</p>
            <p class="text-xs text-slate-400">Log a doubles result</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-amber-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/schedule')">
          <span class="text-2xl">📅</span>
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
              {{ p._gap ? `#${p.club_rank}` : (medals[i] ?? `#${i+1}`) }}
            </span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold truncate"
                :class="isMe(p) ? 'text-cyan-700' : 'text-slate-800'">
                {{ p.display_name }}
                <span v-if="isMe(p)" class="text-xs font-normal text-cyan-500 ml-1">you</span>
              </p>
            </div>
            <div class="text-right shrink-0">
              <p class="text-sm font-extrabold text-neon">{{ p.composite }} pts</p>
              <p class="text-xs text-slate-400">Elo {{ p.elo }}</p>
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

    <!-- ── 6. Courts Near You ────────────────────────────────────────── -->
    <div v-if="facilities.length">
      <div class="flex items-center justify-between mb-2">
        <p class="label">🏢 Courts Near You</p>
        <RouterLink to="/explore" class="text-xs text-neon hover:opacity-75 transition">
          Browse All →
        </RouterLink>
      </div>
      <div class="space-y-2">
        <div v-for="f in facilities" :key="f.id"
          class="card p-4 flex items-center gap-3 cursor-pointer hover:border-cyan-400/40 transition-all active:scale-[0.99]"
          @click="router.push('/facility/' + f.id)">
          <div class="w-10 h-10 rounded-xl bg-cyan-50 flex items-center justify-center text-xl shrink-0">🏢</div>
          <div class="flex-1 min-w-0">
            <p class="font-semibold text-slate-800 text-sm truncate">{{ f.name }}</p>
            <p class="text-xs text-slate-400 truncate">
              <span v-if="f.emirate">{{ f.emirate }}</span>
              <span v-if="f.courts_count"> · {{ f.courts_count }} courts</span>
            </p>
          </div>
          <span class="text-slate-300 text-sm shrink-0">→</span>
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

    <!-- ── Coming Soon ───────────────────────────────────────────────── -->
    <div>
      <p class="label mb-2">🚀 Coming Soon</p>
      <div class="card overflow-hidden">
        <div class="flex items-center gap-3 px-4 py-3.5 border-b border-slate-100">
          <span class="text-2xl shrink-0">🏆</span>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold text-slate-800">Tournaments</p>
            <p class="text-xs text-slate-400 mt-0.5">Club &amp; regional badminton events</p>
          </div>
          <span class="shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full"
            style="background:#fef3c7; color:#92400e; border:1px solid #fde68a">Soon</span>
        </div>
        <div class="flex items-center gap-3 px-4 py-3.5">
          <span class="text-2xl shrink-0">🏟️</span>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold text-slate-800">Court Booking</p>
            <p class="text-xs text-slate-400 mt-0.5">Reserve your court in advance</p>
          </div>
          <span class="shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full"
            style="background:#fef3c7; color:#92400e; border:1px solid #fde68a">Soon</span>
        </div>
      </div>
    </div>

  </div>
</template>
