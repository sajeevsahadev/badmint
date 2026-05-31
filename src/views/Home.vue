<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import { useInstall } from '../composables/useInstall'

const router = useRouter()
const { user } = useAuth()
const { clubs, currentClub, selectClub } = useClub()
const { canInstall, isIOS, isInstalled, promptInstall } = useInstall()

const topClubs    = ref([])
const topPlayers  = ref([])
const searchQ     = ref('')
const searchRes   = ref([])
const searching   = ref(false)
const emirateFilter = ref('')
const loading     = ref(true)

const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

const myClubsWithScore = computed(() =>
  topClubs.value.filter(c => clubs.value.some(m => m.club_id === c.id))
)

const filteredClubs = computed(() => {
  let list = topClubs.value
  if (emirateFilter.value) list = list.filter(c => c.emirates === emirateFilter.value)
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
  <div class="min-h-screen">

    <!-- ── UAE Map Hero ── -->
    <div class="relative overflow-hidden" style="min-height:270px">

      <!-- Base gradient -->
      <div class="absolute inset-0"
        style="background:linear-gradient(160deg,#03081a 0%,#06112a 35%,#071a18 65%,#08150a 100%);" />

      <!-- UAE Map SVG -->
      <svg class="absolute inset-0 w-full h-full" viewBox="0 0 380 210"
           preserveAspectRatio="xMidYMid slice" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">

        <!-- Persian Gulf water shading -->
        <path d="M0,0 L380,0 L380,75 L328,38 L258,80 L160,100 L40,118 L0,130 Z"
              fill="rgba(0,229,255,0.035)"/>
        <line x1="0" y1="25" x2="350" y2="5"  stroke="rgba(0,229,255,0.05)" stroke-width="0.5"/>
        <line x1="0" y1="50" x2="310" y2="22" stroke="rgba(0,229,255,0.04)" stroke-width="0.5"/>
        <line x1="0" y1="75" x2="260" y2="48" stroke="rgba(0,229,255,0.03)" stroke-width="0.5"/>

        <!-- Main UAE body (coast → Oman border → Saudi border → back) -->
        <path d="M40,118 L95,105 L160,100 L222,96 L258,80 L271,72 L278,66 L281,64 L288,58 L313,48 L328,38
                 L338,43 L316,60 L303,80 L295,105 L283,128 L264,162 L220,162 L125,162 L62,170 L40,140 Z"
              fill="rgba(0,229,255,0.07)" stroke="rgba(0,229,255,0.45)" stroke-width="1.5"
              stroke-linejoin="round"/>

        <!-- Fujairah exclave (Indian Ocean coast, separated by Oman) -->
        <path d="M330,62 L350,69 L357,82 L349,92 L334,88 L318,80 L316,66 Z"
              fill="rgba(0,229,255,0.05)" stroke="rgba(0,229,255,0.28)" stroke-width="1"
              stroke-linejoin="round"/>

        <!-- Subtle grid over UAE territory -->
        <clipPath id="uaeClip">
          <path d="M40,118 L95,105 L160,100 L222,96 L258,80 L271,72 L278,66 L281,64 L288,58 L313,48 L328,38
                   L338,43 L316,60 L303,80 L295,105 L283,128 L264,162 L220,162 L125,162 L62,170 L40,140 Z"/>
        </clipPath>
        <g clip-path="url(#uaeClip)" opacity="0.06">
          <line x1="0" y1="120" x2="400" y2="120" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="0" y1="140" x2="400" y2="140" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="0" y1="160" x2="400" y2="160" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="120" y1="0" x2="120" y2="200" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="200" y1="0" x2="200" y2="200" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="280" y1="0" x2="280" y2="200" stroke="#00e5ff" stroke-width="0.5"/>
        </g>

        <!-- ── Emirate dots ── -->
        <!-- Abu Dhabi (capital — larger dot with pulse ring) -->
        <circle cx="205" cy="132" r="9" fill="rgba(0,229,255,0.1)" opacity="0.6"/>
        <circle cx="205" cy="132" r="5" fill="rgba(0,229,255,0.2)" stroke="#00e5ff" stroke-width="1.8"/>

        <!-- Dubai -->
        <circle cx="271" cy="72" r="4" fill="rgba(0,229,255,0.15)" stroke="#00e5ff" stroke-width="1.5"/>

        <!-- Sharjah -->
        <circle cx="278" cy="66" r="3" fill="rgba(168,85,247,0.2)" stroke="#a855f7" stroke-width="1.5"/>

        <!-- Ajman (tiny) -->
        <circle cx="283" cy="61" r="2" fill="rgba(251,191,36,0.3)" stroke="#fbbf24" stroke-width="1"/>

        <!-- UAQ -->
        <circle cx="290" cy="56" r="2.5" fill="rgba(251,191,36,0.2)" stroke="#fbbf24" stroke-width="1"/>

        <!-- RAK -->
        <circle cx="313" cy="48" r="3.5" fill="rgba(168,85,247,0.15)" stroke="#a855f7" stroke-width="1.5"/>

        <!-- Fujairah -->
        <circle cx="336" cy="77" r="3" fill="rgba(0,229,255,0.15)" stroke="#00e5ff" stroke-width="1.5"/>

        <!-- ── Labels ── -->
        <text x="205" y="148" text-anchor="middle" fill="rgba(0,229,255,0.8)"
              font-size="7.5" font-weight="bold" font-family="system-ui,sans-serif">Abu Dhabi ★</text>
        <text x="266" y="64" text-anchor="end" fill="rgba(0,229,255,0.75)"
              font-size="7" font-family="system-ui,sans-serif">Dubai</text>
        <text x="270" y="57" text-anchor="end" fill="rgba(168,85,247,0.7)"
              font-size="6" font-family="system-ui,sans-serif">SHJ</text>
        <text x="315" y="40" text-anchor="middle" fill="rgba(168,85,247,0.7)"
              font-size="6" font-family="system-ui,sans-serif">RAK</text>
        <text x="359" y="76" text-anchor="start" fill="rgba(0,229,255,0.65)"
              font-size="6" font-family="system-ui,sans-serif">FUJ</text>

        <!-- Water / neighbour labels -->
        <text x="65" y="55" fill="rgba(0,229,255,0.18)" font-size="9"
              font-family="system-ui,sans-serif" font-style="italic">Persian Gulf</text>
        <text x="145" y="195" fill="rgba(255,255,255,0.09)" font-size="7.5" text-anchor="middle"
              font-family="system-ui,sans-serif" font-style="italic">Saudi Arabia</text>
        <text x="360" y="148" fill="rgba(255,255,255,0.09)" font-size="7"
              font-family="system-ui,sans-serif" font-style="italic">Oman</text>
      </svg>

      <!-- UAE flag accent strip -->
      <div class="absolute top-0 right-0 bottom-0 w-1.5"
        style="background:linear-gradient(to bottom,#00732f 33%,#fff 33%,#fff 66%,#ff0000 66%);"/>

      <!-- Faint dot grid overlay -->
      <div class="absolute inset-0 opacity-[0.025]"
        style="background-image:radial-gradient(circle,rgba(0,229,255,.8) 1px,transparent 1px);
               background-size:24px 24px;"/>

      <!-- Glow orbs -->
      <div class="absolute top-4 right-12 w-32 h-32 rounded-full opacity-[0.12]"
        style="background:radial-gradient(circle,#00e5ff,transparent);"/>
      <div class="absolute bottom-2 left-6 w-24 h-24 rounded-full opacity-[0.08]"
        style="background:radial-gradient(circle,#fbbf24,transparent);"/>

      <!-- Hero text + search (overlaid on map) -->
      <div class="relative px-4 pt-5 pb-7 mx-auto max-w-2xl">
        <div class="flex items-center gap-2.5 mb-0.5">
          <span class="text-3xl" style="filter:drop-shadow(0 0 14px rgba(0,229,255,.7))">🏸</span>
          <div>
            <h1 class="font-display text-3xl font-extrabold gradient-text leading-none">Badmint</h1>
            <p class="text-[10px] text-slate-500 tracking-[0.2em] uppercase mt-0.5">UAE Badminton Rankings</p>
          </div>
        </div>
        <p class="text-slate-400 text-xs mb-4 mt-2">All 7 Emirates · Elo Rankings · Free Forever 🇦🇪</p>

        <!-- Search -->
        <div class="relative">
          <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 text-sm">🔍</span>
          <input v-model="searchQ" class="input pl-10 bg-white/[0.08]"
            placeholder="Search clubs or facilities…"
            @input="doSearch" @keyup.enter="doSearch"/>
        </div>

        <!-- Search results -->
        <div v-if="searchRes.length" class="card mt-1 overflow-hidden relative z-10">
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

    <!-- ── Page content ── -->
    <div class="px-4 mx-auto max-w-2xl pb-10">

      <!-- Emirate filter chips -->
      <div class="flex gap-1.5 overflow-x-auto pb-2 my-5 scrollbar-none">
        <button v-for="e in ['', ...EMIRATES]" :key="e"
          class="shrink-0 text-[10px] font-semibold px-2.5 py-1 rounded-full border transition-all duration-200"
          :class="emirateFilter === e
            ? 'bg-cyan-500/20 border-cyan-500/50 text-cyan-400'
            : 'border-white/10 text-slate-500 hover:border-white/25'"
          @click="emirateFilter = e">
          {{ e || '🇦🇪 All UAE' }}
        </button>
      </div>

      <!-- ── My Teams (logged-in) ── -->
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

      <!-- ── Install App (hidden once installed) ── -->
      <div v-if="!isInstalled" class="mb-5 fade-up">
        <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400 mb-3">
          📲 Get the App — Free, No App Store
        </h2>
        <div class="grid grid-cols-2 gap-2">

          <!-- Android -->
          <div class="card p-4 flex flex-col gap-2.5" :class="canInstall ? 'card-neon' : ''">
            <div class="flex items-center gap-2">
              <span class="text-xl">🤖</span>
              <div class="text-xs font-bold text-slate-100">Android</div>
            </div>
            <p class="text-[10px] text-slate-400 leading-relaxed flex-1">
              Works offline · No Play Store · Installs from Chrome
            </p>
            <button v-if="canInstall"
              class="btn-primary text-xs py-2 w-full" @click="promptInstall">
              Install Now
            </button>
            <p v-else class="text-[10px] text-slate-500">
              Open in Chrome on Android to install
            </p>
          </div>

          <!-- iPhone / iPad -->
          <div class="card p-4 flex flex-col gap-2.5" :class="isIOS ? 'card-violet' : ''">
            <div class="flex items-center gap-2">
              <span class="text-xl">🍎</span>
              <div class="text-xs font-bold text-slate-100">iPhone / iPad</div>
            </div>
            <ol class="text-[10px] text-slate-400 space-y-1.5 leading-relaxed flex-1">
              <li class="flex items-start gap-1.5">
                <span class="w-4 h-4 rounded-full bg-white/10 flex items-center justify-center text-[9px] font-bold shrink-0 mt-0.5">1</span>
                Tap <strong class="text-slate-300 mx-0.5">Share ↑</strong> in Safari
              </li>
              <li class="flex items-start gap-1.5">
                <span class="w-4 h-4 rounded-full bg-white/10 flex items-center justify-center text-[9px] font-bold shrink-0 mt-0.5">2</span>
                <span>Tap <strong class="text-slate-300">"Add to Home Screen"</strong></span>
              </li>
              <li class="flex items-start gap-1.5">
                <span class="w-4 h-4 rounded-full bg-white/10 flex items-center justify-center text-[9px] font-bold shrink-0 mt-0.5">3</span>
                Tap <strong class="text-slate-300 mx-0.5">Add</strong> to confirm
              </li>
            </ol>
          </div>

        </div>
      </div>

      <!-- ── Top Clubs ── -->
      <div class="mb-5 fade-up">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400">Top Clubs</h2>
          <RouterLink to="/explore" class="text-xs text-neon hover:opacity-75 transition">See All →</RouterLink>
        </div>
        <div v-if="loading" class="grid grid-cols-2 gap-2">
          <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl"/>
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
          <div v-for="i in 4" :key="i" class="h-11 shimmer rounded-xl"/>
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
            <div class="flex-1 min-w-0 ml-2">
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

      <!-- ── Explore CTAs ── -->
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

    </div>
  </div>
</template>
