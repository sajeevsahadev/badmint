<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterView, RouterLink } from 'vue-router'
import { supabase } from './lib/supabase'
import { useAuth } from './composables/useAuth'
import { useClub } from './composables/useClub'
import { useInstall } from './composables/useInstall'
import { useSession } from './composables/useSession'

const { user, ready, signOut } = useAuth()
const { clubs, currentClub, loadClubs, selectClub } = useClub()
const { canInstall, isIOS, isInstalled, promptInstall } = useInstall()
const { startSession, trackPage, endSession } = useSession()
const route  = useRoute()
const router = useRouter()

const pendingCount = ref(0)
const showIOSHint  = ref(false)

async function init() {
  if (!user.value) return
  try {
    await loadClubs()
    await refreshPending()
    await startSession()   // create session record on login
  } catch {}
}

async function refreshPending() {
  const managerIds = clubs.value
    .filter(c => ['owner','manager'].includes(c.role))
    .map(c => c.club_id)
  if (!managerIds.length) { pendingCount.value = 0; return }
  const { count } = await supabase
    .from('join_requests')
    .select('*', { count: 'exact', head: true })
    .in('club_id', managerIds)
    .eq('status', 'pending')
  pendingCount.value = count ?? 0
}

onMounted(init)
watch(user, init)
watch(() => route.path, (path) => {
  refreshPending()
  if (user.value) trackPage(path)   // log every screen navigation
})

async function logout() {
  await endSession()
  await signOut()
  router.push('/login')
}
function onSwitch(e) {
  const c = clubs.value.find(x => x.club_id === e.target.value)
  if (c) selectClub(c)
}

// Nav tabs — shown for all logged-in users on every page
const nav = computed(() => [
  { to: '/',          label: 'Home',     icon: '🏠' },
  { to: '/dashboard', label: 'Rankings', icon: '🏆' },
  { to: '/matches',   label: 'Matches',  icon: '📋' },
  { to: '/players',   label: 'Players',  icon: '👥' },
  { to: '/manage',    label: 'Manage',   icon: '⚙️', badge: pendingCount.value },
])

// Routes that don't need a club selected
const clubFreeRoutes = ['/manage', '/join', '/explore', '/profile']
const needsClub = computed(() =>
  !currentClub.value && !clubFreeRoutes.includes(route.path)
)
</script>

