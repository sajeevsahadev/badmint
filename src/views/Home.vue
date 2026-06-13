<script setup>
import { ref, computed, onMounted } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import { useInstall } from '../composables/useInstall'
import { useGeo } from '../composables/useGeo'

const router = useRouter()
const { user } = useAuth()
const { clubs, currentClub, selectClub } = useClub()
const { canInstall, isIOS, isInstalled, promptInstall } = useInstall()
const { country, countryCode, flagEmoji, detectCountry } = useGeo()
const showIOSGuide     = ref(false)
const showAndroidGuide = ref(false)

const topClubs    = ref([])
const topPlayers  = ref([])
const searchQ     = ref('')
const searchRes   = ref([])
const searching   = ref(false)
const loading     = ref(true)

const myClubsWithScore = computed(() =>
  topClubs.value.filter(c => clubs.value.some(m => m.club_id === c.id))
)

const filteredClubs = computed(() =>
  [...topClubs.value].sort((a, b) => {
    const aOwn = myClubsWithScore.value.some(m => m.id === a.id) ? 1 : 0
    const bOwn = myClubsWithScore.value.some(m => m.id === b.id) ? 1 : 0
    return bOwn - aOwn || (a.club_rank ?? 999) - (b.club_rank ?? 999)
  }).slice(0, 6)
)

// The story a visitor scrolls through before signing in.
// Every chapter is a tap-target that leads to Google sign-in.
const story = [
  {
    icon: '🏟️',
    chapter: 'Saturday, 5:58 AM',
    title: 'The court is booked. Who\'s in?',
    text: 'Your badminton crew has a court every weekend — but the roster lives in one person\'s head. With Badminton 360, your club exists in one place. Add every member, invite by link, all free. Forever.',
    tag: 'Free club management',
  },
  {
    icon: '🏸',
    chapter: 'Game on',
    title: 'Every smash is remembered',
    text: 'Pick 4 players, enter the score, done. The app rates every player with the same Elo system chess grandmasters use — beat a stronger pair, climb faster. The leaderboard settles every "I\'m better than you" debate.',
    tag: 'Match tracking & Elo rankings',
  },
  {
    icon: '💸',
    chapter: 'After the game',
    title: 'Split the bill, not the friendship',
    text: 'Court fee, shuttlecocks, water — someone always pays and someone always forgets. PaySplits divides every cost equally, and the shared Wallet lets players chip in upfront so nobody chases anybody.',
    tag: 'Expense splitting & wallet',
  },
  {
    icon: '📅',
    chapter: 'The next challenge',
    title: 'Tournaments are waiting for you',
    text: 'Browse upcoming tournaments around you, register your pair in two taps, and follow the bracket live from your phone.',
    tag: 'Discover tournaments',
  },
  {
    icon: '🏆',
    chapter: 'Your big day',
    title: 'Run your own tournament',
    text: 'Knockouts or round robin — create a tournament, approve registrations, auto-generate the bracket and record results as they happen. Your club\'s championship, organised like a pro event.',
    tag: 'Host tournaments',
  },
]

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
  if (c) { selectClub(c); router.push('/club/' + clubId) }
}

function goLogin() { router.push('/login') }

onMounted(() => { load(); detectCountry() })
</script>

