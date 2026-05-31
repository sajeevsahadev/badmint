<script setup>
import { ref, watch, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'
import InfoTip from '../components/InfoTip.vue'

const { currentClub } = useClub()
const router = useRouter()
const board  = ref([])
const bestPair = ref(null)
const loading  = ref(true)

async function load() {
  if (!currentClub.value) return
  loading.value = true
  const cid = currentClub.value.club_id
  const [{ data: lb }, { data: bp }] = await Promise.all([
    supabase.from('v_leaderboard').select('*').eq('club_id', cid).order('club_rank'),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid).limit(1)
  ])
  board.value = lb ?? []
  bestPair.value = bp?.[0] ?? null
  loading.value = false
}
onMounted(load)
watch(currentClub, load)

const medal = i => ['🥇','🥈','🥉'][i] ?? (i + 1)
const trendColor = elo => elo >= 1050 ? 'text-teal-400' : elo <= 950 ? 'text-rose-400' : 'text-slate-300'
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 3" :key="i" class="card h-16 animate-pulse bg-white/5" />
  </div>

  <div v-else-if="!board.length" class="card p-8 text-center">
    <div class="text-4xl mb-3">🏸</div>
    <p class="font-semibold mb-1">No matches yet!</p>
    <p class="text-sm text-slate-400 mb-4">
      Add your players first, then record your first match to see the leaderboard.
    </p>
    <div class="flex flex-col gap-2">
      <button class="btn-primary" @click="router.push('/players')">Add Players →</button>
      <button class="btn-ghost" @click="router.push('/match')">Record a Match →</button>
    </div>
  </div>

  <template v-else>
    <PageHeader icon="🏆" title="Rankings" subtitle="Skill + attendance, updated live after every match">
      <template #help>
        <div class="space-y-1.5 text-xs">
          <p><strong class="text-white">Rank Points</strong> = Skill (70%) + Attendance (30%), both normalised 0–100 within your club.</p>
          <p><strong class="text-white">Elo</strong> is your raw skill rating (starts at 1000). It rises when you win and falls when you lose.</p>
          <p><strong class="text-white">W%</strong> is your win percentage across all doubles matches.</p>
          <p><strong class="text-white">Days</strong> is total days you showed up to play.</p>
          <p class="text-slate-500">Tap <span class="text-teal-400">📖 How it works</span> below for the full explainer.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Podium top 3 -->
    <div class="grid grid-cols-3 gap-2 mb-4">
      <div v-for="(p, i) in board.slice(0, 3)" :key="p.id"
        class="card flex flex-col items-center p-3 text-center transition"
        :class="i === 0 ? 'ring-1 ring-amber-400/40 bg-amber-400/5' : ''">
        <div class="text-2xl">{{ ['🥇','🥈','🥉'][i] }}</div>
        <div class="mt-1 text-xs font-semibold truncate w-full text-center">{{ p.display_name }}</div>
        <div class="text-[11px] text-teal-400 font-bold">{{ p.composite }} pts</div>
        <div class="text-[10px] text-slate-500">Elo {{ p.elo }}</div>
      </div>
    </div>

    <!-- Best pair -->
    <div v-if="bestPair" class="card mb-4 p-4 border-teal-500/20 border">
      <div class="flex items-center justify-between">
        <div>
          <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-0.5">🏅 Best Pair</div>
          <div class="font-semibold text-sm">{{ bestPair.p1_name }} + {{ bestPair.p2_name }}</div>
          <div class="text-xs text-slate-400">{{ bestPair.games }} games together</div>
        </div>
        <div class="text-right">
          <div class="text-teal-400 text-xl font-bold">{{ bestPair.win_pct }}%</div>
          <div class="text-xs text-slate-500">{{ bestPair.wins }}W / {{ bestPair.games - bestPair.wins }}L</div>
        </div>
      </div>
    </div>

    <!-- Full leaderboard -->
    <div class="card overflow-hidden mb-4">
      <div class="px-3 py-2 border-b border-white/5 flex items-center justify-between">
        <span class="text-xs font-semibold text-slate-300">Full Leaderboard</span>
        <InfoTip text="Sorted by composite rank points. Elo = raw skill. W% = win rate. Days = attendance. Pts = blended composite score." />
      </div>
      <table class="w-full text-sm">
        <thead class="text-[10px] uppercase tracking-wider text-slate-500">
          <tr class="border-b border-white/5">
            <th class="px-3 py-2 text-left">#</th>
            <th class="px-3 py-2 text-left">Player</th>
            <th class="px-3 py-2 text-right">Pts</th>
            <th class="px-3 py-2 text-right">Elo</th>
            <th class="px-3 py-2 text-right">W%</th>
            <th class="px-3 py-2 text-right">Days</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(p, i) in board" :key="p.id"
            class="border-b border-white/[0.04] hover:bg-white/[0.02] transition">
            <td class="px-3 py-2.5 text-sm">{{ medal(i) }}</td>
            <td class="px-3 py-2.5 font-medium text-slate-200">{{ p.display_name }}</td>
            <td class="px-3 py-2.5 text-right font-bold text-teal-400">{{ p.composite }}</td>
            <td class="px-3 py-2.5 text-right text-xs" :class="trendColor(p.elo)">{{ p.elo }}</td>
            <td class="px-3 py-2.5 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
            <td class="px-3 py-2.5 text-right text-xs text-slate-400">{{ p.days_played }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Guide link -->
    <button class="w-full card p-3 text-sm text-slate-400 hover:text-teal-400 transition flex items-center justify-center gap-2"
      @click="router.push('/guide')">
      📖 How does the ranking work? <span class="text-teal-500">Learn more →</span>
    </button>
  </template>
</template>
