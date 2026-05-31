<script setup>
import { onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterView, RouterLink } from 'vue-router'
import { useAuth } from './composables/useAuth'
import { useClub } from './composables/useClub'

const { user, ready, signOut } = useAuth()
const { clubs, currentClub, loadClubs, selectClub } = useClub()
const route = useRoute()
const router = useRouter()

async function init() { if (user.value) { try { await loadClubs() } catch (e) {} } }
onMounted(init)
watch(user, init)

async function logout() { await signOut(); router.push('/login') }
function onSwitch(e) {
  const c = clubs.value.find(x => x.club_id === e.target.value)
  if (c) selectClub(c)
}

const nav = [
  { to: '/dashboard', label: 'Rankings', icon: '🏆', desc: 'Leaderboard' },
  { to: '/match',     label: 'Add Match', icon: '➕', desc: 'Record result' },
  { to: '/players',   label: 'Players',   icon: '👥', desc: 'Roster' },
  { to: '/compare',   label: 'Compare',   icon: '⚔️',  desc: 'Head to head' },
  { to: '/manage',    label: 'Manage',    icon: '⚙️',  desc: 'Settings' }
]
</script>

<template>
  <div v-if="!ready" class="grid min-h-screen place-items-center">
    <div class="text-center">
      <div class="text-4xl mb-3">🏸</div>
      <div class="text-slate-400 text-sm">Loading Badmint…</div>
    </div>
  </div>

  <template v-else>
    <RouterView v-if="route.meta.public" />

    <div v-else class="mx-auto max-w-2xl px-4 pb-28 pt-4">
      <!-- Top bar -->
      <header class="mb-5 flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <span class="text-2xl">🏸</span>
          <div>
            <h1 class="font-display text-xl font-bold tracking-tight leading-none">Badmint</h1>
            <div class="text-[10px] text-slate-500 tracking-widest uppercase">Ranking System</div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <select v-if="clubs.length" :value="currentClub?.club_id" @change="onSwitch"
            class="rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-sm max-w-[130px] truncate">
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id">{{ c.clubs?.name }}</option>
          </select>
          <button class="text-xs text-slate-400 hover:text-slate-200 transition" @click="logout">Sign out</button>
        </div>
      </header>

      <!-- No club state -->
      <div v-if="!currentClub && route.path !== '/manage'"
        class="card p-6 text-center">
        <div class="text-3xl mb-3">👋</div>
        <p class="font-semibold mb-1">Welcome to Badmint!</p>
        <p class="text-sm text-slate-400 mb-4">You're not part of any team yet. Create your club to get started.</p>
        <RouterLink to="/manage" class="btn-primary inline-block">Create Your Club →</RouterLink>
      </div>

      <RouterView v-else />

      <!-- Bottom nav -->
      <nav class="fixed inset-x-0 bottom-0 z-10 border-t border-white/10 bg-[#0b1120]/95 backdrop-blur safe-area-pb">
        <div class="mx-auto flex max-w-2xl">
          <RouterLink v-for="n in nav" :key="n.to" :to="n.to"
            class="flex flex-1 flex-col items-center gap-0.5 py-2.5 text-[10px] text-slate-500 transition"
            active-class="!text-teal-400">
            <span class="text-lg leading-none">{{ n.icon }}</span>
            <span>{{ n.label }}</span>
          </RouterLink>
        </div>
      </nav>
    </div>
  </template>
</template>
