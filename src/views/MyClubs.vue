<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()
const { clubs, currentClub, loadClubs, selectClub, createClub } = useClub()

// Per-club leaderboard summaries
const boardMap = ref({})   // club_id → top 3 players

async function loadBoardSummaries() {
  for (const c of clubs.value) {
    const { data } = await supabase
      .from('v_leaderboard')
      .select('id, display_name, elo, composite, club_rank')
      .eq('club_id', c.club_id)
      .order('club_rank')
      .limit(3)
    if (data) boardMap.value[c.club_id] = data
  }
}

onMounted(async () => {
  await loadClubs()
  await loadBoardSummaries()
})

function switchTo(c) {
  selectClub(c)
  router.push('/club/' + c.club_id)
}

const medals = ['🥇','🥈','🥉']
</script>

<template>
  <div>
    <PageHeader icon="🏸" title="My Clubs" subtitle="All clubs you're a member of">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p>Tap a club to switch to it and go to your Home screen.</p>
          <p>Use <strong>Manage</strong> to invite players, change weights, or leave a club.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Empty state -->
    <div v-if="!clubs.length" class="card-neon p-10 text-center fade-up">
      <div class="text-4xl mb-4">🏸</div>
      <p class="font-bold gradient-text text-lg mb-2">You're not in any club yet</p>
      <p class="text-slate-400 text-sm mb-5">Join an existing club or create your own.</p>
      <div class="flex flex-col gap-3">
        <RouterLink to="/explore" class="btn-primary w-full py-3">🌍 Browse &amp; Join</RouterLink>
        <RouterLink to="/manage"  class="btn-ghost  w-full py-3">➕ Create a Club</RouterLink>
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
            {{ currentClub?.club_id === c.club_id ? 'View →' : 'Switch →' }}
          </button>
        </div>

        <!-- Mini leaderboard -->
        <div v-if="boardMap[c.club_id]?.length"
          class="border-t border-slate-100 px-4 py-2">
          <p class="text-[10px] uppercase tracking-widest text-slate-400 mb-2">Top Players</p>
          <div class="space-y-1.5">
            <div v-for="(p, i) in boardMap[c.club_id]" :key="p.id"
              class="flex items-center gap-2">
              <span class="text-sm w-6 text-center shrink-0">{{ medals[i] ?? `#${i+1}` }}</span>
              <RouterLink :to="'/player/' + p.id"
                class="flex-1 text-xs font-medium text-slate-700 hover:text-neon truncate transition-colors">
                {{ p.display_name }}
              </RouterLink>
              <span class="text-xs font-bold text-neon shrink-0">{{ p.composite }}pts</span>
            </div>
          </div>
        </div>

        <div v-else class="border-t border-slate-100 px-4 py-3">
          <p class="text-xs text-slate-400 italic">No matches recorded yet.</p>
        </div>

        <!-- Club actions -->
        <div class="border-t border-slate-100 px-4 py-2 flex gap-3">
          <RouterLink :to="'/club/' + c.club_id"
            class="text-[11px] text-neon hover:opacity-75 transition">
            Club Profile →
          </RouterLink>
          <RouterLink to="/matches"
            class="text-[11px] text-slate-400 hover:text-slate-700 transition">
            Matches →
          </RouterLink>
          <RouterLink to="/manage"
            class="text-[11px] text-slate-400 hover:text-slate-700 transition">
            Manage →
          </RouterLink>
        </div>
      </div>

      <!-- Join / Create -->
      <div class="grid grid-cols-2 gap-3">
        <RouterLink to="/explore" class="btn-ghost text-sm py-3 text-center">
          🌍 Join a Club
        </RouterLink>
        <RouterLink to="/manage" class="btn-ghost text-sm py-3 text-center">
          ➕ Create Club
        </RouterLink>
      </div>
    </div>
  </div>
</template>
