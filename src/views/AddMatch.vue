<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { withNicknames } from '../lib/playerNames'
import { useClub } from '../composables/useClub'

const router = useRouter()
const { currentClub } = useClub()
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

// Guided picking: 'A' = filling Side A, 'B' = filling Side B
const pickingFor = ref('A')

// Schedule-aware player filter
const scheduleId          = ref(null)
const scheduleAttendeeIds = ref(new Set())
const showAllPlayers      = ref(false)

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

onMounted(() => Promise.all([
  loadPlayers(),
  loadNextMatchNum(),
  checkScheduleAttendees(playedOn.value),
]))
watch(currentClub, () => { reset(); loadPlayers(); loadNextMatchNum() })
watch(playedOn, (date) => checkScheduleAttendees(date))

// Wizard-style assignment: tap a player to add to active side; tap assigned player to remove
function assignPlayer(id) {
  if (sideA.value.includes(id)) {
    sideA.value = sideA.value.filter(x => x !== id)
    pickingFor.value = 'A'
    return
  }
  if (sideB.value.includes(id)) {
    sideB.value = sideB.value.filter(x => x !== id)
    return
  }
  if (pickingFor.value === 'A' && sideA.value.length < 2) {
    sideA.value = [...sideA.value, id]
    if (sideA.value.length === 2) pickingFor.value = 'B'
  } else if (pickingFor.value === 'B' && sideB.value.length < 2) {
    sideB.value = [...sideB.value, id]
  }
}

const playerSide = id => sideA.value.includes(id) ? 'A' : sideB.value.includes(id) ? 'B' : null

const ready = computed(() =>
  sideA.value.length === 2 && sideB.value.length === 2 &&
  Number(scoreA.value) !== Number(scoreB.value))

const nameOf = id => players.value.find(p => p.id === id)?.display_name
const eloOf  = id => players.value.find(p => p.id === id)?.elo

const avgElo = arr => arr.length
  ? Math.round(arr.reduce((s, id) => s + (eloOf(id) ?? 1000), 0) / arr.length)
  : null

