<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()
const players      = ref([])
const sideA        = ref([])
const sideB        = ref([])
const scoreA       = ref(21)
const scoreB       = ref(0)
const playedOn     = ref(new Date().toISOString().slice(0, 10))
const matchName    = ref('')
const matchNameEdited = ref(false)
const nextMatchNum = ref(null)
const msg          = ref(null)
const saving       = ref(false)

// Schedule-aware player filter
const scheduleId         = ref(null)
const scheduleAttendeeIds = ref(new Set())
const showAllPlayers     = ref(false)

const displayPlayers = computed(() => {
  if (!scheduleId.value || showAllPlayers.value || scheduleAttendeeIds.value.size === 0) return players.value
  return players.value.filter(p => scheduleAttendeeIds.value.has(p.id))
})

async function checkScheduleAttendees(date) {
  scheduleId.value = null
  scheduleAttendeeIds.value = new Set()
  showAllPlayers.value = false
  if (!currentClub.value || !date) return

  const { data: sched } = await supabase
    .from('club_schedule')
    .select('id')
    .eq('club_id', currentClub.value.club_id)
    .eq('scheduled_date', date)
    .maybeSingle()

  if (!sched) return

  const { data: atts } = await supabase.rpc('get_schedule_attendees', { p_schedule_id: sched.id })
  if (atts?.length) {
    scheduleId.value = sched.id
    scheduleAttendeeIds.value = new Set(atts.map(a => a.player_id))
  }
}

async function loadPlayers() {
  if (!currentClub.value) return
  const { data } = await supabase.from('players')
    .select('id, display_name, elo, user_id')
    .eq('club_id', currentClub.value.club_id)
    .eq('is_active', true)
    .order('display_name')
  players.value = await withNicknames(data ?? [])
}

async function loadNextMatchNum() {
  if (!currentClub.value) return
  const { data } = await supabase
    .from('matches')
    .select('match_number')
    .eq('club_id', currentClub.value.club_id)
    .order('match_number', { ascending: false })
    .limit(1)
    .maybeSingle()
  nextMatchNum.value = (data?.match_number ?? 0) + 1
}

onMounted(async () => {
  await loadPlayers()
  await loadNextMatchNum()
  await checkScheduleAttendees(playedOn.value)
})
watch(currentClub, () => { reset(); loadPlayers(); loadNextMatchNum() })
watch(playedOn, (date) => checkScheduleAttendees(date))

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

const abbrev = id => (nameOf(id) ?? '').slice(0, 2).toUpperCase()

const autoMatchName = computed(() => {
  if (sideA.value.length < 2 || sideB.value.length < 2) return ''
  const a   = sideA.value.map(abbrev).join('-')
  const b   = sideB.value.map(abbrev).join('-')
  const num = nextMatchNum.value ? `#${nextMatchNum.value} ` : ''
  return `${num}${a} VS ${b}`
})

watch(autoMatchName, newName => {
  if (!matchNameEdited.value) matchName.value = newName
})

function reset() {
  sideA.value = []; sideB.value = []
  scoreA.value = 21; scoreB.value = 0
  matchName.value = ''; matchNameEdited.value = false; msg.value = null
}

async function submit() {
  msg.value = null; saving.value = true
  const { error } = await supabase.rpc('record_match', {
    p_club_id:      currentClub.value.club_id,
    p_played_on:    playedOn.value,
    p_side_a:       sideA.value,
    p_side_b:       sideB.value,
    p_score_a:      Number(scoreA.value),
    p_score_b:      Number(scoreB.value),
    p_display_name: matchName.value.trim() || null
  })
  saving.value = false
  if (error) { msg.value = { ok: false, t: error.message }; return }
  msg.value = { ok: true, t: '✅ Match saved! Elo + attendance updated for all 4 players.' }
  reset(); loadPlayers(); loadNextMatchNum()
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
          <p><strong class="text-slate-800">Step 1</strong> — Set the date (defaults to today).</p>
          <p><strong class="text-slate-800">Step 2</strong> — Tap <span class="text-teal-400">A</span> or <span class="text-amber-400">B</span> next to each player to assign them to a side. Each side needs exactly 2 players.</p>
          <p><strong class="text-slate-800">Step 3</strong> — Enter the final score for each side.</p>
          <p><strong class="text-slate-800">Step 4</strong> — Hit Record. Elo is recalculated and attendance is marked for all 4 players automatically.</p>
          <p class="text-slate-500">Scores cannot be equal (a match must have a winner). Badminton standard: first to 21.</p>
        </div>
      </template>
    </PageHeader>

    <!-- Date + Name row -->
    <div class="grid grid-cols-2 gap-3 mb-4">
      <div>
        <label class="label">Match Date</label>
        <input v-model="playedOn" type="date" class="input" />
      </div>
      <div>
        <label class="label">Match Name <span class="text-slate-600">(optional)</span></label>
        <input v-model="matchName" class="input" placeholder="Auto-generated from player names" maxlength="40"
          @input="matchNameEdited = true" />
      </div>
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
            class="w-full rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-center font-bold text-lg text-slate-800" />
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
            class="w-full rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-center font-bold text-lg text-slate-800" />
        </div>
      </div>
    </div>

    <!-- Schedule attendees banner -->
    <div v-if="scheduleId && scheduleAttendeeIds.size > 0"
      class="rounded-xl px-3 py-2.5 mb-3 flex items-center gap-2 text-xs"
      style="background:rgba(0,229,255,.08); border:1px solid rgba(0,229,255,.2)">
      <span class="text-neon shrink-0">📅</span>
      <span class="flex-1 text-slate-300">
        Showing <strong class="text-neon">{{ scheduleAttendeeIds.size }}</strong> attendees from today's schedule
      </span>
      <button class="text-slate-500 underline shrink-0"
        @click="showAllPlayers = !showAllPlayers">
        {{ showAllPlayers ? 'filter' : 'show all' }}
      </button>
    </div>

    <!-- Player list -->
    <div class="label mb-2">Tap to assign players to sides</div>
    <div class="space-y-1.5 mb-4">
      <div v-for="p in displayPlayers" :key="p.id"
        class="card flex items-center justify-between px-3 py-2.5 transition"
        :class="chosen.has(p.id) ? 'bg-slate-50' : ''">
        <div>
          <span class="font-medium text-sm" :class="chosen.has(p.id) ? 'text-slate-900 font-semibold' : 'text-slate-500'">
            {{ p.display_name }}
          </span>
          <span class="ml-2 text-[10px] text-slate-600">Elo {{ Math.round(p.elo) }}</span>
        </div>
        <div class="flex gap-1.5">
          <button class="w-8 h-8 rounded-lg text-xs font-bold transition"
            :class="sideA.includes(p.id) ? 'bg-teal-500 text-slate-950' : 'border border-slate-200 text-slate-500 hover:border-teal-400'"
            @click="toggle('A', p.id)">A</button>
          <button class="w-8 h-8 rounded-lg text-xs font-bold transition"
            :class="sideB.includes(p.id) ? 'bg-amber-400 text-slate-950' : 'border border-slate-200 text-slate-500 hover:border-amber-400'"
            @click="toggle('B', p.id)">B</button>
        </div>
      </div>
      <div v-if="!displayPlayers.length" class="card p-4 text-center text-sm text-slate-500">
        <span v-if="scheduleId && !showAllPlayers">
          No attendees saved for this schedule yet.
          <RouterLink to="/schedule" class="text-neon underline ml-1">Set attendees →</RouterLink>
        </span>
        <span v-else>No players yet. Go to 👥 Players tab to add your team roster first.</span>
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
