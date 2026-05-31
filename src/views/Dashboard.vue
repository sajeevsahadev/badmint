<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'
import InfoTip from '../components/InfoTip.vue'

const { currentClub } = useClub()
const router   = useRouter()
const board    = ref([])
const bestPair = ref(null)
const loading  = ref(true)

async function load() {
  if (!currentClub.value) return
  loading.value = true
  const cid = currentClub.value.club_id
  const [{ data: lb }, { data: bp }] = await Promise.all([
    supabase.from('v_leaderboard').select('*').eq('club_id', cid).order('club_rank'),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid).limit(1),
  ])
  board.value    = lb ?? []
  bestPair.value = bp?.[0] ?? null
  loading.value  = false
}
onMounted(load)
watch(currentClub, load)

const medals = ['🥇','🥈','🥉']
const podiumColors = [
  'card-amber',   // gold
  'card',         // silver
  'card',         // bronze
]
const trendColor = elo =>
  elo >= 1050 ? 'text-neon' : elo <= 950 ? 'text-rose-400' : 'text-slate-300'
</script>

<template>
  <!-- Skeletons -->
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-16 shimmer rounded-2xl" />
  </div>

  <!-- Empty state -->
  <div v-else-if="!board.length" class="card-neon p-10 text-center fade-up">
    <div class="text-5xl mb-4" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.4));">🏸</div>
    <p class="font-display text-xl font-bold gradient-text mb-2">No matches yet!</p>
    <p class="text-sm text-slate-400 mb-6">Add players first, then record your first match.</p>
    <div class="flex flex-col gap-3">
      <button class="btn-primary" @click="router.push('/players')">Add Players →</button>
      <button class="btn-ghost" @click="router.push('/match')">Record a Match →</button>
    </div>
  </div>

  <template v-else>
    <PageHeader icon="🏆" title="Rankings" subtitle="Skill + attendance · updated after every match">
      <template #help>
        <div class="space-y-1.5 text-xs">
          <p><strong class="text-white">Rank Points</strong> = Skill (70%) + Attendance (30%), both normalised 0–100 within your club.</p>
          <p><strong class="text-white">Elo</strong> is your raw skill rating (starts at 1000). Wins raise it, losses drop it.</p>
          <p><strong class="text-white">W%</strong> is your win percentage across all doubles matches.</p>
          <p><strong class="text-white">Days</strong> is total days you showed up to play.</p>
        </div>
      </template>
    </PageHeader>
    <div class="flex justify-end -mt-3 mb-3">
      <RouterLink v-if="currentClub" :to="'/club/' + currentClub.club_id"
        class="text-[10px] text-neon hover:opacity-75 transition">
        View Club Profile →
      </RouterLink>
    </div>

    <!-- Podium top 3 -->
    <div class="grid grid-cols-3 gap-2 mb-4 fade-up">
      <div v-for="(p, i) in board.slice(0, 3)" :key="p.id"
        :class="[podiumColors[i], 'flex flex-col items-center p-3 text-center transition-all duration-300']">
        <div class="text-2xl mb-1" :style="i === 0 ? 'filter:drop-shadow(0 0 12px rgba(251,191,36,.7))' : ''">
          {{ medals[i] }}
        </div>
        <RouterLink :to="'/player/' + p.id"
          class="text-xs font-bold truncate w-full text-center text-slate-100 hover:text-neon transition-colors">
          {{ p.display_name }}
        </RouterLink>
        <div class="text-[12px] font-extrabold mt-0.5"
          :class="i === 0 ? 'text-gold' : 'text-neon'">
          {{ p.composite }} pts
        </div>
        <div class="text-[10px] text-slate-500">Elo {{ p.elo }}</div>
      </div>
    </div>

    <!-- Best pair -->
    <div v-if="bestPair" class="card-neon mb-4 p-4 fade-up">
      <div class="flex items-center justify-between">
        <div>
          <div class="label mb-0.5">🏅 Best Pair</div>
          <div class="font-bold text-slate-100">{{ bestPair.p1_name }} + {{ bestPair.p2_name }}</div>
          <div class="text-xs text-slate-400 mt-0.5">{{ bestPair.games }} games together</div>
        </div>
        <div class="text-right">
          <div class="text-neon text-2xl font-extrabold">{{ bestPair.win_pct }}%</div>
          <div class="text-xs text-slate-500">{{ bestPair.wins }}W / {{ bestPair.games - bestPair.wins }}L</div>
        </div>
      </div>
    </div>

    <!-- Full leaderboard -->
    <div class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b border-white/[0.06] flex items-center justify-between">
        <span class="text-xs font-bold text-slate-200 tracking-wide">Full Leaderboard</span>
        <InfoTip text="Sorted by composite rank points. Elo = raw skill. W% = win rate. Days = attendance. Pts = blended score." />
      </div>
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-white/[0.05]">
            <th class="px-4 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-500">#</th>
            <th class="px-4 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-500">Player</th>
            <th class="px-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-500">Pts</th>
            <th class="px-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-500">Elo</th>
            <th class="px-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-500">W%</th>
            <th class="px-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-500">Days</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(p, i) in board" :key="p.id"
            class="border-b border-white/[0.04] transition-colors duration-150 cursor-pointer"
            :class="i === 0 ? 'bg-amber-500/[0.04] hover:bg-amber-500/[0.07]' : 'hover:bg-white/[0.02]'"
            @click="router.push('/player/' + p.id)">
            <td class="px-4 py-3 font-bold text-slate-300">{{ medals[i] ?? (i + 1) }}</td>
            <td class="px-4 py-3 font-semibold text-slate-100 hover:text-neon transition-colors">{{ p.display_name }}</td>
            <td class="px-4 py-3 text-right font-extrabold text-neon">{{ p.composite }}</td>
            <td class="px-4 py-3 text-right text-xs font-semibold" :class="trendColor(p.elo)">{{ p.elo }}</td>
            <td class="px-4 py-3 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
            <td class="px-4 py-3 text-right text-xs text-slate-400">{{ p.days_played }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Quick links -->
    <div class="grid grid-cols-2 gap-2 fade-up">
      <button class="card py-3 text-sm text-slate-400 hover:text-neon transition-all duration-200
                     flex items-center justify-center gap-2 hover:border-white/15"
        @click="router.push('/compare')">
        ⚔️ Head-to-Head
      </button>
      <button class="card py-3 text-sm text-slate-400 hover:text-neon transition-all duration-200
                     flex items-center justify-center gap-2 hover:border-white/15"
        @click="router.push('/guide')">
        📖 How Rankings Work
      </button>
    </div>
  </template>
</template>
