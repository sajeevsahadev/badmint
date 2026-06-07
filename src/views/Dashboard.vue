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
const showFullBoard   = ref(false)

// ── Time-of-day greeting ──────────────────────────────────────────────
const h = new Date().getHours()
const greetText  = h < 12 ? 'Good morning'   : h < 17 ? 'Good afternoon' : 'Good evening'
const greetEmoji = h < 12 ? '☀️'             : h < 17 ? '⛅'             : '🌙'

// ── Load ──────────────────────────────────────────────────────────────
async function load() {
  loading.value = true
  await Promise.all([loadProfile(), loadClubData(), loadTournaments(), loadFacilities()])
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
    supabase.from('v_leaderboard').select('*').eq('club_id', cid).order('club_rank'),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid)
      .order('win_pct', { ascending: false }).order('games', { ascending: false }).limit(3),
  ])
  board.value     = lb ?? []
  bestPairs.value = bp ?? []

  // Find own player row
  const inBoard = board.value.find(p => p.user_id === user.value?.id)
  if (inBoard) {
    myPlayer.value = inBoard
  } else if (user.value) {
    const { data: me } = await supabase
      .from('v_leaderboard')
      .select('*').eq('club_id', cid).eq('user_id', user.value.id).maybeSingle()
    myPlayer.value = me ?? null
  }

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
              <p class="text-[10px] text-slate-400 uppercase tracking-widest">Your Rank</p>
              <p class="text-lg font-extrabold text-neon leading-none">
                #{{ myPlayer.club_rank }}
                <span class="text-xs text-slate-400 font-normal ml-0.5">in {{ clubName }}</span>
              </p>
            </div>
            <div>
              <p class="text-[10px] text-slate-400 uppercase tracking-widest">Elo</p>
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
              <p class="text-[10px] text-slate-400 uppercase tracking-widest">W%</p>
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
          class="shrink-0 text-[10px] text-neon hover:opacity-75 transition mt-1">
          Club Profile →
        </RouterLink>
      </div>
    </div>

    <!-- ── 2. Announcements (open tournaments + facilities) ───────────── -->
    <div v-if="openTournaments.length" class="space-y-2">
      <p class="label">📣 Announcements</p>
      <div v-for="t in openTournaments" :key="t.id"
        class="card-violet p-4 cursor-pointer active:scale-[0.99] transition-transform"
        @click="router.push('/tournament/' + t.id)">
        <div class="flex items-start justify-between gap-2">
          <div class="flex-1 min-w-0">
            <p class="text-[10px] font-bold uppercase tracking-widest text-violet-500 mb-1">
              🏆 Tournament · Registration Open
            </p>
            <p class="font-bold text-slate-800 text-sm truncate">{{ t.name }}</p>
            <p class="text-xs text-slate-500 mt-0.5">
              {{ t.confirmed_teams }} / {{ t.max_teams }} teams
              <span v-if="t.start_date"> · Starts {{ fmtDate(t.start_date) }}</span>
              <span v-if="t.entry_fee"> · AED {{ t.entry_fee }}</span>
            </p>
          </div>
          <button class="shrink-0 btn-violet text-xs px-3 py-1.5">Register</button>
        </div>
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
            <p class="text-[10px] text-slate-400">Log a doubles result</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-violet-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/tournaments')">
          <span class="text-2xl">🏆</span>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Tournaments</p>
            <p class="text-[10px] text-slate-400">Join or browse events</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-amber-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/schedule')">
          <span class="text-2xl">📅</span>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Schedule Court</p>
            <p class="text-[10px] text-slate-400">Plan match days</p>
          </div>
        </button>
        <button class="card p-4 flex items-center gap-3 hover:border-emerald-400/50 transition-all active:scale-[0.97]"
          @click="router.push('/splits')">
          <span class="text-2xl">💰</span>
          <div class="text-left min-w-0">
            <p class="text-sm font-bold text-slate-800 truncate">Pay Splits</p>
            <p class="text-[10px] text-slate-400">Split court costs</p>
          </div>
        </button>
      </div>
    </div>

    <!-- ── 4. Your Club mini-leaderboard ────────────────────────────── -->
    <div v-if="currentClub">
      <div class="flex items-center justify-between mb-2">
        <p class="label">🏸 {{ clubName }}</p>
        <button class="text-[10px] text-neon hover:opacity-75 transition"
          @click="showFullBoard = !showFullBoard">
          {{ showFullBoard ? 'Show less ↑' : 'See Full Rankings →' }}
        </button>
      </div>

      <div v-if="!board.length" class="card p-6 text-center text-sm text-slate-400">
        No matches yet — record one to start the leaderboard.
      </div>

      <div v-else class="card overflow-hidden">
        <!-- Mini top 3 + me -->
        <div v-for="(p, i) in miniBoard" :key="p.id">
          <!-- Gap separator before "you" if not in top 3 -->
          <div v-if="p._gap" class="px-4 py-1 text-center text-[9px] text-slate-400 border-t border-slate-100 tracking-widest">
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
                <span v-if="isMe(p)" class="text-[10px] font-normal text-cyan-500 ml-1">you</span>
              </p>
            </div>
            <div class="text-right shrink-0">
              <p class="text-sm font-extrabold text-neon">{{ p.composite }} pts</p>
              <p class="text-[10px] text-slate-400">Elo {{ p.elo }}</p>
            </div>
          </RouterLink>
        </div>
      </div>

      <!-- Full leaderboard (expandable) -->
      <div v-if="showFullBoard && board.length" class="mt-3 space-y-3">

        <!-- Podium top 3 -->
        <div class="grid grid-cols-3 gap-2">
          <div v-for="(p, i) in board.slice(0, 3)" :key="p.id"
            :class="i === 0 ? 'card-amber' : 'card'"
            class="flex flex-col items-center p-3 text-center">
            <div class="text-2xl mb-1"
              :style="i === 0 ? 'filter:drop-shadow(0 0 10px rgba(217,119,6,.5))' : ''">
              {{ medals[i] }}
            </div>
            <RouterLink :to="'/player/' + p.id"
              class="text-xs font-bold truncate w-full text-center text-slate-700 hover:text-neon transition-colors">
              {{ p.display_name }}
            </RouterLink>
            <div class="text-[11px] font-extrabold mt-0.5"
              :class="i === 0 ? 'text-gold' : 'text-neon'">
              {{ p.composite }} pts
            </div>
            <div class="text-[10px] text-slate-400">Elo {{ p.elo }}</div>
          </div>
        </div>

        <!-- Full table -->
        <div class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100 flex items-center justify-between">
            <span class="text-xs font-bold text-slate-600 tracking-wide">Full Leaderboard</span>
            <InfoTip text="Sorted by composite rank points = Skill (70%) + Attendance (30%), both normalised 0–100 within club." />
          </div>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-slate-100">
                <th class="pl-4 pr-2 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-400">#</th>
                <th class="pl-2 pr-3 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-400">Player</th>
                <th class="px-2 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400">Pts</th>
                <th class="px-2 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400">Elo</th>
                <th class="px-2 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400">W%</th>
                <th class="pl-2 pr-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400">Days</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(p, i) in board" :key="p.id"
                class="border-b border-slate-50 last:border-0 transition-colors"
                :class="isMe(p) ? 'bg-cyan-50/70' : (i === 0 ? 'bg-amber-50/50' : 'hover:bg-slate-50')">
                <td class="pl-4 pr-2 py-3 font-bold text-slate-500">{{ medals[i] ?? (i + 1) }}</td>
                <td class="pl-2 pr-3 py-3">
                  <RouterLink :to="'/player/' + p.id"
                    class="font-semibold text-slate-800 hover:text-neon transition-colors">
                    {{ p.display_name }}
                    <span v-if="isMe(p)" class="text-[10px] text-cyan-500 ml-1">you</span>
                  </RouterLink>
                </td>
                <td class="px-2 py-3 text-right font-extrabold text-neon text-xs">{{ p.composite }}</td>
                <td class="px-2 py-3 text-right text-xs font-semibold" :class="trendColor(p.elo)">{{ p.elo }}</td>
                <td class="px-2 py-3 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
                <td class="pl-2 pr-4 py-3 text-right text-xs text-slate-400">{{ p.days_played }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Best pairs -->
        <div v-if="bestPairs.length" class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100 flex items-center gap-2">
            <span class="text-xs font-bold text-slate-600">🏅 Best Pairs</span>
            <InfoTip text="Ranked by win % across all doubles matches played together (min 1 game)." />
          </div>
          <div v-for="(pair, i) in bestPairs" :key="pair.p1 + pair.p2"
            class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
            <span class="text-lg shrink-0 w-6 text-center">{{ ['🥇','🥈','🥉'][i] }}</span>
            <div class="flex-1 min-w-0">
              <p class="text-sm font-bold text-slate-700 truncate">{{ pair.p1_name }} + {{ pair.p2_name }}</p>
              <p class="text-[10px] text-slate-400 mt-0.5">
                {{ pair.games }} games · {{ pair.wins }}W / {{ pair.games - pair.wins }}L
              </p>
            </div>
            <div class="text-lg font-extrabold text-neon shrink-0">{{ pair.win_pct }}%</div>
          </div>
        </div>

        <!-- Quick compare link -->
        <button class="card w-full py-3 text-sm text-slate-400 hover:text-neon transition-all flex items-center justify-center gap-2"
          @click="router.push('/compare')">
          ⚔️ Head-to-Head Comparison
        </button>
      </div>
    </div>

    <!-- ── 5a. My Club's Tournaments (all statuses) ────────────────── -->
    <div v-if="myClubTournaments.length">
      <div class="flex items-center justify-between mb-2">
        <p class="label">🏆 My Club Tournaments</p>
        <RouterLink to="/tournaments" class="text-[10px] text-neon hover:opacity-75 transition">
          See All →
        </RouterLink>
      </div>
      <div class="space-y-2">
        <div v-for="t in myClubTournaments" :key="t.id"
          class="card p-4 cursor-pointer hover:border-violet-400/40 transition-all active:scale-[0.99]"
          @click="router.push('/tournament/' + t.id)">
          <div class="flex items-center justify-between gap-2">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 mb-1 flex-wrap">
                <span :class="{
                  'badge-pending':  t.status === 'draft',
                  'badge-approved': t.status === 'registration_open',
                  'badge bg-rose-50 text-rose-600 border border-rose-200': t.status === 'live',
                  'badge bg-slate-100 text-slate-500 border border-slate-200': t.status === 'completed',
                }">
                  {{ { draft:'Draft', registration_open:'Open', live:'🔴 Live', completed:'Done', cancelled:'Cancelled', registration_closed:'Closed' }[t.status] ?? t.status }}
                </span>
                <span class="text-[10px] text-slate-400">
                  {{ t.format === 'single_elimination' ? 'Knock-out' : 'Round Robin' }}
                </span>
              </div>
              <p class="font-bold text-slate-800 text-sm truncate">{{ t.name }}</p>
              <p class="text-xs text-slate-500 mt-0.5">
                {{ t.confirmed_teams }} confirmed
                <span v-if="t.pending_teams"> · {{ t.pending_teams }} pending</span>
                <span v-if="t.start_date"> · {{ fmtDate(t.start_date) }}</span>
              </p>
            </div>
            <span class="text-slate-300 text-sm shrink-0">→</span>
          </div>
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
        <RouterLink to="/explore" class="text-[10px] text-neon hover:opacity-75 transition">
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
        <RouterLink to="/explore" class="text-[10px] text-neon hover:opacity-75 transition">
          + Join or Create
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
          @click="selectClub(c); router.push('/dashboard')">
          <div class="w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0"
            :class="currentClub?.club_id === c.club_id ? 'bg-cyan-100' : 'bg-slate-100'">
            🏸
          </div>
          <div class="flex-1 min-w-0">
            <p class="font-semibold text-slate-800 text-sm truncate">{{ c.clubs?.name }}</p>
            <p class="text-xs text-slate-400 capitalize">{{ c.role }}</p>
          </div>
          <span v-if="currentClub?.club_id === c.club_id"
            class="shrink-0 text-[10px] font-bold text-cyan-600">Active</span>
          <span v-else class="shrink-0 text-slate-300 text-sm">→</span>
        </div>
      </div>
    </div>

  </div>
</template>
