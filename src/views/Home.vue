<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const router = useRouter()
const { user } = useAuth()
const { clubs, currentClub, selectClub } = useClub()

const topClubs    = ref([])
const topPlayers  = ref([])
const searchQ     = ref('')
const searchRes   = ref([])
const searching   = ref(false)
const emirateFilter = ref('')
const loading     = ref(true)

const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

// My clubs with ranking info
const myClubsWithScore = computed(() =>
  topClubs.value.filter(c => clubs.value.some(m => m.club_id === c.id))
)

const filteredClubs = computed(() => {
  let list = topClubs.value
  if (emirateFilter.value) list = list.filter(c => c.emirates === emirateFilter.value)
  // Own clubs first
  return [...list].sort((a, b) => {
    const aOwn = myClubsWithScore.value.some(m => m.id === a.id) ? 1 : 0
    const bOwn = myClubsWithScore.value.some(m => m.id === b.id) ? 1 : 0
    return bOwn - aOwn || (a.club_rank ?? 999) - (b.club_rank ?? 999)
  }).slice(0, 6)
})

async function load() {
  loading.value = true
  const [clubsRes, playersRes] = await Promise.all([
    supabase.rpc('get_public_clubs'),
    supabase.rpc('get_top_scorers', { p_limit: 10 }),
  ])
  topClubs.value   = clubsRes.data   ?? []
  topPlayers.value = playersRes.data ?? []
  loading.value    = false
}

async function doSearch() {
  if (!searchQ.value.trim()) { searchRes.value = []; return }
  searching.value = true
  const q = searchQ.value.trim()
  const [clubsRes, facRes] = await Promise.all([
    supabase.rpc('get_public_clubs'),
    supabase.rpc('get_facilities', { p_search: q }),
  ])
  const clubs_ = (clubsRes.data ?? []).filter(c =>
    c.name.toLowerCase().includes(q.toLowerCase()) ||
    (c.facility_name || '').toLowerCase().includes(q.toLowerCase())
  ).slice(0, 4)
  const facs = (facRes.data ?? []).slice(0, 4)
  searchRes.value = [
    ...clubs_.map(c => ({ type: 'club', id: c.id, name: c.name, sub: c.emirates ?? '', to: '/club/' + c.id })),
    ...facs.map(f => ({ type: 'facility', id: f.id, name: f.name, sub: f.emirate ?? '', to: '/facility/' + f.id })),
  ]
  searching.value = false
}

function switchMyClub(clubId) {
  const c = clubs.value.find(x => x.club_id === clubId)
  if (c) { selectClub(c); router.push('/dashboard') }
}

onMounted(load)
</script>

