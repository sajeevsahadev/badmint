<script setup>
import { ref, watch, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { currentClub } = useClub()
const players = ref([])
const a = ref('')
const b = ref('')
const h2h   = ref(null)
const pairs = ref([])
const ranks = ref({})

async function load() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id
  const [{ data: pl }, { data: lb }, { data: bp }] = await Promise.all([
    supabase.from('players').select('id, display_name, user_id').eq('club_id', cid).order('display_name'),
    supabase.from('v_leaderboard').select('id, club_rank, elo, composite, win_pct, days_played, games, wins').eq('club_id', cid),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid).order('win_pct', { ascending: false }).limit(5)
  ])
  players.value = await withNicknames(pl ?? [])
  ranks.value = Object.fromEntries((lb ?? []).map(r => [r.id, r]))
  pairs.value = bp ?? []
}
onMounted(load)
watch(currentClub, load)

async function compare() {
  h2h.value = null
  if (!a.value || !b.value || a.value === b.value) return
  // check both orderings (A vs B and B vs A)
  const [{ data: d1 }, { data: d2 }] = await Promise.all([
    supabase.from('v_head_to_head').select('*').eq('club_id', currentClub.value.club_id)
      .eq('player_a', a.value).eq('player_b', b.value).maybeSingle(),
    supabase.from('v_head_to_head').select('*').eq('club_id', currentClub.value.club_id)
      .eq('player_a', b.value).eq('player_b', a.value).maybeSingle()
  ])
  if (d1) { h2h.value = d1; return }
  if (d2) { h2h.value = { ...d2, player_a: d2.player_b, player_b: d2.player_a, a_wins: d2.b_wins, b_wins: d2.a_wins }; return }
  h2h.value = { meetings: 0, a_wins: 0, b_wins: 0 }
}
watch([a, b], compare)

const nameOf = id => players.value.find(p => p.id === id)?.display_name
const rA = computed(() => ranks.value[a.value])
const rB = computed(() => ranks.value[b.value])

const statRows = computed(() => {
  if (!rA.value || !rB.value) return []
  return [
    { label: 'Rank',     vA: '#' + rA.value.club_rank,  vB: '#' + rB.value.club_rank, betterLow: true },
    { label: 'Points',   vA: rA.value.composite,        vB: rB.value.composite },
    { label: 'Elo',      vA: rA.value.elo,              vB: rB.value.elo },
    { label: 'Win %',    vA: rA.value.win_pct + '%',    vB: rB.value.win_pct + '%' },
    { label: 'Games',    vA: rA.value.games,            vB: rB.value.games },
    { label: 'Days',     vA: rA.value.days_played,      vB: rB.value.days_played }
  ]
})
const better = (row, side) => {
  const va = parseFloat(String(row.vA))
  const vb = parseFloat(String(row.vB))
  if (isNaN(va) || isNaN(vb) || va === vb) return false
  return side === 'A' ? (row.betterLow ? va < vb : va > vb) : (row.betterLow ? vb < va : vb > va)
}
</script>

<template>
  <PageHeader icon="⚔️" title="Compare Players" subtitle="Head-to-head stats and ranking comparison">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-slate-800">Rank comparison</strong> shows both players' full stat profile side by side — composite points, Elo, win rate, games played, and attendance.</p>
        <p><strong class="text-slate-800">Head-to-head</strong> counts every match where they were on <em>opposite sides</em>. If they've only played as partners, the head-to-head will show 0.</p>
        <p><strong class="text-slate-800">Best Pairs</strong> at the bottom shows which player combinations have the highest win rate when on the same side.</p>
      </div>
    </template>
  </PageHeader>

  <!-- Player selectors -->
  <div class="grid grid-cols-2 gap-3 mb-4">
    <div>
      <label class="label text-teal-400">Player A</label>
      <select v-model="a" class="input">
        <option value="" disabled>Select player</option>
        <option v-for="p in players" :key="p.id" :value="p.id" :disabled="p.id === b">{{ p.display_name }}</option>
      </select>
    </div>
    <div>
      <label class="label text-amber-400">Player B</label>
      <select v-model="b" class="input">
        <option value="" disabled>Select player</option>
        <option v-for="p in players" :key="p.id" :value="p.id" :disabled="p.id === a">{{ p.display_name }}</option>
      </select>
    </div>
  </div>

  <!-- Comparison table -->
  <div v-if="rA && rB" class="card overflow-hidden mb-4">
    <div class="grid grid-cols-3 border-b border-white/10 py-3 px-3 text-center">
      <div class="font-semibold text-teal-400">{{ nameOf(a) }}</div>
      <div class="text-xs text-slate-500 self-center">vs</div>
      <div class="font-semibold text-amber-400">{{ nameOf(b) }}</div>
    </div>
    <div v-for="row in statRows" :key="row.label"
      class="grid grid-cols-3 px-3 py-2 border-b border-white/[0.04] last:border-0 text-center text-sm">
      <div :class="better(row, 'A') ? 'text-slate-900 font-bold' : 'text-slate-400'">{{ row.vA }}</div>
      <div class="text-[10px] text-slate-500 self-center uppercase tracking-wider">{{ row.label }}</div>
      <div :class="better(row, 'B') ? 'text-slate-900 font-bold' : 'text-slate-400'">{{ row.vB }}</div>
    </div>
  </div>

  <!-- Head to head -->
  <div v-if="h2h && rA && rB" class="card p-4 mb-4">
    <div class="label mb-3">Head-to-head — opposite sides only</div>
    <div v-if="h2h.meetings" class="grid grid-cols-3 items-center text-center">
      <div>
        <div class="text-3xl font-bold text-teal-400">{{ h2h.a_wins }}</div>
        <div class="text-xs text-slate-500">wins</div>
      </div>
      <div class="text-xs text-slate-400">{{ h2h.meetings }} matches<br>face-to-face</div>
      <div>
        <div class="text-3xl font-bold text-amber-400">{{ h2h.b_wins }}</div>
        <div class="text-xs text-slate-500">wins</div>
      </div>
    </div>
    <p v-else class="text-center text-sm text-slate-500">
      These two players have never been on opposite sides yet.
    </p>
  </div>

  <!-- Best pairs table -->
  <div v-if="pairs.length" class="card overflow-hidden">
    <div class="px-3 py-2 border-b border-white/5">
      <div class="text-xs font-semibold text-slate-300">🏅 Best Pairs in Club</div>
      <div class="text-[10px] text-slate-500">Highest win rate when playing together</div>
    </div>
    <div v-for="p in pairs" :key="p.p1 + p.p2"
      class="flex items-center justify-between px-3 py-2.5 border-b border-white/[0.04] last:border-0">
      <div>
        <div class="text-sm font-medium">{{ p.p1_name }} + {{ p.p2_name }}</div>
        <div class="text-xs text-slate-500">{{ p.games }} games together</div>
      </div>
      <div class="text-right">
        <div class="font-bold text-teal-400">{{ p.win_pct }}%</div>
        <div class="text-[10px] text-slate-500">{{ p.wins }}W {{ p.games - p.wins }}L</div>
      </div>
    </div>
  </div>

  <div v-if="!players.length" class="card p-6 text-center text-slate-400 text-sm">
    Add players and record matches first to see comparisons.
  </div>
</template>
