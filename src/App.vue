<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterView, RouterLink } from 'vue-router'
import { useRegisterSW } from 'virtual:pwa-register/vue'
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
const showMenu     = ref(false)
const updating     = ref(false)
const isAdmin      = ref(false)

// ── PWA update detection ──────────────────────────────────────────────────────
// If a new SW is already waiting when the app opens (during loading screen),
// apply it silently — user sees the loading screen for ~1 extra second.
// If detected while the app is running, show the update banner instead.
const { needRefresh, updateServiceWorker } = useRegisterSW({ immediate: true })
watch(needRefresh, (yes) => {
  if (yes && !ready.value) {
    updating.value = true
    updateServiceWorker(true)   // skip-waiting + reload
  }
})

// ── Hamburger menu sections ──────────────────────────────────────────────────
const menuSections = [
  {
    label: 'Match Day',
    items: [
      { to: '/match',   icon: '➕', label: 'Add Match' },
      { to: '/matches', icon: '📋', label: 'Matches' },
      { to: '/compare', icon: '📊', label: 'Compare Players' },
      { to: '/guide',   icon: '📖', label: 'Ranking Guide' },
    ]
  },
  {
    label: 'Club Admin',
    items: [
      { to: '/manage',  icon: '⚙️', label: 'Manage Club' },
      { to: '/explore', icon: '🌍', label: 'Explore Clubs' },
      { to: '/join',    icon: '🔗', label: 'Join a Club' },
    ]
  },
  {
    label: 'Competitions',
    items: [
      { to: '/tournaments', icon: '🏆', label: 'Tournaments' },
    ]
  },
  {
    label: 'Finances',
    items: [
      { to: '/splits',  icon: '💰', label: 'PaySplits' },
    ]
  },
  {
    label: 'Account',
    items: [
      { to: '/profile',  icon: '👤', label: 'My Profile' },
      { to: '/schedule', icon: '📅', label: 'Schedule' },
    ]
  }
]

const comingSoon = [
  { icon: '📒', label: 'Ledger Book' },
]

function closeMenu() { showMenu.value = false }

