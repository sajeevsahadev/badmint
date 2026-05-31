<script setup>
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { clubs, currentClub, loadClubs, createClub, isManager } = useClub()
const newClub = ref('')
const cfg     = ref(null)
const members = ref([])
const note    = ref(null)
const busy    = ref(false)

async function load() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id
  const [{ data: c }, { data: m }] = await Promise.all([
    supabase.from('ranking_config').select('*').eq('club_id', cid).single(),
    supabase.from('club_members').select('user_id, role').eq('club_id', cid)
  ])
  cfg.value = c
  members.value = m ?? []
}
onMounted(() => { loadClubs(); load() })
watch(currentClub, load)

async function make() {
  if (!newClub.value.trim()) return
  busy.value = true; note.value = null
  try {
    await createClub(newClub.value.trim())
    newClub.value = ''
    note.value = { ok: true, t: '✅ Club created! You are now the owner. Add players in the Players tab.' }
  } catch (e) {
    note.value = { ok: false, t: e.message }
  }
  busy.value = false
}

async function saveCfg() {
  const { elo_weight, participation_weight, k_factor } = cfg.value
  const sum = Number(elo_weight) + Number(participation_weight)
  if (Math.abs(sum - 1) > 0.01) {
    note.value = { ok: false, t: `Skill + Attendance must add up to 1.0 (currently ${sum.toFixed(2)}).` }; return
  }
  busy.value = true; note.value = null
  const { error } = await supabase.from('ranking_config').update({ elo_weight, participation_weight, k_factor })
    .eq('club_id', currentClub.value.club_id)
  busy.value = false
  if (error) {
    note.value = { ok: false, t: `Save failed: ${error.message}` }
  } else {
    note.value = { ok: true, t: '✅ Ranking weights saved. Leaderboard will update immediately.' }
  }
}

const roleLabel = r => ({ owner: '👑 Owner', manager: '🛠 Manager', player: '🏸 Player' }[r] ?? r)
</script>

<template>
  <PageHeader icon="⚙️" title="Manage" subtitle="Clubs, members, and ranking settings">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-white">Create a Club</strong> — Each club is a separate team with its own roster, matches, and leaderboard. You become the owner.</p>
        <p><strong class="text-white">Roles:</strong> 👑 Owner has full control. 🛠 Manager can add players and record matches. 🏸 Player can only view dashboards.</p>
        <p><strong class="text-white">Ranking Weights</strong> — Tune how much skill vs attendance affects the composite rank. Must add up to 1.0.</p>
        <p><strong class="text-white">K-factor</strong> — Controls Elo volatility. Lower (8–16) = slow, stable changes. Higher (24–48) = fast, reactive changes. Default 24 is ideal for casual groups.</p>
        <p><strong class="text-white">Multiple clubs</strong> — Use the club switcher in the top bar to jump between clubs (e.g. your court vs the court next door).</p>
      </div>
    </template>
  </PageHeader>

  <!-- Create club -->
  <div class="card p-4 mb-4">
    <div class="label">Create a New Club / Team</div>
    <div class="flex gap-2">
      <input v-model="newClub" class="input" placeholder="e.g. Kore Smashers, Court B Team…"
        @keyup.enter="make" maxlength="50" />
      <button class="btn-primary shrink-0 px-4" :disabled="busy || !newClub.trim()" @click="make">
        Create
      </button>
    </div>
    <p class="text-[11px] text-slate-500 mt-2">
      Each club has its own players, matches, and leaderboard. You can create unlimited clubs and switch between them using the team selector at the top.
    </p>
  </div>

  <!-- Ranking weights -->
  <div v-if="currentClub && isManager() && cfg" class="card p-4 mb-4">
    <div class="label">Ranking Weights — {{ currentClub.clubs?.name }}</div>
    <div class="grid grid-cols-3 gap-3 mb-3">
      <div>
        <label class="label">Skill (Elo)</label>
        <input v-model.number="cfg.elo_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">How much skill matters</div>
      </div>
      <div>
        <label class="label">Attendance</label>
        <input v-model.number="cfg.participation_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">How much regularity matters</div>
      </div>
      <div>
        <label class="label">K-factor</label>
        <input v-model.number="cfg.k_factor" type="number" min="8" max="64" step="4" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Elo swing per match</div>
      </div>
    </div>
    <div class="rounded-xl bg-white/5 px-3 py-2 text-xs text-slate-400 mb-3">
      Current split: Skill <strong class="text-teal-400">{{ Math.round(cfg.elo_weight * 100) }}%</strong>
      + Attendance <strong class="text-purple-400">{{ Math.round(cfg.participation_weight * 100) }}%</strong>
      = {{ Math.round((cfg.elo_weight + cfg.participation_weight) * 100) }}%
      <span v-if="Math.abs(cfg.elo_weight + cfg.participation_weight - 1) > 0.01" class="text-amber-400"> ⚠️ must equal 100%</span>
      <span v-else class="text-teal-400"> ✓</span>
    </div>
    <p v-if="note" class="rounded-xl px-3 py-2 text-xs mb-3"
      :class="note.ok ? 'bg-teal-500/15 text-teal-300' : 'bg-rose-500/15 text-rose-300'">
      {{ note.t }}
    </p>
    <button class="btn-ghost w-full" :disabled="busy" @click="saveCfg">Save Ranking Weights</button>
  </div>

  <!-- Members -->
  <div v-if="currentClub && members.length" class="card p-4 mb-4">
    <div class="label">Members — {{ currentClub.clubs?.name }}</div>
    <div v-for="m in members" :key="m.user_id"
      class="flex justify-between py-2 border-b border-white/5 last:border-0 text-sm">
      <span class="text-slate-400 text-xs font-mono truncate">{{ m.user_id.slice(0, 12) }}…</span>
      <span class="text-xs">{{ roleLabel(m.role) }}</span>
    </div>
    <p class="text-[11px] text-slate-500 mt-3">
      To promote someone to Manager: they must sign in first, then update their role in the
      Supabase dashboard under Table Editor → club_members.
    </p>
  </div>

  <!-- Club list -->
  <div v-if="clubs.length" class="card p-4">
    <div class="label">Your Clubs</div>
    <div v-for="c in clubs" :key="c.club_id"
      class="flex items-center justify-between py-2 border-b border-white/5 last:border-0">
      <div>
        <div class="text-sm font-medium">{{ c.clubs?.name }}</div>
        <div class="text-[10px] text-slate-500">{{ roleLabel(c.role) }}</div>
      </div>
      <div v-if="currentClub?.club_id === c.club_id"
        class="text-[10px] text-teal-400 border border-teal-500/30 rounded-full px-2 py-0.5">Active</div>
    </div>
  </div>

  <p v-if="note" class="mt-3 rounded-xl px-4 py-3 text-sm"
    :class="note.ok ? 'bg-teal-500/15 text-teal-300' : 'bg-rose-500/15 text-rose-300'">
    {{ note.t }}
  </p>
</template>
