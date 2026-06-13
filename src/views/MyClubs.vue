<script setup>
import { onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()
const { clubs, currentClub, loadClubs, selectClub } = useClub()

onMounted(() => loadClubs())

function switchTo(c) {
  selectClub(c)
  router.push('/club/' + c.club_id)
}
</script>

<template>
  <div>
    <PageHeader icon="🏸" title="My Clubs" subtitle="All clubs you're a member of">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p>Tap <strong>Club Profile</strong> to view rankings and members.</p>
          <p>Tap <strong>Matches</strong> to see the full match history for that club.</p>
          <p>Tap <strong>Manage</strong> to invite players, change settings, or leave a club.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Empty state -->
    <div v-if="!clubs.length" class="card-neon p-10 text-center fade-up">
      <div class="text-4xl mb-4">🏸</div>
      <p class="font-bold gradient-text text-lg mb-2">You're not in any club yet</p>
      <p class="text-slate-400 text-sm mb-5">Join an existing club or create your own.</p>
      <div class="flex flex-col gap-3">
        <RouterLink to="/join"         class="btn-primary w-full py-3">🔗 Join a Club</RouterLink>
        <RouterLink to="/create-club"  class="btn-ghost   w-full py-3">➕ Create a Club</RouterLink>
      </div>
    </div>

    <!-- Club cards -->
    <div v-else class="space-y-4 fade-up">
      <div v-for="c in clubs" :key="c.club_id"
        class="card overflow-hidden transition-all duration-200"
        :class="currentClub?.club_id === c.club_id ? 'card-neon' : 'hover:border-slate-300'">

        <!-- Club header -->
        <div class="flex items-center gap-3 p-4 pb-3">
          <div class="w-12 h-12 rounded-2xl flex items-center justify-center text-2xl shrink-0"
            :class="currentClub?.club_id === c.club_id ? 'bg-cyan-100' : 'bg-slate-100'">
            🏸
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <h3 class="font-display font-bold text-slate-800 text-base truncate">
                {{ c.clubs?.name }}
              </h3>
              <span v-if="currentClub?.club_id === c.club_id"
                class="badge bg-cyan-50 text-cyan-700 border border-cyan-200 shrink-0">Active</span>
            </div>
            <p class="text-xs text-slate-400 capitalize mt-0.5">{{ c.role }}</p>
          </div>
          <button class="shrink-0 btn-primary text-xs px-3 py-1.5"
            @click="switchTo(c)">
            {{ currentClub?.club_id === c.club_id ? 'Active ✓' : 'Switch →' }}
          </button>
        </div>

        <!-- Action buttons row -->
        <div class="border-t border-slate-100 px-4 py-3 grid grid-cols-3 gap-2">
          <RouterLink :to="'/club/' + c.club_id"
            class="flex flex-col items-center gap-1.5 py-2.5 rounded-xl transition-all text-center border
                   border-cyan-200 bg-cyan-50 hover:bg-cyan-100 active:scale-95">
            <span class="text-lg">🏆</span>
            <span class="text-xs font-semibold text-cyan-700">Club Profile</span>
          </RouterLink>

          <RouterLink to="/matches"
            class="flex flex-col items-center gap-1.5 py-2.5 rounded-xl transition-all text-center border
                   border-slate-200 bg-slate-50 hover:bg-slate-100 active:scale-95">
            <span class="text-lg">📋</span>
            <span class="text-xs font-semibold text-slate-600">Matches</span>
          </RouterLink>

          <RouterLink to="/manage"
            class="flex flex-col items-center gap-1.5 py-2.5 rounded-xl transition-all text-center border
                   border-slate-200 bg-slate-50 hover:bg-slate-100 active:scale-95">
            <span class="text-lg">⚙️</span>
            <span class="text-xs font-semibold text-slate-600">Manage</span>
          </RouterLink>
        </div>
      </div>

      <!-- Join / Create -->
      <div class="grid grid-cols-2 gap-3">
        <RouterLink to="/join"        class="btn-ghost text-sm py-3 text-center">🔗 Join a Club</RouterLink>
        <RouterLink to="/create-club" class="btn-ghost text-sm py-3 text-center">➕ Create Club</RouterLink>
      </div>
    </div>
  </div>
</template>
