<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterView, RouterLink } from 'vue-router'
import { supabase } from './lib/supabase'
import { useAuth } from './composables/useAuth'
import { useClub } from './composables/useClub'

const { user, ready, signOut } = useAuth()
const { clubs, currentClub, loadClubs, selectClub } = useClub()
const route  = useRoute()
const router = useRouter()

const pendingCount = ref(0)

async function init() {
  if (!user.value) return
  try {
    await loadClubs()
    await refreshPending()
  } catch {}
}

// Count pending join requests across all clubs where user is manager
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
watch(() => route.path, refreshPending)

async function logout() { await signOut(); router.push('/login') }
function onSwitch(e) {
  const c = clubs.value.find(x => x.club_id === e.target.value)
  if (c) selectClub(c)
}

const nav = computed(() => [
  { to: '/dashboard', label: 'Rankings',  icon: '🏆' },
  { to: '/match',     label: 'Add Match', icon: '➕' },
  { to: '/players',   label: 'Players',   icon: '👥' },
  { to: '/compare',   label: 'Compare',   icon: '⚔️'  },
  { to: '/manage',    label: 'Manage',    icon: '⚙️', badge: pendingCount.value },
])
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
    <!-- Public routes (Login) render full-screen -->
    <RouterView v-if="route.meta.public" />

    <div v-else class="mx-auto max-w-2xl px-4 pb-28 pt-4">

      <!-- ── Top bar ── -->
      <header class="mb-5 flex items-center justify-between gap-3">
        <div class="flex items-center gap-2.5">
          <span class="text-2xl leading-none" style="filter:drop-shadow(0 0 12px rgba(0,229,255,.5));">🏸</span>
          <div>
            <h1 class="font-display text-xl font-extrabold tracking-tight leading-none gradient-text">Badmint</h1>
            <div class="text-[9px] text-slate-500 tracking-[0.2em] uppercase">Ranking System</div>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <!-- Club switcher -->
          <select v-if="clubs.length" :value="currentClub?.club_id" @change="onSwitch"
            class="rounded-lg border border-white/10 bg-white/[0.05] px-2.5 py-1.5 text-xs
                   max-w-[130px] truncate text-slate-200 outline-none focus:border-cyan-500/40
                   transition-colors duration-200">
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id"
              class="bg-slate-900">{{ c.clubs?.name }}</option>
          </select>

          <button class="text-xs text-slate-500 hover:text-slate-200 transition px-1"
            @click="logout">Sign out</button>
        </div>
      </header>

      <!-- ── No club state ── -->
      <div v-if="!currentClub && route.path !== '/manage' && route.path !== '/join'"
        class="card-neon p-8 text-center fade-up">
        <div class="text-4xl mb-4" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.4));">👋</div>
        <h2 class="font-display text-xl font-bold gradient-text mb-1">Welcome to Badmint!</h2>
        <p class="text-sm text-slate-400 mb-6">
          Join your team's club or create a new one to get started.
        </p>
        <div class="flex flex-col gap-3">
          <RouterLink to="/join" class="btn-primary w-full py-3 text-sm">
            🏟️ Browse &amp; Join a Club
          </RouterLink>
          <RouterLink to="/manage" class="btn-ghost w-full py-3 text-sm">
            ➕ Create My Own Club
          </RouterLink>
        </div>
        <p class="mt-4 text-[11px] text-slate-600">
          Have an invite link? Click it — you'll be added automatically.
        </p>
      </div>

      <RouterView v-else />

      <!-- ── Bottom nav ── -->
      <nav class="fixed inset-x-0 bottom-0 z-20 safe-area-pb"
        style="background:rgba(5,13,26,.95); border-top:1px solid rgba(255,255,255,.07); backdrop-filter:blur(20px);">

        <!-- Neon top accent line -->
        <div class="absolute top-0 left-0 right-0 h-px"
          style="background:linear-gradient(90deg,transparent,rgba(0,229,255,.3) 40%,rgba(168,85,247,.3) 60%,transparent);" />

        <div class="mx-auto flex max-w-2xl">
          <RouterLink v-for="n in nav" :key="n.to" :to="n.to"
            class="relative flex flex-1 flex-col items-center gap-0.5 py-3 text-[10px]
                   text-slate-500 transition-all duration-200"
            active-class="!text-cyan-400">

            <!-- Badge for pending requests -->
            <span v-if="n.badge" class="badge-dot absolute top-1.5 right-[25%] w-3.5 h-3.5 text-[8px]">
              {{ n.badge > 9 ? '9+' : n.badge }}
            </span>

            <span class="text-lg leading-none">{{ n.icon }}</span>
            <span class="font-medium">{{ n.label }}</span>
          </RouterLink>
        </div>
      </nav>

    </div>
  </template>
</template>