<template>
  <div class="min-h-screen">

    <!-- ── Global Hero (Professional Sport) ── -->
    <div class="relative overflow-hidden" style="min-height:256px">

      <!-- Professional sport blue gradient — bold, not black -->
      <div class="absolute inset-0"
        style="background:linear-gradient(150deg,#0B2D6B 0%,#0D47A1 45%,#006064 100%)" />

      <!-- Diagonal stripe texture (sport jersey feel) -->
      <div class="absolute inset-0"
        style="background-image:repeating-linear-gradient(-55deg,rgba(255,255,255,.055) 0,rgba(255,255,255,.055) 1px,transparent 0,transparent 50%);background-size:20px 20px" />

      <!-- Glow accents -->
      <div class="absolute top-0 right-0 w-64 h-64 rounded-full pointer-events-none"
        style="background:radial-gradient(circle,rgba(0,229,255,.22),transparent);transform:translate(35%,-35%)"/>
      <div class="absolute bottom-0 left-0 w-48 h-48 rounded-full pointer-events-none"
        style="background:radial-gradient(circle,rgba(168,85,247,.15),transparent);transform:translate(-30%,30%)"/>

      <!-- Hero text + search -->
      <div class="relative px-4 pt-6 pb-7 mx-auto max-w-2xl">
        <div class="flex items-center gap-2.5 mb-0.5">
          <span class="text-3xl" style="filter:drop-shadow(0 0 18px rgba(255,255,255,.35))">🏸</span>
          <div>
            <h1 class="font-display text-3xl font-extrabold gradient-text leading-none">Badminton 360</h1>
            <p class="text-xs text-white/50 tracking-[0.2em] uppercase mt-0.5">Your Club · Your Game · One App</p>
          </div>
        </div>
        <p class="text-white/70 text-xs mb-4 mt-2">
          {{ country ? flagEmoji(countryCode) + ' ' + country : '🌍 Worldwide' }} · Elo Rankings · Free Forever
        </p>

        <!-- Search — glass style for colored hero -->
        <div class="relative">
          <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-white/50 pointer-events-none select-none">🔍</span>
          <input v-model="searchQ"
            class="w-full rounded-xl py-3 pl-11 pr-4 text-sm text-white outline-none transition-all focus:ring-2 focus:ring-white/30"
            style="background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.25);backdrop-filter:blur(6px)"
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
              <div class="text-xs text-slate-500">{{ r.type === 'club' ? 'Club' : 'Facility' }}{{ r.sub ? ' · ' + r.sub : '' }}</div>
            </div>
          </RouterLink>
        </div>
      </div>
    </div>

    <!-- ── Page content ── -->
    <div class="px-4 mx-auto max-w-2xl pb-10 pt-5">

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

      <!-- ══════════════ LOGGED-OUT LANDING ══════════════ -->
      <template v-if="!user">

        <!-- 1. Join CTA -->
        <div class="card-neon p-5 mb-8 fade-up">
          <div class="text-center">
            <div class="text-3xl mb-2" style="filter:drop-shadow(0 0 16px rgba(0,229,255,.5))">🏸</div>
            <p class="font-bold gradient-text text-lg mb-1">Join your badminton team</p>
            <p class="text-slate-400 text-sm mb-4">Free Elo rankings, match history, and club stats for every court — anywhere in the world.</p>
            <RouterLink to="/login" class="btn-primary px-8">Sign in with Google — Free</RouterLink>
          </div>
        </div>

        <!-- 2. The Story -->
        <div class="mb-8">
          <div class="text-center mb-6 fade-up">
            <h2 class="font-display text-xl font-extrabold text-slate-100">
              Every great club has the same problems.
            </h2>
            <p class="text-sm gradient-text font-bold mt-1">Badminton 360 solves all of them.</p>
          </div>

          <div class="relative">
            <!-- Vertical story line -->
            <div class="absolute left-[22px] top-6 bottom-6 w-px"
              style="background:linear-gradient(180deg,rgba(0,229,255,.4),rgba(168,85,247,.4),rgba(251,191,36,.4))" aria-hidden="true"/>

            <button v-for="(s, i) in story" :key="i"
              class="relative w-full text-left flex gap-4 mb-4 group fade-up"
              @click="goLogin">
              <!-- Node -->
              <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shrink-0 z-10
                          transition-transform duration-200 group-hover:scale-110"
                style="background:rgba(13,26,46,.95); border:1px solid rgba(0,229,255,.3);
                       box-shadow:0 0 18px rgba(0,229,255,.12)">
                {{ s.icon }}
              </div>
              <!-- Card -->
              <div class="card flex-1 p-4 transition-all duration-200
                          group-hover:border-cyan-400/40 group-active:scale-[0.99]">
                <div class="text-[9px] font-bold uppercase tracking-[0.18em] text-slate-500 mb-1">{{ s.chapter }}</div>
                <div class="text-sm font-bold text-slate-100 mb-1.5">{{ s.title }}</div>
                <p class="text-xs text-slate-400 leading-relaxed mb-2.5">{{ s.text }}</p>
                <div class="flex items-center justify-between">
                  <span class="text-[9px] font-bold uppercase tracking-wide px-2 py-0.5 rounded-full"
                    style="background:rgba(0,229,255,.1); color:#00e5ff; border:1px solid rgba(0,229,255,.25)">
                    {{ s.tag }}
                  </span>
                  <span class="text-[10px] text-neon opacity-0 group-hover:opacity-100 transition-opacity">
                    Start free →
                  </span>
                </div>
              </div>
            </button>
          </div>

          <!-- Story finale CTA -->
          <div class="card-violet p-5 text-center mt-6 fade-up">
            <p class="font-display font-extrabold text-slate-100 text-base mb-1">
              The whole game. The whole club. One app. 360°.
            </p>
            <p class="text-xs text-slate-400 mb-4">No downloads, no fees, no spreadsheets. Just badminton.</p>
            <RouterLink to="/login" class="btn-primary px-8">Get Started — It's Free</RouterLink>
          </div>
        </div>
      </template>

      <!-- ══════════════ LOGGED-IN CONTENT ══════════════ -->
      <template v-if="user">
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
        <div class="grid grid-cols-2 gap-2 mb-5 fade-up">
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

      <!-- ── Install App — kept at the bottom (native iOS/Android apps coming soon) ── -->
      <div v-if="!isInstalled" class="mb-2 fade-up">
        <h2 class="text-xs font-bold uppercase tracking-widest text-slate-400 mb-3">
          📲 Get the App — No App Store Needed
        </h2>
        <div class="grid grid-cols-2 gap-2">

          <!-- Android: tapping either triggers native install (if ready) or opens guide -->
          <button
            class="card p-4 flex flex-col gap-2.5 text-left w-full
                   active:scale-[0.98] transition-all duration-150"
            :class="canInstall ? 'card-neon hover:border-cyan-400/40' : 'hover:border-white/20'"
            @click="canInstall ? promptInstall() : (showAndroidGuide = true)">
            <div class="flex items-center justify-between">
              <span class="text-2xl">🤖</span>
              <span class="text-[9px] font-bold uppercase tracking-wide"
                :class="canInstall ? 'text-neon' : 'text-slate-500'">
                {{ canInstall ? 'Tap to Install' : 'Tap for Guide' }}
              </span>
            </div>
            <div class="text-xs font-bold text-slate-100">Android</div>
            <p class="text-[10px] text-slate-400 leading-relaxed flex-1">
              {{ canInstall ? 'Works offline · No Play Store needed' : 'Open in Chrome on Android to install' }}
            </p>
            <div class="text-xs text-center py-1.5 border rounded-xl mt-auto transition-colors"
              :class="canInstall
                ? 'btn-primary border-transparent'
                : 'border-white/15 text-slate-400 hover:text-neon hover:border-neon/30'">
              {{ canInstall ? 'Install Now →' : 'Show me how →' }}
            </div>
          </button>

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
        <p class="text-[10px] text-slate-600 text-center mt-2">
          Native iOS &amp; Android apps are on the way 🚀
        </p>
      </div>

      <!-- ── Android Install Guide ── -->
      <Teleport to="body">
        <div v-if="showAndroidGuide"
          class="fixed inset-0 z-50 flex items-end"
          style="background:rgba(0,0,0,.6); backdrop-filter:blur(4px)"
          @click.self="showAndroidGuide = false">
          <div class="w-full rounded-t-3xl px-6 pt-6 pb-10"
            style="background:#0d1a2e; border-top:1px solid rgba(0,229,255,.25);
                   box-shadow:0 -8px 40px rgba(0,229,255,.12);">
            <div class="w-12 h-1 rounded-full bg-white/20 mx-auto mb-5"/>
            <div class="text-center mb-6">
              <div class="text-4xl mb-2" style="filter:drop-shadow(0 0 16px rgba(0,229,255,.5))">🤖</div>
              <h3 class="font-display text-lg font-bold text-slate-100">Add to Android Home Screen</h3>
              <p class="text-[11px] text-slate-400 mt-1">Follow these steps in Chrome on Android</p>
            </div>
            <div class="space-y-3 mb-6">
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shrink-0"
                  style="background:rgba(0,229,255,.12); border:1px solid rgba(0,229,255,.25)">🌐</div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">Open in Chrome</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">Must be Chrome browser — not Samsung Internet or Firefox</div>
                </div>
              </div>
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shrink-0"
                  style="background:rgba(0,229,255,.12); border:1px solid rgba(0,229,255,.25)">⋮</div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">Tap ⋮ (three-dot menu)</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">Top-right corner of Chrome</div>
                </div>
              </div>
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shrink-0"
                  style="background:rgba(0,229,255,.12); border:1px solid rgba(0,229,255,.25)">➕</div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">"Add to Home screen"</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">Or "Install app" — scroll down in the menu to find it</div>
                </div>
              </div>
              <div class="flex items-center gap-4 card p-3.5">
                <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shrink-0"
                  style="background:rgba(0,229,255,.1); border:1px solid rgba(0,229,255,.25)">✓</div>
                <div>
                  <div class="text-sm font-semibold text-slate-100">Tap Add to confirm</div>
                  <div class="text-[11px] text-slate-400 mt-0.5">Badminton 360 appears on your home screen — tap to launch the app</div>
                </div>
              </div>
            </div>
            <button class="btn-ghost w-full py-3 text-sm" @click="showAndroidGuide = false">
              Got it — close
            </button>
          </div>
        </div>
      </Teleport>

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
                    Badminton 360 appears on your home screen — tap it to open the app
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

    </div>
  </div>
</template>