<template>
  <!-- Loading splash -->
  <div v-if="!ready" class="grid min-h-screen place-items-center">
    <div class="text-center">
      <div class="text-5xl mb-4" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.6));">🏸</div>
      <div class="text-neon font-semibold text-sm animate-pulse">Loading Badmint…</div>
    </div>
  </div>

  <template v-else>
    <!-- Public routes render full-screen; pad bottom for nav when logged in -->
    <div v-if="route.meta.public" :class="user ? 'pb-28' : ''">
      <RouterView />
    </div>

    <!-- Authenticated shell (top bar + content wrapper) -->
    <div v-else class="mx-auto max-w-2xl px-4 pb-28 pt-4">

      <!-- ── PWA Install banner ── -->
      <div v-if="canInstall && !isInstalled" class="card-neon mb-4 px-4 py-3 flex items-center gap-3 fade-up">
        <span class="text-2xl shrink-0">📲</span>
        <div class="flex-1 min-w-0">
          <div class="text-xs font-bold text-slate-200">Install Badmint on Android</div>
          <div class="text-[10px] text-slate-500">Works offline · No app store needed</div>
        </div>
        <button class="btn-primary text-xs px-3 py-1.5 shrink-0" @click="promptInstall">Install</button>
      </div>

      <div v-if="isIOS && !isInstalled && showIOSHint"
        class="card mb-4 px-4 py-3 fade-up" style="border-color:rgba(168,85,247,.3)">
        <div class="flex items-start gap-2">
          <span class="text-xl shrink-0">🍎</span>
          <div>
            <div class="text-xs font-bold text-slate-200 mb-1">Add to iPhone Home Screen</div>
            <div class="text-[11px] text-slate-400 leading-relaxed">
              Tap the <strong class="text-slate-300">Share</strong> button (↑) in Safari,
              then choose <strong class="text-slate-300">"Add to Home Screen"</strong>.
            </div>
          </div>
          <button class="text-slate-600 hover:text-slate-400 text-sm shrink-0 transition"
            @click="showIOSHint = false">✕</button>
        </div>
      </div>

      <!-- ── Top bar ── -->
      <header class="mb-5 flex items-center justify-between gap-3">
        <RouterLink to="/" class="flex items-center gap-2.5 hover:opacity-80 transition">
          <span class="text-2xl leading-none" style="filter:drop-shadow(0 0 12px rgba(0,229,255,.5));">🏸</span>
          <div>
            <h1 class="font-display text-xl font-extrabold tracking-tight leading-none gradient-text">Badmint</h1>
            <div class="text-[9px] text-slate-500 tracking-[0.2em] uppercase">UAE Badminton Rankings</div>
          </div>
        </RouterLink>

        <div class="flex items-center gap-2">
          <!-- iOS install hint trigger -->
          <button v-if="isIOS && !isInstalled && !showIOSHint"
            class="text-[10px] text-violet hover:opacity-80 transition px-1" @click="showIOSHint = true">
            📲 Install
          </button>

          <!-- Club switcher -->
          <select v-if="clubs.length" :value="currentClub?.club_id" @change="onSwitch"
            class="rounded-lg border border-white/10 bg-white/[0.05] px-2.5 py-1.5 text-xs
                   max-w-[120px] truncate text-slate-200 outline-none focus:border-cyan-500/40
                   transition-colors duration-200">
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id"
              class="bg-slate-900">{{ c.clubs?.name }}</option>
          </select>

          <!-- Profile link -->
          <RouterLink to="/profile" class="w-7 h-7 rounded-full flex items-center justify-center text-xs
            font-bold text-slate-950 shrink-0 hover:opacity-80 transition"
            style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
            {{ (user?.user_metadata?.full_name ?? user?.email ?? '?')[0].toUpperCase() }}
          </RouterLink>

          <button class="text-xs text-slate-500 hover:text-slate-200 transition"
            @click="logout">Sign out</button>
        </div>
      </header>

      <!-- ── No club state ── -->
      <div v-if="needsClub" class="card-neon p-8 text-center fade-up">
        <div class="text-4xl mb-4" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.4));">👋</div>
        <h2 class="font-display text-xl font-bold gradient-text mb-1">Welcome to Badmint!</h2>
        <p class="text-sm text-slate-400 mb-6">Join your team's club or create a new one to get started.</p>
        <div class="flex flex-col gap-3">
          <RouterLink to="/explore" class="btn-primary w-full py-3 text-sm">🌍 Browse &amp; Join a Club</RouterLink>
          <RouterLink to="/join"    class="btn-ghost  w-full py-3 text-sm">🔗 Have an Invite Link?</RouterLink>
          <RouterLink to="/manage"  class="btn-ghost  w-full py-3 text-sm">➕ Create My Own Club</RouterLink>
        </div>
      </div>

      <RouterView v-else />

    </div>

    <!-- ── Bottom nav: all logged-in users on every page ── -->
    <nav v-if="user && route.path !== '/login'"
      class="fixed inset-x-0 bottom-0 z-20 safe-area-pb"
      style="background:rgba(5,13,26,.96); border-top:1px solid rgba(255,255,255,.07); backdrop-filter:blur(20px);">
      <div class="absolute top-0 left-0 right-0 h-px"
        style="background:linear-gradient(90deg,transparent,rgba(0,229,255,.3) 40%,rgba(168,85,247,.3) 60%,transparent);" />
      <div class="mx-auto flex max-w-2xl">
        <RouterLink v-for="n in nav" :key="n.to" :to="n.to"
          class="relative flex flex-1 flex-col items-center gap-0.5 py-3 text-[10px]
                 text-slate-500 transition-all duration-200 font-medium"
          exact-active-class="!text-cyan-400">
          <span v-if="n.badge"
            class="badge-dot absolute top-1.5 right-[22%] w-3.5 h-3.5 text-[8px]">
            {{ n.badge > 9 ? '9+' : n.badge }}
          </span>
          <span class="text-lg leading-none">{{ n.icon }}</span>
          <span>{{ n.label }}</span>
        </RouterLink>
      </div>
    </nav>

  </template>
</template>
