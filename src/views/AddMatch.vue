<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()
const players  = ref([])
const sideA    = ref([])
const sideB    = ref([])
const scoreA   = ref(21)
const scoreB   = ref(0)
const playedOn = ref(new Date().toISOString().slice(0, 10))
const msg      = ref(null)
const saving   = ref(false)

async function loadPlayers() {
  if (!currentClub.value) return
  const { data } = await supabase.from('players')
    .select('id, display_name, elo')
    .eq('club_id', currentClub.value.club_id)
    .eq('is_active', true)
    .order('display_name')
  players.value = data ?? []
}
onMounted(loadPlayers)
watch(currentClub, () => { reset(); loadPlayers() })

const chosen = computed(() => new Set([...sideA.value, ...sideB.value]))

function toggle(side, id) {
  const arr   = side === 'A' ? sideA : sideB
  const other = side === 'A' ? sideB : sideA
  if (arr.value.includes(id)) { arr.value = arr.value.filter(x => x !== id); return }
  if (other.value.includes(id)) other.value = other.value.filter(x => x !== id)
  if (arr.value.length >= 2) return
  arr.value = [...arr.value, id]
}

const ready = computed(() =>
  sideA.value.length === 2 && sideB.value.length === 2 &&
  Number(scoreA.value) !== Number(scoreB.value))

const nameOf = id => players.value.find(p => p.id === id)?.display_name
const eloOf  = id => players.value.find(p => p.id === id)?.elo

const avgElo = arr => arr.length
  ? Math.round(arr.reduce((s, id) => s + (eloOf(id) ?? 1000), 0) / arr.length)
  : '—'

function reset() {
  sideA.value = []; sideB.value = []
  scoreA.value = 21; scoreB.value = 0
  msg.value = null
}

async function submit() {
  msg.value = null; saving.value = true
  const { error } = await supabase.rpc('record_match', {
    p_club_id:   currentClub.value.club_id,
    p_played_on: playedOn.value,
    p_side_a:    sideA.value,
    p_side_b:    sideB.value,
    p_score_a:   Number(scoreA.value),
    p_score_b:   Number(scoreB.value)
  })
  saving.value = false
  if (error) { msg.value = { ok: false, t: error.message }; return }
  msg.value = { ok: true, t: '✅ Match saved! Elo + attendance updated for all 4 players.' }
  reset(); loadPlayers()
}
</script>

<template>
  <div v-if="!isManager()" class="card p-6 text-center">
    <div class="text-3xl mb-3">🔒</div>
    <p class="font-semibold">Managers only</p>
    <p class="text-sm text-slate-400 mt-1">Only club owners and managers can record matches. Contact your manager.</p>
  </div>

  <template v-else>
    <PageHeader icon="➕" title="Add Match" subtitle="Record a doubles result — Elo updates instantly">
      <template #help>
        <div class="text-xs space-y-1.5">
          <p><strong class="text-white">Step 1</strong> — Set the date (defaults to today).</p>
          <p><strong class="text-white">Step 2</strong> — Tap <span class="text-teal-400">A</span> or <span class="text-amber-400">B</span> next to each player to assign them to a side. Each side needs exactly 2 players.</p>
          <p><strong class="text-white">Step 3</strong> — Enter the final score for each side.</p>
          <p><strong class="text-white">Step 4</strong> — Hit Record. Elo is recalculated and attendance is marked for all 4 players automatically.</p>
          <p class="text-slate-500">Scores cannot be equal (a match must have a winner). Badminton standard: first to 21.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Date -->
    <div class="mb-4">
      <label class="label">Match Date</label>
      <input v-model="playedOn" type="date" class="input" />
    </div>

    <!-- Side panels -->
    <div class="grid grid-cols-2 gap-3 mb-4">
      <div class="card p-3 border-teal-500/30 border">
        <div class="text-[10px] uppercase tracking-widest text-teal-400 mb-2">Side A</div>
        <div class="text-xs text-slate-400 mb-2">{{ sideA.length }}/2 players • Avg Elo {{ avgElo(sideA) }}</div>
        <div v-if="sideA.length" class="space-y-1">
          <div v-for="id in sideA" :key="id" class="text-xs font-medium truncate text-slate-200">{{ nameOf(id) }}</div>
        </div>
        <div v-else class="text-xs text-slate-600 italic">Tap A to assign</div>
        <div class="mt-3">
          <label class="text-[10px] text-slate-500">Score</label>
          <input v-model="scoreA" type="number" min="0" max="30"
            class="w-full rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-center font-bold text-lg" />
        </div>
      </div>

      <div class="card p-3 border-amber-500/30 border">
        <div class="text-[10px] uppercase tracking-widest text-amber-400 mb-2">Side B</div>
        <div class="text-xs text-slate-400 mb-2">{{ sideB.length }}/2 players • Avg Elo {{ avgElo(sideB) }}</div>
        <div v-if="sideB.length" class="space-y-1">
          <div v-for="id in sideB" :key="id" class="text-xs font-medium truncate text-slate-200">{{ nameOf(id) }}</div>
        </div>
        <div v-else class="text-xs text-slate-600 italic">Tap B to assign</div>
        <div class="mt-3">
          <label class="text-[10px] text-slate-500">Score</label>
          <input v-model="scoreB" type="number" min="0" max="30"
            class="w-full rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-center font-bold text-lg" />
        </div>
      </div>
    </div>

    <!-- Player list -->
    <div class="label mb-2">Tap to assign players to sides</div>
    <div class="space-y-1.5 mb-4">
      <div v-for="p in players" :key="p.id"
        class="card flex items-center justify-between px-3 py-2.5 transition"
        :class="chosen.has(p.id) ? 'bg-white/5' : ''">
        <div>
          <span class="font-medium text-sm" :class="chosen.has(p.id) ? 'text-white' : 'text-slate-400'">
            {{ p.display_name }}
          </span>
          <span class="ml-2 text-[10px] text-slate-600">Elo {{ Math.round(p.elo) }}</span>
        </div>
        <div class="flex gap-1.5">
          <button class="w-8 h-8 rounded-lg text-xs font-bold transition"
            :class="sideA.includes(p.id) ? 'bg-teal-500 text-slate-950' : 'border border-white/15 text-slate-400 hover:border-teal-500'"
            @click="toggle('A', p.id)">A</button>
          <button class="w-8 h-8 rounded-lg text-xs font-bold transition"
            :class="sideB.includes(p.id) ? 'bg-amber-400 text-slate-950' : 'border border-white/15 text-slate-400 hover:border-amber-500'"
            @click="toggle('B', p.id)">B</button>
        </div>
      </div>
      <div v-if="!players.length" class="card p-4 text-center text-sm text-slate-500">
        No players yet. Go to 👥 Players tab to add your team roster first.
      </div>
    </div>

    <!-- Validation hints -->
    <div v-if="sideA.length < 2 || sideB.length < 2" class="text-xs text-slate-500 mb-3 text-center">
      Assign 2 players to each side to enable recording.
    </div>
    <div v-else-if="Number(scoreA) === Number(scoreB)" class="text-xs text-amber-400 mb-3 text-center">
      Scores cannot be equal — one side must win.
    </div>

    <button class="btn-primary w-full py-3" :disabled="!ready || saving" @click="submit">
      {{ saving ? 'Saving…' : '🏸 Record Match' }}
    </button>

    <p v-if="msg" class="mt-3 rounded-xl px-4 py-3 text-sm"
      :class="msg.ok ? 'bg-teal-500/15 text-teal-300' : 'bg-rose-500/15 text-rose-300'">
      {{ msg.t }}
    </p>
  </template>
</template>