<template>
  <!-- ── UAE Hero ── -->
  <div class="relative -mx-4 -mt-4 mb-6 overflow-hidden" style="min-height:220px">

    <!-- UAE-inspired layered background -->
    <div class="absolute inset-0"
      style="background:linear-gradient(160deg, #060d1a 0%, #0a1628 25%, #0d2035 50%, #0f1a10 75%, #1a1205 100%);" />
    <!-- Desert dunes silhouette -->
    <div class="absolute bottom-0 left-0 right-0 h-16 opacity-20"
      style="background:linear-gradient(to top, rgba(251,191,36,.4), transparent);" />
    <!-- Grid lines -->
    <div class="absolute inset-0 opacity-[0.04]"
      style="background-image:linear-gradient(rgba(0,229,255,.6) 1px,transparent 1px),linear-gradient(90deg,rgba(0,229,255,.6) 1px,transparent 1px); background-size:40px 40px;" />
    <!-- UAE flag accent strip -->
    <div class="absolute top-0 right-0 bottom-0 w-1.5"
      style="background:linear-gradient(to bottom, #00732f 33%, white 33%, white 66%, #ff0000 66%);" />

    <!-- Orbs -->
    <div class="absolute top-4 right-8 w-32 h-32 rounded-full opacity-15"
      style="background:radial-gradient(circle,#00e5ff,transparent);" />
    <div class="absolute bottom-4 left-8 w-24 h-24 rounded-full opacity-10"
      style="background:radial-gradient(circle,#fbbf24,transparent);" />

    <!-- Hero content -->
    <div class="relative px-4 pt-6 pb-8">
      <div class="flex items-center gap-2 mb-1">
        <span class="text-3xl" style="filter:drop-shadow(0 0 12px rgba(0,229,255,.6))">🏸</span>
        <h1 class="font-display text-3xl font-extrabold gradient-text">Badmint</h1>
      </div>
      <p class="text-slate-400 text-sm mb-4">UAE Badminton Rankings · All 7 Emirates 🇦🇪</p>

      <!-- Search bar -->
      <div class="relative">
        <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400">🔍</span>
        <input v-model="searchQ" class="input pl-10 bg-white/[0.07]"
          placeholder="Search clubs or facilities…"
          @input="doSearch" @keyup.enter="doSearch" />
      </div>

      <!-- Search results dropdown -->
      <div v-if="searchRes.length" class="card mt-1 overflow-hidden">
        <RouterLink v-for="r in searchRes" :key="r.type + r.id" :to="r.to"
          class="flex items-center gap-3 px-4 py-2.5 border-b border-white/[0.05] last:border-0
                 hover:bg-white/[0.04] transition-colors">
          <span class="text-base">{{ r.type === 'club' ? '🏢' : '🏟️' }}</span>
          <div class="min-w-0">
            <div class="text-sm font-semibold text-slate-100 truncate">{{ r.name }}</div>
            <div class="text-[10px] text-slate-500">{{ r.type === 'club' ? 'Club' : 'Facility' }} · {{ r.sub }}</div>
          </div>
        </RouterLink>
      </div>
    </div>
  </div>

  <!-- ── Emirate filter chips ── -->
  <div class="flex gap-1.5 overflow-x-auto pb-2 mb-5 scrollbar-none">
    <button v-for="e in ['', ...EMIRATES]" :key="e"
      class="shrink-0 text-[10px] font-semibold px-2.5 py-1 rounded-full border transition-all duration-200"
      :class="emirateFilter === e
        ? 'bg-cyan-500/20 border-cyan-500/50 text-cyan-400'
        : 'border-white/10 text-slate-500 hover:border-white/25'"
      @click="emirateFilter = e">
      {{ e || '🇦🇪 All UAE' }}
    </button>
  </div>

  <!-- ── My Clubs (logged-in users) ── -->
  <template v-if="user && clubs.length">
    <div class="mb-5 fade-up">
      <div class="flex items-center justify-between mb-3">
        <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400">My Teams</h2>
        <RouterLink to="/dashboard" class="text-xs text-neon hover:opacity-75 transition">
          View Rankings →
        </RouterLink>
      </div>
      <div class="grid gap-2" :class="clubs.length > 1 ? 'grid-cols-2' : 'grid-cols-1'">
        <button v-for="c in clubs" :key="c.club_id"
          class="card p-3.5 text-left transition-all duration-200 hover:border-white/20"
          :class="currentClub?.club_id === c.club_id ? 'card-neon' : ''"
          @click="switchMyClub(c.club_id)">
          <div class="flex items-center gap-2.5 mb-2">
            <div class="w-8 h-8 rounded-xl flex items-center justify-center text-xs font-black text-slate-950 shrink-0"
              style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
              {{ (c.clubs?.name ?? '?').slice(0, 2).toUpperCase() }}
            </div>
            <div class="min-w-0">
              <div class="text-sm font-bold text-slate-100 truncate">{{ c.clubs?.name }}</div>
              <div class="text-[10px] text-slate-500 capitalize">{{ c.role }}</div>
            </div>
          </div>
          <!-- Club score from top clubs data -->
          <div v-if="topClubs.find(tc => tc.id === c.club_id)" class="flex gap-3">
            <span class="text-[10px] text-neon font-bold">
              Score {{ topClubs.find(tc => tc.id === c.club_id)?.club_score ?? '–' }}
            </span>
            <span class="text-[10px] text-slate-500">
              Rank #{{ topClubs.find(tc => tc.id === c.club_id)?.club_rank ?? '–' }}
            </span>
          </div>
        </button>
      </div>
    </div>
  </template>

  <!-- ── Not logged in CTA ── -->
  <div v-else-if="!user" class="card-neon p-5 mb-5 fade-up">
    <div class="text-center">
      <div class="text-3xl mb-2" style="filter:drop-shadow(0 0 16px rgba(0,229,255,.5))">🏸</div>
      <p class="font-bold gradient-text text-lg mb-1">Join your UAE badminton team</p>
      <p class="text-slate-400 text-sm mb-4">Free Elo rankings, match history, and club stats for every court.</p>
      <RouterLink to="/login" class="btn-primary px-8">Sign in with Google — Free</RouterLink>
    </div>
  </div>

  <!-- ── Top Clubs ── -->
  <div class="mb-5 fade-up">
    <div class="flex items-center justify-between mb-3">
      <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400">Top Clubs</h2>
      <RouterLink to="/explore" class="text-xs text-neon hover:opacity-75 transition">See All →</RouterLink>
    </div>

    <div v-if="loading" class="grid grid-cols-2 gap-2">
      <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!filteredClubs.length" class="card p-6 text-center text-slate-500 text-sm">
      No clubs yet.
    </div>

    <div v-else class="grid grid-cols-2 gap-2">
      <RouterLink v-for="(c, i) in filteredClubs" :key="c.id" :to="'/club/' + c.id"
        class="card p-3 transition-all duration-200 hover:border-white/20"
        :class="myClubsWithScore.some(m => m.id === c.id) ? 'card-neon' : ''">
        <div class="flex items-start justify-between mb-1">
          <span class="text-sm font-black" :class="i < 3 ? 'text-gold' : 'text-slate-500'">
            {{ ['🥇','🥈','🥉'][i] ?? ('#' + (i+1)) }}
          </span>
          <span v-if="c.emirates" class="text-[9px] text-slate-600">{{ c.emirates }}</span>
        </div>
        <div class="text-xs font-bold text-slate-100 truncate mb-1">{{ c.name }}</div>
        <div class="flex items-center gap-2">
          <span class="text-[10px] text-neon font-bold">{{ c.club_score }}</span>
          <span class="text-[10px] text-slate-600">{{ c.total_members }}👥</span>
        </div>
      </RouterLink>
    </div>
  </div>

  <!-- ── Top Players ── -->
  <div class="mb-5 fade-up">
    <div class="flex items-center justify-between mb-3">
      <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400">Top Players</h2>
      <RouterLink to="/explore" class="text-xs text-neon hover:opacity-75 transition">See All →</RouterLink>
    </div>

    <div v-if="loading" class="space-y-2">
      <div v-for="i in 4" :key="i" class="h-11 shimmer rounded-xl" />
    </div>

    <div v-else class="card overflow-hidden">
      <RouterLink v-for="(p, i) in topPlayers" :key="p.player_id"
        :to="'/player/' + p.player_id"
        class="flex items-center gap-3 px-4 py-2.5 border-b border-white/[0.04] last:border-0
               hover:bg-white/[0.02] transition-colors">
        <span class="text-sm w-6 shrink-0 font-bold"
          :class="i < 3 ? 'text-gold' : 'text-slate-600'">
          {{ ['🥇','🥈','🥉'][i] ?? (i + 1) }}
        </span>
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold text-slate-100 truncate">{{ p.public_name }}</div>
          <div class="text-[10px] text-slate-500 truncate">{{ p.club_name }}{{ p.emirates ? ' · ' + p.emirates : '' }}</div>
        </div>
        <div class="text-right shrink-0">
          <div class="text-sm font-extrabold text-neon">{{ p.elo }}</div>
          <div class="text-[9px] text-slate-600">{{ p.win_pct }}%W</div>
        </div>
      </RouterLink>
    </div>
  </div>

  <!-- ── Explore CTA ── -->
  <div class="grid grid-cols-2 gap-2 mb-2 fade-up">
    <RouterLink to="/explore?tab=facilities"
      class="card p-4 flex flex-col items-center text-center hover:border-white/20 transition-all duration-200">
      <span class="text-2xl mb-1.5">🏟️</span>
      <div class="text-xs font-bold text-slate-200">Find a Facility</div>
      <div class="text-[10px] text-slate-500 mt-0.5">Courts near you</div>
    </RouterLink>
    <RouterLink to="/explore"
      class="card p-4 flex flex-col items-center text-center hover:border-white/20 transition-all duration-200">
      <span class="text-2xl mb-1.5">🌍</span>
      <div class="text-xs font-bold text-slate-200">Explore Clubs</div>
      <div class="text-[10px] text-slate-500 mt-0.5">Join a team</div>
    </RouterLink>
  </div>
</template>
