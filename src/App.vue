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
const showMenu     = ref(false)

// ── Hamburger menu sections ──────────────────────────────────────────────────
// When Payments ships: add { to: '/payments', icon: '💰', label: 'Payment Splits' }
// and { to: '/ledger', icon: '📒', label: 'Ledger Book' } to comingSoon → active items.
const menuSections = [
  {
    label: 'Match Day',
    items: [
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
    label: 'Account',
    items: [
      { to: '/profile', icon: '👤', label: 'My Profile' },
      { to: '/',        icon: '🏠', label: 'Home' },
    ]
  }
]

// Greyed-out coming-soon items in the drawer — removed once the feature ships
const comingSoon = [
  { icon: '💰', label: 'Payment Splits' },
  { icon: '📒', label: 'Ledger Book' },
]

function closeMenu() { showMenu.value = false }

async function init() {
  if (!user.value) return
  try {
    await loadClubs()
    await refreshPending()
    await startSession()
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
// Add Match promoted to bottom (most-used manager action).
// Manage moved to hamburger — pending badge shown there instead.
// When Payments ships: swap 📋 Matches → 💰 Payments (Matches → hamburger).
const nav = computed(() => [
  { to: '/schedule',  label: 'Schedule',  icon: '📅' },
  { to: '/dashboard', label: 'Rankings',  icon: '🏆' },
  { to: '/match',     label: 'Add Match', icon: '➕' },
  { to: '/players',   label: 'Players',   icon: '👥' },
  { to: '/matches',   label: 'Matches',   icon: '📋' },
])

// Routes that don't need a club selected
const clubFreeRoutes = ['/manage', '/join', '/explore', '/profile', '/schedule']
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

    <!-- ── Floating hamburger for public routes when logged in ────────────────
         Public pages (Explore, Home, FacilityProfile) render their own full-screen
         layouts inside RouterView without this shell's top bar. We overlay a fixed
         hamburger button so all pages have consistent nav access. -->
    <button v-if="user && route.meta.public"
      class="fixed top-3 left-3 z-40 w-10 h-10 rounded-xl flex flex-col items-center
             justify-center gap-[5px] border border-white/15
             hover:border-white/35 transition shrink-0"
      style="background:rgba(7,16,31,.85); backdrop-filter:blur(12px);"
      @click="showMenu = true"
      aria-label="Open menu">
      <span class="block w-4 h-px bg-slate-300"></span>
      <span class="block w-4 h-px bg-slate-300"></span>
      <span class="block w-3 h-px bg-slate-300 self-start ml-2"></span>
    </button>

    <!-- Public routes: full-screen, pad bottom for nav when logged in -->
    <div v-if="route.meta.public" :class="user ? 'pb-28' : ''">
      <RouterView />
    </div>

    <!-- ── Authenticated shell (top bar + content wrapper) ───────────────────── -->
    <div v-else class="mx-auto max-w-2xl px-4 pb-28 pt-4">

      <!-- PWA Install banner -->
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

      <!-- ── Top bar: hamburger on LEFT ──────────────────────────────────────── -->
      <header class="mb-5 flex items-center justify-between gap-3">

        <!-- LEFT: hamburger + logo -->
        <div class="flex items-center gap-2.5">
          <button @click="showMenu = true"
            class="w-9 h-9 rounded-xl flex flex-col items-center justify-center gap-[5px]
                   border border-white/10 hover:border-white/30 transition shrink-0 relative"
            aria-label="Open menu">
            <span class="block w-4 h-px bg-slate-400"></span>
            <span class="block w-4 h-px bg-slate-400"></span>
            <span class="block w-3 h-px bg-slate-400 self-start ml-2"></span>
            <!-- pending requests badge on hamburger -->
            <span v-if="pendingCount > 0"
              class="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-rose-500 text-[8px]
                     text-white font-bold flex items-center justify-center leading-none">
              {{ pendingCount > 9 ? '9+' : pendingCount }}
            </span>
          </button>

          <RouterLink to="/" class="flex items-center gap-2 hover:opacity-80 transition">
            <span class="text-2xl leading-none" style="filter:drop-shadow(0 0 12px rgba(0,229,255,.5));">🏸</span>
            <div>
              <h1 class="font-display text-xl font-extrabold tracking-tight leading-none gradient-text">Badmint</h1>
              <div class="text-[9px] text-slate-500 tracking-[0.2em] uppercase">UAE Badminton Rankings</div>
            </div>
          </RouterLink>
        </div>

        <!-- RIGHT: iOS install · club switcher · profile avatar -->
        <div class="flex items-center gap-2">
          <button v-if="isIOS && !isInstalled && !showIOSHint"
            class="text-[10px] text-violet hover:opacity-80 transition px-1" @click="showIOSHint = true">
            📲 Install
          </button>

          <select v-if="clubs.length" :value="currentClub?.club_id" @change="onSwitch"
            class="rounded-lg border border-white/10 bg-white/[0.05] px-2.5 py-1.5 text-xs
                   max-w-[120px] truncate text-slate-200 outline-none focus:border-cyan-500/40
                   transition-colors duration-200">
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id"
              class="bg-slate-900">{{ c.clubs?.name }}</option>
          </select>

          <RouterLink to="/profile" class="w-7 h-7 rounded-full flex items-center justify-center text-xs
            font-bold text-slate-950 shrink-0 hover:opacity-80 transition"
            style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
            {{ (user?.user_metadata?.full_name ?? user?.email ?? '?')[0].toUpperCase() }}
          </RouterLink>
        </div>

      </header>

      <!-- No club state -->
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

    <!-- ── Bottom nav: all logged-in users on every page ───────────────────── -->
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
          <div class="absolute inset-0 bg-black/65 backdrop-blur-sm" @click="closeMenu" />

          <!-- Slide-in panel from LEFT -->
          <div class="menu-panel absolute left-0 top-0 bottom-0 w-72 flex flex-col"
            style="background:#07101f; border-right:1px solid rgba(255,255,255,.08);">

            <!-- Panel header -->
            <div class="flex items-center justify-between px-5 py-4"
              style="border-bottom:1px solid rgba(255,255,255,.07)">
              <div class="flex items-center gap-2">
                <span class="text-xl" style="filter:drop-shadow(0 0 10px rgba(0,229,255,.5))">🏸</span>
                <span class="font-display font-extrabold gradient-text">Badmint</span>
              </div>
              <button @click="closeMenu"
                class="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400
                       hover:text-white hover:bg-white/10 transition text-base">✕</button>
            </div>

            <!-- Nav sections -->
            <div class="flex-1 overflow-y-auto py-3">

              <div v-for="section in menuSections" :key="section.label" class="mb-1">
                <div class="text-[10px] uppercase tracking-widest text-slate-600 px-5 py-2">
                  {{ section.label }}
                </div>
                <RouterLink v-for="item in section.items" :key="item.to" :to="item.to"
                  @click="closeMenu"
                  class="flex items-center gap-3 px-5 py-3 text-sm font-medium text-slate-300
                         hover:bg-white/[0.06] hover:text-white transition-colors"
                  active-class="!text-cyan-400 bg-cyan-500/[0.08]">
                  <span class="text-base w-6 text-center shrink-0">{{ item.icon }}</span>
                  {{ item.label }}
                  <!-- pending badge on Manage Club link -->
                  <span v-if="item.to === '/manage' && pendingCount > 0"
                    class="ml-auto text-[10px] bg-rose-500 text-white rounded-full
                           px-1.5 py-0.5 font-bold leading-none">
                    {{ pendingCount > 9 ? '9+' : pendingCount }}
                  </span>
                </RouterLink>
              </div>

              <!-- Coming soon: Finances -->
              <div class="mb-1 mt-2">
                <div class="text-[10px] uppercase tracking-widest text-slate-600 px-5 py-2 flex items-center gap-2">
                  Finances
                  <span class="text-[9px] bg-amber-500/20 text-amber-400 rounded px-1.5 py-0.5
                               normal-case tracking-normal font-semibold">coming soon</span>
                </div>
                <div v-for="item in comingSoon" :key="item.label"
                  class="flex items-center gap-3 px-5 py-3 text-sm font-medium
                         text-slate-600 cursor-default select-none">
                  <span class="text-base w-6 text-center shrink-0 opacity-40">{{ item.icon }}</span>
                  <span class="opacity-50">{{ item.label }}</span>
                  <span class="ml-auto text-[9px] bg-slate-700/50 text-slate-500
                               rounded px-1.5 py-0.5 font-medium">soon</span>
                </div>
              </div>

            </div>

            <!-- Sign out -->
            <div style="border-top:1px solid rgba(255,255,255,.07)" class="p-4">
              <button @click="logout(); closeMenu()"
                class="w-full flex items-center gap-3 px-4 py-2.5 rounded-xl text-sm
                       text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition">
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
</style>