async function init() {
  if (!user.value) return
  try {
    await loadClubs()
    await refreshPending()
  } catch {}
  // Non-blocking: session + admin check don't need to hold up club/page loading
  startSession().catch(() => {})
  supabase.rpc('get_my_roles').then(({ data }) => {
    isAdmin.value = (data ?? []).some(r => r.role === 'app_admin')
  }).catch(() => {})
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
  if (user.value) trackPage(path)
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

// ── Bottom nav ───────────────────────────────────────────────────────────────
const nav = computed(() => [
  { to: '/dashboard',   label: 'Home',        icon: '🏠' },
  { to: '/clubs',       label: 'My Clubs',    icon: '🏸' },
  { to: '/splits',      label: 'PaySplits',   icon: '💰' },
  { to: '/book',        label: 'Book Court',  icon: '🏢' },
  { to: '/tournaments', label: 'Tournaments', icon: '🏆' },
])

const clubFreeRoutes = ['/manage', '/join', '/explore', '/profile', '/schedule', '/tournaments', '/clubs', '/book', '/splits']
const needsClub = computed(() =>
  !currentClub.value &&
  !clubFreeRoutes.includes(route.path) &&
  !route.path.startsWith('/tournament')
)
</script>

<template>
  <!-- Loading splash -->
  <div v-if="!ready" class="grid min-h-screen place-items-center">
    <div class="text-center">
      <div class="text-5xl mb-4">🏸</div>
      <div class="text-neon font-semibold text-sm animate-pulse">
        {{ updating ? 'Applying update…' : 'Loading Badminton 360…' }}
      </div>
      <div v-if="updating" class="text-[11px] text-slate-400 mt-2">
        Getting the latest version — one moment
      </div>
    </div>
  </div>

  <template v-else>

    <!-- ── PWA update banner ──────────────────────────────────────────────────
         Shown when a new SW is waiting but the app was already past the loading
         screen (so auto-reload didn't fire). User taps Update to reload. -->
    <Teleport to="body">
      <Transition name="update-slide">
        <div v-if="needRefresh"
          class="fixed top-0 inset-x-0 z-[90] flex items-center justify-between gap-3 px-4 py-2.5"
          style="background:linear-gradient(90deg,#0077a8,#0099b8);
                 box-shadow:0 2px 12px rgba(0,119,168,.3);">
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-base shrink-0">🔄</span>
            <div class="min-w-0">
              <div class="text-xs font-semibold text-white leading-tight">New version available</div>
              <div class="text-[10px] text-white/70 leading-tight">Tap to get the latest Badminton 360</div>
            </div>
          </div>
          <button @click="updateServiceWorker(true)"
            class="text-xs font-bold px-3 py-1.5 rounded-lg shrink-0 transition-opacity hover:opacity-80"
            style="background:rgba(255,255,255,.25); color:#fff;
                   border:1px solid rgba(255,255,255,.35);">
            Update
          </button>
        </div>
      </Transition>
    </Teleport>

    <!-- ── Floating hamburger for public routes when logged in ────────────────
         Public views (Explore, Home, FacilityProfile) don't use this shell's
         top bar, so we overlay a fixed button so navigation is always reachable. -->
    <button v-if="user && route.meta.public"
      class="fixed top-3 left-3 z-40 w-10 h-10 rounded-xl flex flex-col items-center
             justify-center gap-[5px] border hover:shadow-md transition shrink-0"
      style="background:rgba(255,255,255,.92); backdrop-filter:blur(12px);
             border-color:rgba(0,0,0,.10); box-shadow:0 2px 10px rgba(0,0,0,.10);"
      @click="showMenu = true"
      aria-label="Open menu">
      <span class="block w-4 h-px bg-slate-600"></span>
      <span class="block w-4 h-px bg-slate-600"></span>
      <span class="block w-3 h-px bg-slate-600 self-start ml-2"></span>
    </button>

    <!-- Public routes: full-screen, pad bottom for nav when logged in -->
    <div v-if="route.meta.public" :class="user ? 'pb-28' : ''">
      <RouterView />
    </div>

    <!-- ── Authenticated shell ─────────────────────────────────────────────── -->
    <div v-else class="mx-auto max-w-2xl px-4 pb-28 pt-4">

      <!-- PWA install banner -->
      <div v-if="canInstall && !isInstalled" class="card-neon mb-4 px-4 py-3 flex items-center gap-3 fade-up">
        <span class="text-2xl shrink-0">📲</span>
        <div class="flex-1 min-w-0">
          <div class="text-xs font-bold text-slate-800">Install Badminton 360 on Android</div>
          <div class="text-[10px] text-slate-500">Works offline · No app store needed</div>
        </div>
        <button class="btn-primary text-xs px-3 py-1.5 shrink-0" @click="promptInstall">Install</button>
      </div>

      <div v-if="isIOS && !isInstalled && showIOSHint"
        class="card mb-4 px-4 py-3 fade-up" style="border-color:rgba(147,51,234,.25)">
        <div class="flex items-start gap-2">
          <span class="text-xl shrink-0">🍎</span>
          <div>
            <div class="text-xs font-bold text-slate-800 mb-1">Add to iPhone Home Screen</div>
            <div class="text-[11px] text-slate-500 leading-relaxed">
              Tap the <strong class="text-slate-700">Share</strong> button (↑) in Safari,
              then choose <strong class="text-slate-700">"Add to Home Screen"</strong>.
            </div>
          </div>
          <button class="text-slate-400 hover:text-slate-600 text-sm shrink-0 transition"
            @click="showIOSHint = false">✕</button>
        </div>
      </div>

      <!-- ── Top bar: hamburger on LEFT ──────────────────────────────────────── -->
      <header class="mb-5 flex items-center justify-between gap-3">

        <!-- LEFT: hamburger + logo -->
        <div class="flex items-center gap-2.5">
          <button @click="showMenu = true"
            class="w-9 h-9 rounded-xl flex flex-col items-center justify-center gap-[5px]
                   border hover:shadow-sm transition shrink-0 relative"
            style="border-color:rgba(0,0,0,.10); background:rgba(255,255,255,.8);"
            aria-label="Open menu">
            <span class="block w-4 h-px bg-slate-500"></span>
            <span class="block w-4 h-px bg-slate-500"></span>
            <span class="block w-3 h-px bg-slate-500 self-start ml-2"></span>
            <span v-if="pendingCount > 0"
              class="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-rose-500 text-[8px]
                     text-white font-bold flex items-center justify-center leading-none">
              {{ pendingCount > 9 ? '9+' : pendingCount }}
            </span>
          </button>

          <RouterLink to="/" class="flex items-center gap-2 hover:opacity-75 transition">
            <span class="text-2xl leading-none">🏸</span>
            <div>
              <h1 class="font-display text-xl font-extrabold tracking-tight leading-none gradient-text">Badminton 360</h1>
              <div class="text-[9px] text-slate-400 tracking-[0.2em] uppercase">Your Club · Your Game · One App</div>
            </div>
          </RouterLink>
        </div>

        <!-- RIGHT: iOS install · club switcher · profile avatar -->
        <div class="flex items-center gap-2">
          <button v-if="isIOS && !isInstalled && !showIOSHint"
            class="text-[10px] text-violet hover:opacity-75 transition px-1" @click="showIOSHint = true">
            📲 Install
          </button>

          <select v-if="clubs.length" :value="currentClub?.club_id" @change="onSwitch"
            class="rounded-lg px-2.5 py-1.5 text-xs max-w-[120px] truncate text-slate-700
                   outline-none transition-colors duration-200 font-medium"
            style="border:1px solid rgba(0,0,0,.12); background:#ffffff;">
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id"
              class="bg-white text-slate-800">{{ c.clubs?.name }}</option>
          </select>

          <RouterLink to="/profile" class="w-7 h-7 rounded-full flex items-center justify-center text-xs
            font-bold text-white shrink-0 hover:opacity-80 transition"
            style="background:linear-gradient(135deg,#00b4d8,#9333ea)">
            {{ (user?.user_metadata?.full_name ?? user?.email ?? '?')[0].toUpperCase() }}
          </RouterLink>
        </div>

      </header>

      <!-- No club state -->
      <div v-if="needsClub" class="card-neon p-8 text-center fade-up">
        <div class="text-4xl mb-4">👋</div>
        <h2 class="font-display text-xl font-bold gradient-text mb-1">Welcome to Badminton 360!</h2>
        <p class="text-sm text-slate-500 mb-6">Join your team's club or create a new one to get started.</p>
        <div class="flex flex-col gap-3">
          <RouterLink to="/explore" class="btn-primary w-full py-3 text-sm">🌍 Browse &amp; Join a Club</RouterLink>
          <RouterLink to="/join"    class="btn-ghost  w-full py-3 text-sm">🔗 Have an Invite Link?</RouterLink>
          <RouterLink to="/manage"  class="btn-ghost  w-full py-3 text-sm">➕ Create My Own Club</RouterLink>
        </div>
      </div>

      <RouterView v-else />

    </div>

    <!-- ── Bottom nav: all logged-in users ─────────────────────────────────── -->
    <nav v-if="user && route.path !== '/login'"
      class="fixed inset-x-0 bottom-0 z-20 safe-area-pb"
      style="background:rgba(255,255,255,.96); border-top:1px solid rgba(0,0,0,.07);
             backdrop-filter:blur(20px); box-shadow:0 -4px 20px rgba(0,0,0,.06);">
      <!-- Cyan→violet gradient accent line at top of nav bar -->
      <div class="absolute top-0 left-0 right-0 h-px"
        style="background:linear-gradient(90deg,transparent,rgba(0,168,204,.45) 35%,rgba(147,51,234,.40) 65%,transparent);" />
      <div class="mx-auto flex max-w-2xl">
        <RouterLink v-for="n in nav" :key="n.to" :to="n.to"
          class="relative flex flex-1 flex-col items-center gap-0.5 py-3 text-[10px]
                 text-slate-400 transition-all duration-200 font-medium"
          exact-active-class="!text-cyan-700">
          <span class="text-lg leading-none">{{ n.icon }}</span>
          <span>{{ n.label }}</span>
        </RouterLink>
      </div>
    </nav>

    <!-- ── Hamburger menu drawer (slides from LEFT) ─────────────────────────── -->
    <Teleport to="body">
      <Transition name="menu-fade">
        <div v-if="showMenu" class="fixed inset-0 z-50 flex" @keydown.esc="closeMenu">

          <!-- Backdrop -->
          <div class="absolute inset-0 bg-black/30 backdrop-blur-sm" @click="closeMenu" />

          <!-- Panel -->
          <div class="menu-panel absolute left-0 top-0 bottom-0 w-72 flex flex-col"
            style="background:#f8faff; border-right:1px solid rgba(0,0,0,.08);
                   box-shadow:4px 0 32px rgba(0,0,0,.12);">

            <!-- Panel header -->
            <div class="flex items-center justify-between px-5 py-4"
              style="border-bottom:1px solid rgba(0,0,0,.07)">
              <div class="flex items-center gap-2">
                <span class="text-xl">🏸</span>
                <span class="font-display font-extrabold gradient-text">Badminton 360</span>
              </div>
              <button @click="closeMenu"
                class="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400
                       hover:text-slate-700 hover:bg-black/[0.05] transition text-base">✕</button>
            </div>

            <!-- Nav sections -->
            <div class="flex-1 overflow-y-auto py-3">

              <!-- Home — always first -->
              <RouterLink to="/" @click="closeMenu"
                class="flex items-center gap-3 px-5 py-3 text-sm font-semibold text-slate-700
                       hover:bg-black/[0.04] hover:text-slate-900 transition-colors"
                exact-active-class="!text-cyan-700 bg-cyan-50">
                <span class="text-base w-6 text-center shrink-0">🏠</span>
                Home
              </RouterLink>

              <div class="mx-5 my-1" style="border-top:1px solid rgba(0,0,0,.07)" />

              <div v-for="section in menuSections" :key="section.label" class="mb-1">
                <div class="text-[10px] uppercase tracking-widest text-slate-400 px-5 py-2 font-semibold">
                  {{ section.label }}
                </div>
                <RouterLink v-for="item in section.items" :key="item.to" :to="item.to"
                  @click="closeMenu"
                  class="flex items-center gap-3 px-5 py-3 text-sm font-medium text-slate-700
                         hover:bg-black/[0.04] hover:text-slate-900 transition-colors"
                  active-class="!text-cyan-700 bg-cyan-50">
                  <span class="text-base w-6 text-center shrink-0">{{ item.icon }}</span>
                  {{ item.label }}
                  <span v-if="item.to === '/manage' && pendingCount > 0"
                    class="ml-auto text-[10px] bg-rose-500 text-white rounded-full
                           px-1.5 py-0.5 font-bold leading-none">
                    {{ pendingCount > 9 ? '9+' : pendingCount }}
                  </span>
                </RouterLink>
              </div>

              <!-- Admin Panel (app_admin only) -->
              <div v-if="isAdmin" class="mb-1 mt-2">
                <div class="text-[10px] uppercase tracking-widest text-slate-400 px-5 py-2 font-semibold">
                  Platform Admin
                </div>
                <RouterLink to="/admin" @click="closeMenu"
                  class="flex items-center gap-3 px-5 py-3 text-sm font-medium text-slate-700
                         hover:bg-black/[0.04] hover:text-slate-900 transition-colors"
                  active-class="!text-cyan-700 bg-cyan-50">
                  <span class="text-base w-6 text-center shrink-0">🛡️</span>
                  Admin Panel
                  <span class="ml-auto text-[9px] bg-rose-100 text-rose-600 rounded px-1.5 py-0.5 font-bold">ADMIN</span>
                </RouterLink>
              </div>

              <!-- Coming soon items -->
              <div v-if="comingSoon.length" class="mb-1 mt-2">
                <div class="text-[10px] uppercase tracking-widest text-slate-400 px-5 py-2
                            font-semibold flex items-center gap-2">
                  Coming Soon
                  <span class="text-[9px] bg-amber-100 text-amber-700 rounded px-1.5 py-0.5
                               normal-case tracking-normal font-semibold">beta</span>
                </div>
                <div v-for="item in comingSoon" :key="item.label"
                  class="flex items-center gap-3 px-5 py-3 text-sm font-medium
                         text-slate-400 cursor-default select-none">
                  <span class="text-base w-6 text-center shrink-0 opacity-50">{{ item.icon }}</span>
                  <span class="opacity-60">{{ item.label }}</span>
                  <span class="ml-auto text-[9px] bg-slate-100 text-slate-400
                               rounded px-1.5 py-0.5 font-medium">soon</span>
                </div>
              </div>

            </div>

            <!-- Sign out -->
            <div style="border-top:1px solid rgba(0,0,0,.07)" class="p-4">
              <button @click="logout(); closeMenu()"
                class="w-full flex items-center gap-3 px-4 py-2.5 rounded-xl text-sm
                       text-slate-500 hover:text-rose-600 hover:bg-rose-50 transition">
                <span class="text-base">🚪</span> Sign out
              </button>
            </div>

          </div>
        </div>
      </Transition>
    </Teleport>

  </template>
</template>

<style>
.menu-fade-enter-active { transition: opacity 0.2s ease; }
.menu-fade-leave-active { transition: opacity 0.15s ease; }
.menu-fade-enter-from, .menu-fade-leave-to { opacity: 0; }

/* Drawer slides in/out from the LEFT */
.menu-fade-enter-active .menu-panel { transition: transform 0.25s ease; }
.menu-fade-leave-active .menu-panel { transition: transform 0.2s ease; }
.menu-fade-enter-from .menu-panel, .menu-fade-leave-to .menu-panel { transform: translateX(-100%); }

/* Update banner slides down from top */
.update-slide-enter-active { transition: transform 0.3s ease, opacity 0.3s ease; }
.update-slide-leave-active { transition: transform 0.2s ease, opacity 0.2s ease; }
.update-slide-enter-from, .update-slide-leave-to { transform: translateY(-100%); opacity: 0; }
</style>