const autoMatchName = computed(() => {
  if (sideA.value.length < 2 || sideB.value.length < 2) return ''
  const abbrev = id => (nameOf(id) ?? '').slice(0, 2).toUpperCase()
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
  pickingFor.value = 'A'
}

async function doSubmit() {
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
  return error
}

async function submitAndGo() {
  const error = await doSubmit()
  if (error) { msg.value = { ok: false, t: error.message }; return }
  router.push('/matches')
}

async function submitAndStay() {
  const error = await doSubmit()
  if (error) { msg.value = { ok: false, t: error.message }; return }
  msg.value = { ok: true, t: '✅ Match saved! Elo updated for all 4 players.' }
  reset(); loadPlayers(); loadNextMatchNum()
}
</script>

<template>
  <div>

    <!-- Back link -->
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-4 fade-up"
      @click="router.push('/matches')">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
      </svg>
      Match History
    </button>

    <!-- Title -->
    <div class="mb-4 fade-up">
      <h2 class="font-display text-xl font-bold gradient-text">Record Match</h2>
      <p class="text-xs text-slate-400 mt-0.5">Elo ratings update instantly for all 4 players</p>
    </div>

    <!-- Date + Name row -->
    <div class="grid grid-cols-2 gap-3 mb-4">
      <div>
        <label class="label">Match Date</label>
        <input v-model="playedOn" type="date" class="input" />
      </div>
      <div>
        <label class="label">Match Name <span class="text-slate-600">(optional)</span></label>
        <input v-model="matchName" class="input" placeholder="Auto-generated"
          maxlength="40" @input="matchNameEdited = true" />
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

    <!-- Team summary panels -->
    <div class="grid grid-cols-2 gap-2 mb-4">
      <!-- Side A panel -->
      <div class="rounded-2xl p-3 border-2 transition-all"
        :style="pickingFor === 'A' && sideA.length < 2
          ? 'border-color:#00e5ff; background:rgba(0,229,255,.06)'
          : 'border-color:rgba(255,255,255,.1); background:rgba(255,255,255,.02)'">
        <div class="flex items-center gap-1.5 mb-2">
          <span class="w-5 h-5 rounded-md text-[10px] font-black flex items-center justify-center text-slate-950"
            style="background:#00e5ff">A</span>
          <span class="text-xs font-bold text-slate-300">Side A</span>
          <span class="ml-auto text-xs font-bold"
            :class="sideA.length === 2 ? 'text-neon' : 'text-slate-500'">
            {{ sideA.length }}/2
          </span>
        </div>
        <div v-if="sideA.length" class="space-y-1 mb-2">
          <div v-for="id in sideA" :key="id"
            class="text-xs font-medium text-slate-200 truncate">{{ nameOf(id) }}</div>
        </div>
        <div v-else class="text-xs text-slate-600 italic mb-2">Tap players below</div>
        <div v-if="avgElo(sideA)" class="text-[10px] text-slate-500">Avg Elo {{ avgElo(sideA) }}</div>
        <div class="mt-2">
          <label class="text-[10px] text-slate-500 block mb-1">Score</label>
          <input v-model="scoreA" type="number" min="0" max="30"
            class="w-full rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-center font-bold text-lg text-slate-800" />
        </div>
      </div>

      <!-- Side B panel -->
      <div class="rounded-2xl p-3 border-2 transition-all"
        :style="pickingFor === 'B' && sideB.length < 2
          ? 'border-color:#fbbf24; background:rgba(251,191,36,.06)'
          : 'border-color:rgba(255,255,255,.1); background:rgba(255,255,255,.02)'">
        <div class="flex items-center gap-1.5 mb-2">
          <span class="w-5 h-5 rounded-md text-[10px] font-black flex items-center justify-center text-slate-950"
            style="background:#fbbf24">B</span>
          <span class="text-xs font-bold text-slate-300">Side B</span>
          <span class="ml-auto text-xs font-bold"
            :class="sideB.length === 2 ? 'text-gold' : 'text-slate-500'">
            {{ sideB.length }}/2
          </span>
        </div>
        <div v-if="sideB.length" class="space-y-1 mb-2">
          <div v-for="id in sideB" :key="id"
            class="text-xs font-medium text-slate-200 truncate">{{ nameOf(id) }}</div>
        </div>
        <div v-else class="text-xs text-slate-600 italic mb-2">Tap players below</div>
        <div v-if="avgElo(sideB)" class="text-[10px] text-slate-500">Avg Elo {{ avgElo(sideB) }}</div>
        <div class="mt-2">
          <label class="text-[10px] text-slate-500 block mb-1">Score</label>
          <input v-model="scoreB" type="number" min="0" max="30"
            class="w-full rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-center font-bold text-lg text-slate-800" />
        </div>
      </div>
    </div>

    <!-- Guided prompt -->
    <div class="text-center text-xs mb-3"
      :class="sideA.length < 2 || sideB.length < 2 ? 'text-slate-400' : 'text-slate-600'">
      <template v-if="sideA.length < 2">
        Tap {{ 2 - sideA.length }} player{{ 2 - sideA.length > 1 ? 's' : '' }} to add to
        <span class="font-bold text-neon">Side A</span>
      </template>
      <template v-else-if="sideB.length < 2">
        Tap {{ 2 - sideB.length }} player{{ 2 - sideB.length > 1 ? 's' : '' }} to add to
        <span class="font-bold text-gold">Side B</span>
      </template>
      <template v-else>
        All 4 players assigned · Tap any player card to remove them
      </template>
    </div>

    <!-- Player list -->
    <div class="space-y-1.5 mb-4">
      <button v-for="p in displayPlayers" :key="p.id"
        class="w-full flex items-center justify-between px-3 py-2.5 rounded-2xl border text-left transition-all active:scale-[0.98]"
        :class="{
          'border-cyan-400/60 bg-cyan-50/10':    playerSide(p.id) === 'A',
          'border-amber-400/60 bg-amber-50/10':   playerSide(p.id) === 'B',
          'border-[rgba(15,23,42,0.08)] bg-[rgba(15,23,42,0.02)] hover:border-[rgba(15,23,42,0.20)]': !playerSide(p.id),
        }"
        @click="assignPlayer(p.id)">

        <div class="flex items-center gap-2 min-w-0">
          <!-- Team badge or slot indicator -->
          <span v-if="playerSide(p.id) === 'A'"
            class="w-6 h-6 rounded-lg shrink-0 text-[10px] font-black flex items-center justify-center text-slate-950"
            style="background:#00e5ff">A</span>
          <span v-else-if="playerSide(p.id) === 'B'"
            class="w-6 h-6 rounded-lg shrink-0 text-[10px] font-black flex items-center justify-center text-slate-950"
            style="background:#fbbf24">B</span>
          <span v-else
            class="w-6 h-6 rounded-lg shrink-0 border flex items-center justify-center text-slate-600"
            style="border-color:rgba(15,23,42,.1); background:rgba(15,23,42,.04)">+</span>

          <div class="min-w-0">
            <span class="text-sm font-medium truncate block"
              :class="{
                'text-neon font-semibold':    playerSide(p.id) === 'A',
                'text-amber-300 font-semibold': playerSide(p.id) === 'B',
                'text-slate-300':               !playerSide(p.id),
              }">
              {{ p.display_name }}
            </span>
            <span class="text-[10px] text-slate-600">Elo {{ Math.round(p.elo) }}</span>
          </div>
        </div>

        <span v-if="playerSide(p.id)"
          class="text-[10px] text-slate-500 shrink-0 ml-2">tap to remove</span>
      </button>

      <div v-if="!displayPlayers.length" class="rounded-2xl p-4 text-center text-sm text-slate-500 border border-[rgba(15,23,42,0.08)]">
        <span v-if="scheduleId && !showAllPlayers">
          No attendees saved for this schedule.
          <RouterLink to="/schedule" class="text-neon underline ml-1">Set attendees →</RouterLink>
        </span>
        <span v-else>No players yet. Go to 👥 Players to add your roster first.</span>
      </div>
    </div>

    <!-- Validation hint -->
    <div v-if="sideA.length === 2 && sideB.length === 2 && Number(scoreA) === Number(scoreB)"
      class="text-xs text-amber-400 mb-3 text-center">
      Scores cannot be equal — one side must win.
    </div>

    <!-- Submit buttons -->
    <div class="grid grid-cols-2 gap-2">
      <button class="btn-ghost py-3 text-sm font-semibold"
        :disabled="!ready || saving"
        @click="submitAndGo">
        {{ saving ? 'Saving…' : '🏸 Record Match' }}
      </button>
      <button class="btn-primary py-3 text-sm font-semibold"
        :disabled="!ready || saving"
        @click="submitAndStay">
        {{ saving ? 'Saving…' : '➕ Record &amp; Add New' }}
      </button>
    </div>
    <p class="text-center text-xs text-slate-600 mt-1.5">
      Record Match → goes to match list &nbsp;·&nbsp; Record &amp; Add New → stays here
    </p>

    <p v-if="msg" class="mt-3 rounded-xl px-4 py-3 text-sm"
      :class="msg.ok ? 'bg-teal-500/15 text-teal-300' : 'bg-rose-500/15 text-rose-300'">
      {{ msg.t }}
    </p>
  </div>
</template>
