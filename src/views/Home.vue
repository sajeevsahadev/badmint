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
const showIOSGuide = ref(false)

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

      <!-- UAE Map SVG
           Coordinate system: viewBox 0 0 420 220
           x = (longitude − 51°E) × 70   [range 51–57°E → 0–420]
           y = (27°N − latitude)  × 44   [range 27–22°N → 0–220]
           Points derived from official UAE boundary coordinates. -->
      <svg class="absolute inset-0 w-full h-full" viewBox="0 0 420 220"
           preserveAspectRatio="xMidYMid slice" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">

        <!-- Persian Gulf water fill (above the coast) -->
        <path d="M0,0 L420,0 L420,50 L364,40 L347,54 L318,64 L310,70 L307,73 L298,80
                 L290,87 L273,95 L238,111 L196,125 L147,130 L112,124 L42,128 L0,128 Z"
              fill="rgba(0,229,255,0.04)"/>
        <!-- Gulf wave lines -->
        <line x1="0" y1="22" x2="380" y2="4"  stroke="rgba(0,229,255,0.05)" stroke-width="0.5"/>
        <line x1="0" y1="50" x2="340" y2="25" stroke="rgba(0,229,255,0.04)" stroke-width="0.5"/>
        <line x1="0" y1="80" x2="270" y2="55" stroke="rgba(0,229,255,0.03)" stroke-width="0.5"/>

        <!-- ═══ MAIN UAE BODY ═══
             Gulf coast: Qatar border → RAK northern tip
             Oman border: east/south through Hajar mountains → Saudi junction
             Saudi border: west back to Qatar/UAE corner -->
        <path d="
          M42,128
          L112,124 L147,130 L196,125 L238,111
          L273,95 L290,87 L298,80 L307,73 L310,70 L318,64
          L347,54 L364,40
          L374,45 L376,65 L372,73
          L362,89 L344,97 L336,108 L335,119 L337,128
          L327,140 L317,150 L306,163 L292,176
          L240,189 L133,191 L63,187 L42,171
          Z"
          fill="rgba(0,229,255,0.08)" stroke="rgba(0,229,255,0.5)" stroke-width="1.5"
          stroke-linejoin="round"/>

        <!-- ═══ FUJAIRAH ═══
             Separate coastal strip on the Gulf of Oman (east) side.
             Oman territory lies between it and the main UAE body. -->
        <path d="M372,73 L393,71 L396,77 L395,84 L386,89 L371,89 L364,86 L365,80 Z"
              fill="rgba(0,229,255,0.06)" stroke="rgba(0,229,255,0.32)" stroke-width="1.2"
              stroke-linejoin="round"/>

        <!-- Subtle territory grid clipped to UAE shape -->
        <clipPath id="uaeClip">
          <path d="M42,128 L112,124 L147,130 L196,125 L238,111 L273,95 L290,87
                   L298,80 L307,73 L310,70 L318,64 L347,54 L364,40
                   L374,45 L376,65 L372,73 L362,89 L344,97 L336,108
                   L335,119 L337,128 L327,140 L317,150 L306,163 L292,176
                   L240,189 L133,191 L63,187 L42,171 Z"/>
        </clipPath>
        <g clip-path="url(#uaeClip)" opacity="0.055">
          <line x1="0" y1="115" x2="420" y2="115" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="0" y1="135" x2="420" y2="135" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="0" y1="155" x2="420" y2="155" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="0" y1="175" x2="420" y2="175" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="130" y1="0" x2="130" y2="220" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="210" y1="0" x2="210" y2="220" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="290" y1="0" x2="290" y2="220" stroke="#00e5ff" stroke-width="0.5"/>
          <line x1="360" y1="0" x2="360" y2="220" stroke="#00e5ff" stroke-width="0.5"/>
        </g>

        <!-- ── Emirate capital dots ── -->
        <!-- Abu Dhabi (capital ★) — pulse ring -->
        <circle cx="228" cy="116" r="10" fill="rgba(0,229,255,0.08)"/>
        <circle cx="228" cy="116" r="5"  fill="rgba(0,229,255,0.2)" stroke="#00e5ff" stroke-width="1.8"/>

        <!-- Dubai -->
        <circle cx="298" cy="80" r="4"   fill="rgba(0,229,255,0.15)" stroke="#00e5ff" stroke-width="1.5"/>

        <!-- Sharjah -->
        <circle cx="307" cy="73" r="3"   fill="rgba(168,85,247,0.2)" stroke="#a855f7" stroke-width="1.5"/>

        <!-- Ajman -->
        <circle cx="310" cy="70" r="2"   fill="rgba(251,191,36,0.3)" stroke="#fbbf24" stroke-width="1"/>

        <!-- Umm Al Quwain -->
        <circle cx="318" cy="64" r="2.5" fill="rgba(251,191,36,0.2)" stroke="#fbbf24" stroke-width="1"/>

        <!-- Ras Al Khaimah -->
        <circle cx="347" cy="54" r="3.5" fill="rgba(168,85,247,0.15)" stroke="#a855f7" stroke-width="1.5"/>

        <!-- Fujairah -->
        <circle cx="383" cy="79" r="3"   fill="rgba(0,229,255,0.15)" stroke="#00e5ff" stroke-width="1.5"/>

        <!-- ── Labels ── -->
        <text x="200" y="145" text-anchor="middle" fill="rgba(0,229,255,0.85)"
              font-size="7.5" font-weight="bold" font-family="system-ui,sans-serif">Abu Dhabi ★</text>
        <text x="292" y="73"  text-anchor="end"    fill="rgba(0,229,255,0.75)"
              font-size="7"   font-family="system-ui,sans-serif">Dubai</text>
        <text x="300" y="66"  text-anchor="end"    fill="rgba(168,85,247,0.7)"
              font-size="6"   font-family="system-ui,sans-serif">SHJ</text>
        <text x="349" y="46"  text-anchor="middle" fill="rgba(168,85,247,0.7)"
              font-size="6"   font-family="system-ui,sans-serif">RAK</text>
        <text x="398" y="79"  text-anchor="start"  fill="rgba(0,229,255,0.65)"
              font-size="6"   font-family="system-ui,sans-serif">FUJ</text>

        <!-- Neighbour / water labels -->
        <text x="62"  y="55"  fill="rgba(0,229,255,0.18)" font-size="9"
              font-family="system-ui,sans-serif" font-style="italic">Persian Gulf</text>
        <text x="155" y="207" fill="rgba(255,255,255,0.09)" font-size="7.5" text-anchor="middle"
              font-family="system-ui,sans-serif" font-style="italic">Saudi Arabia</text>
        <text x="405" y="145" fill="rgba(255,255,255,0.08)" font-size="7"
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
        <p class="text-slate-400 text-xs mb-4 mt-2">All 7 Emirates · Elo Rankings 🇦🇪</p>

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
          📲 Get the App — No App Store Needed
        </h2>
        <div class="grid grid-cols-2 gap-2">

          <!-- Android: whole card is the install button -->
          <button v-if="canInstall"
            class="card card-neon p-4 flex flex-col gap-2.5 text-left w-full
                   hover:border-cyan-400/40 active:scale-[0.98] transition-all duration-150"
            @click="promptInstall">
            <div class="flex items-center justify-between">
              <span class="text-2xl">🤖</span>
              <span class="text-[9px] text-neon font-bold uppercase tracking-wide">Tap to Install</span>
            </div>
            <div class="text-xs font-bold text-slate-100">Android</div>
            <p class="text-[10px] text-slate-400 leading-relaxed">
              Works offline · No Play Store needed
            </p>
            <div class="btn-primary text-xs py-1.5 text-center rounded-xl mt-auto">
              Install Now →
            </div>
          </button>

          <!-- Android: informational when prompt not ready -->
          <div v-else class="card p-4 flex flex-col gap-2.5 opacity-70">
            <span class="text-2xl">🤖</span>
            <div class="text-xs font-bold text-slate-100">Android</div>
            <p class="text-[10px] text-slate-400 leading-relaxed">
              Open this page in <strong class="text-slate-300">Chrome</strong> on Android, then tap Install.
            </p>
          </div>

          <!-- iPhone / iPad: tapping opens the step-by-step guide -->
          <button class="card p-4 flex flex-col gap-2.5 text-left w-full
                         hover:border-violet-400/40 active:scale-[0.98] transition-all duration-150"
            :class="isIOS ? 'card-violet' : 'opacity-70'"
            @click="showIOSGuide = true">
            <div class="flex items-center justify-between">
              <span class="text-2xl">🍎</span>
              <span class="text-[9px] text-violet font-bold uppercase tracking-wide">Tap for Guide</span>
            </div>
            <div class="text-xs font-bold text-slate-100">iPhone / iPad</div>
            <p class="text-[10px] text-slate-400 leading-relaxed">
              Add via Safari's Share menu — no App Store needed.
            </p>
            <div class="text-[10px] text-center text-violet py-1.5 border border-violet/30
                        rounded-xl mt-auto bg-violet/5">
              Show me how →
            </div>
          </button>

        </div>
      </div>

      <!-- ── iOS Install Guide (bottom sheet) ── -->
      <Teleport to="body">
        <div v-if="showIOSGuide"
          class="fixed inset-0 z-50 flex items-end"
          style="background:rgba(0,0,0,.6); backdrop-filter:blur(4px)"
          @click.self="showIOSGuide = false">
          <div class="w-full rounded-t-3xl px-6 pt-6 pb-10"
            style="background:#0d1a2e; border-top:1px solid rgba(168,85,247,.3);
                   box-shadow:0 -8px 40px rgba(168,85,247,.15);">

            <!-- Handle bar -->
            <div class="w-12 h-1 rounded-full bg-white/20 mx-auto mb-5"/>

            <div class="text-center mb-6">
              <div class="text-4xl mb-2" style="filter:drop-shadow(0 0 16px rgba(168,85,247,.5))">🍎</div>
              <h3 class="font-display text-lg font-bold text-slate-100">Add to iPhone / iPad</h3>
              <p class="text-[11px] text-slate-400 mt-1">Follow these 3 steps in Safari</p>
            </div>

            <div class="space-y-4 mb-6">
              <!-- Step 1 -->
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-2xl shrink-0"
                  style="background:rgba(168,85,247,.15); border:1px solid rgba(168,85,247,.3)">
                  ↑
                </div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">Tap the Share button</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">
                    The <strong class="text-slate-300">↑</strong> icon at the bottom of Safari
                    (iPad: top-right toolbar)
                  </div>
                </div>
              </div>

              <!-- Step 2 -->
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-2xl shrink-0"
                  style="background:rgba(168,85,247,.15); border:1px solid rgba(168,85,247,.3)">
                  ➕
                </div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">"Add to Home Screen"</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">
                    Scroll down in the share sheet and tap this option
                  </div>
                </div>
              </div>

              <!-- Step 3 -->
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-2xl shrink-0"
                  style="background:rgba(0,229,255,.1); border:1px solid rgba(0,229,255,.3)">
                  ✓
                </div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">Tap Add</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">
                    Badmint appears on your home screen — tap it to open the app
                  </div>
                </div>
              </div>
            </div>

            <button class="btn-ghost w-full py-3 text-sm" @click="showIOSGuide = false">
              Got it — close
            </button>
          </div>
        </div>
      </Teleport>

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
