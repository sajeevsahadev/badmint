<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { isManager } = useClub()

const data    = ref(null)
const loading = ref(true)
const busy    = ref('')
const err     = ref('')
const ok      = ref('')
const tab     = ref('registrations') // registrations | bracket | settings

// Score recording
const scoreModal   = ref(null) // { match, scoreA: '', scoreB: '' }
const scoreBusy    = ref(false)
const scoreErr     = ref('')

// Settings edit
const settings = ref({})
const settingsBusy = ref(false)
const settingsOk   = ref(false)

async function load() {
  loading.value = true
  const { data: d, error } = await supabase.rpc('get_tournament_detail', {
    p_tournament_id: route.params.id
  })
  if (error || !d) { loading.value = false; return }
  data.value = d
  if (d.tournament) {
    settings.value = {
      name:             d.tournament.name,
      venue:            d.tournament.venue ?? '',
      venue_address:    d.tournament.venue_address ?? '',
      emirate:          d.tournament.emirate ?? '',
      entry_fee:        d.tournament.entry_fee ?? '',
      prize_info:       d.tournament.prize_info ?? '',
      description:      d.tournament.description ?? '',
      registration_end: d.tournament.registration_end ?? '',
      start_date:       d.tournament.start_date ?? '',
      end_date:         d.tournament.end_date ?? '',
      max_teams:        d.tournament.max_teams ?? 8,
    }
  }
  loading.value = false
}

onMounted(load)

const tour          = computed(() => data.value?.tournament)
const registrations = computed(() => data.value?.registrations ?? [])
const matches       = computed(() => data.value?.matches ?? [])

const confirmed = computed(() => registrations.value.filter(r => r.status === 'confirmed'))
const pending   = computed(() => registrations.value.filter(r => r.status === 'pending'))

const roundsMap = computed(() => {
  const m = {}
  matches.value.forEach(match => {
    if (!m[match.round]) m[match.round] = []
    m[match.round].push(match)
  })
  return m
})
const rounds = computed(() =>
  Object.entries(roundsMap.value).map(([r, ms]) => ({
    round: Number(r),
    matches: ms.sort((a, b) => a.position - b.position)
  })).sort((a, b) => a.round - b.round)
)
const totalRounds = computed(() => rounds.value.length)
const roundLabel = (r, total) => {
  if (tour.value?.format === 'round_robin') return 'All Matches'
  const fromEnd = total - r
  if (fromEnd === 0) return 'Final'
  if (fromEnd === 1) return 'Semi'
  if (fromEnd === 2) return 'Quarter'
  return `R${r}`
}

const emirates = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

async function setStatus(newStatus) {
  err.value = ''; ok.value = ''; busy.value = 'status'
  const { error } = await supabase.rpc('update_tournament_status', {
    p_tournament_id: tour.value.id,
    p_status: newStatus
  })
  busy.value = ''
  if (error) { err.value = error.message; return }
  ok.value = 'Status updated'
  await load()
}

async function approve(regId) {
  busy.value = 'reg-' + regId
  const { error } = await supabase.rpc('approve_registration', { p_reg_id: regId })
  busy.value = ''
  if (error) { err.value = error.message; return }
  await load()
}

async function reject(regId) {
  busy.value = 'reg-' + regId
  await supabase.rpc('reject_registration', { p_reg_id: regId })
  busy.value = ''
  await load()
}

async function setSeed(regId, seed) {
  await supabase.rpc('set_seed', { p_reg_id: regId, p_seed: Number(seed) })
  await load()
}

async function generateBracket() {
  err.value = ''; busy.value = 'bracket'
  const { error } = await supabase.rpc('generate_bracket', {
    p_tournament_id: tour.value.id
  })
  busy.value = ''
  if (error) { err.value = error.message; return }
  ok.value = 'Bracket generated! Tournament is now Live.'
  tab.value = 'bracket'
  await load()
}

function openScoreModal(m) {
  scoreErr.value = ''
  scoreModal.value = { match: m, scoreA: '', scoreB: '' }
}

async function submitScore() {
  scoreErr.value = ''
  const m = scoreModal.value
  if (!m.scoreA || !m.scoreB) { scoreErr.value = 'Enter both scores'; return }
  if (Number(m.scoreA) === Number(m.scoreB)) { scoreErr.value = 'Scores cannot be equal'; return }
  scoreBusy.value = true
  const { error } = await supabase.rpc('record_tournament_result', {
    p_match_id: m.match.id,
    p_score_a:  Number(m.scoreA),
    p_score_b:  Number(m.scoreB),
  })
  scoreBusy.value = false
  if (error) { scoreErr.value = error.message; return }
  scoreModal.value = null
  await load()
}

async function saveSettings() {
  settingsBusy.value = true; settingsOk.value = false; err.value = ''
  const { error } = await supabase.rpc('update_tournament_details', {
    p_tournament_id:   tour.value.id,
    p_name:            settings.value.name || null,
    p_description:     settings.value.description || null,
    p_entry_fee:       settings.value.entry_fee ? Number(settings.value.entry_fee) : null,
    p_prize_info:      settings.value.prize_info || null,
    p_venue:           settings.value.venue || null,
    p_venue_address:   settings.value.venue_address || null,
    p_emirate:         settings.value.emirate || null,
    p_registration_end: settings.value.registration_end || null,
    p_start_date:      settings.value.start_date || null,
    p_end_date:        settings.value.end_date || null,
    p_max_teams:       Number(settings.value.max_teams) || null,
  })
  settingsBusy.value = false
  if (error) { err.value = error.message; return }
  settingsOk.value = true
  await load()
}

const statusFlow = computed(() => {
  const s = tour.value?.status
  const options = []
  if (s === 'draft')                 options.push({ v: 'registration_open', l: '📬 Open Registration' })
  if (s === 'registration_open')     options.push({ v: 'registration_closed', l: '🔒 Close Registration' })
  if (s === 'registration_closed')   options.push({ v: 'registration_open', l: '📬 Re-open Registration' })
  if (!['live','completed','cancelled'].includes(s))
    options.push({ v: 'cancelled', l: '🚫 Cancel' })
  return options
})

const matchStatusClass = s => ({
  completed: 'border-emerald-200 bg-emerald-50',
  bye: 'border-slate-100 bg-slate-50 opacity-60',
  scheduled: 'border-cyan-200/50 bg-white',
}[s] ?? 'border-slate-200 bg-white')
</script>

<template>
  <div>
    <!-- Back -->
    <button class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4"
      @click="router.push('/tournament/' + route.params.id)">
      ← Back to Tournament
    </button>

    <div v-if="loading" class="space-y-3">
      <div class="h-24 shimmer rounded-2xl" />
      <div class="h-48 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!data" class="card p-8 text-center text-slate-500">
      Tournament not found or access denied.
    </div>

    <template v-else>
      <!-- Header -->
      <div class="mb-4">
        <h1 class="font-display text-xl font-bold gradient-text">{{ tour.name }}</h1>
        <p class="text-xs text-slate-400 mt-0.5">Tournament Director Panel</p>
      </div>

      <!-- Alerts -->
      <div v-if="err" class="rounded-xl px-4 py-3 mb-3 text-sm text-rose-600 bg-rose-50 border border-rose-200">
        ⚠️ {{ err }}
      </div>
      <div v-if="ok" class="rounded-xl px-4 py-3 mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200">
        ✅ {{ ok }}
      </div>

      <!-- Status card -->
      <div class="card p-4 mb-4">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <div>
            <p class="text-xs text-slate-400">Status</p>
            <p class="font-bold text-slate-800 capitalize mt-0.5">{{ tour.status.replace(/_/g,' ') }}</p>
          </div>
          <div class="flex gap-2 flex-wrap">
            <button v-for="opt in statusFlow" :key="opt.v"
              class="btn-ghost text-xs px-3 py-1.5"
              :disabled="busy === 'status'"
              @click="setStatus(opt.v)">
              {{ busy === 'status' ? '…' : opt.l }}
            </button>
          </div>
        </div>

        <!-- Generate bracket button (shown when closed or draft and has teams) -->
        <div v-if="['draft','registration_open','registration_closed'].includes(tour.status) && confirmed.length >= 2"
          class="mt-3 pt-3 border-t border-slate-100">
          <p class="text-xs text-slate-500 mb-2">
            {{ confirmed.length }} confirmed team{{ confirmed.length > 1 ? 's' : '' }}.
            Ready to generate bracket.
          </p>
          <button class="btn-primary w-full py-2.5 text-sm"
            :disabled="busy === 'bracket'"
            @click="generateBracket">
            {{ busy === 'bracket' ? '⏳ Generating…' : '🎯 Generate Bracket & Go Live' }}
          </button>
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 mb-4 border border-slate-200 rounded-2xl p-1 bg-white">
        <button v-for="t in [{v:'registrations',l:'Teams'},{v:'bracket',l:'Bracket'},{v:'settings',l:'Settings'}]"
          :key="t.v"
          class="flex-1 py-2 text-xs font-semibold rounded-xl transition-all relative"
          :class="tab === t.v ? 'bg-cyan-600 text-white shadow-sm' : 'text-slate-500 hover:text-slate-700'"
          @click="tab = t.v">
          {{ t.l }}
          <span v-if="t.v === 'registrations' && pending.length"
            class="absolute -top-1 -right-1 badge-dot text-[8px]">
            {{ pending.length }}
          </span>
        </button>
      </div>

      <!-- ── REGISTRATIONS TAB ── -->
      <div v-if="tab === 'registrations'" class="space-y-4 fade-up">

        <!-- Pending -->
        <div v-if="pending.length">
          <h3 class="label mb-2">Pending Approval ({{ pending.length }})</h3>
          <div class="space-y-2">
            <div v-for="r in pending" :key="r.id" class="card p-4">
              <div class="flex items-start justify-between gap-2">
                <div class="flex-1 min-w-0">
                  <p class="font-semibold text-slate-800">{{ r.team_name }}</p>
                  <p class="text-xs text-slate-500 mt-0.5">
                    {{ r.player_a_name }}<span v-if="r.player_b_name"> · {{ r.player_b_name }}</span>
                  </p>
                  <p v-if="r.notes" class="text-xs text-slate-400 mt-1 italic">{{ r.notes }}</p>
                </div>
                <div class="flex gap-2 shrink-0">
                  <button class="btn-success text-xs px-3 py-1.5"
                    :disabled="busy === 'reg-' + r.id"
                    @click="approve(r.id)">✓ Approve</button>
                  <button class="btn-danger text-xs px-3 py-1.5"
                    :disabled="busy === 'reg-' + r.id"
                    @click="reject(r.id)">✗</button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Confirmed -->
        <div v-if="confirmed.length">
          <h3 class="label mb-2">Confirmed Teams ({{ confirmed.length }})</h3>
          <div class="card overflow-hidden">
            <div v-for="(r, i) in confirmed" :key="r.id"
              class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
              <!-- Seed input -->
              <input type="number" min="1" :max="confirmed.length"
                :value="r.seed ?? (i+1)"
                class="w-10 text-center rounded-lg border border-slate-200 py-1 text-xs font-bold"
                @change="setSeed(r.id, $event.target.value)" />
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-slate-800 text-sm truncate">{{ r.team_name }}</p>
                <p class="text-xs text-slate-400">
                  {{ r.player_a_name }}<span v-if="r.player_b_name"> · {{ r.player_b_name }}</span>
                </p>
              </div>
              <span class="badge-approved">confirmed</span>
            </div>
          </div>
          <p class="text-xs text-slate-400 mt-2 text-center">
            Seed numbers are used for bracket seeding. Edit inline.
          </p>
        </div>

        <div v-if="!registrations.length" class="card p-8 text-center text-slate-400 text-sm">
          No registrations yet. Share the tournament link to get sign-ups.
        </div>
      </div>

      <!-- ── BRACKET TAB ── -->
      <div v-if="tab === 'bracket'" class="fade-up">
        <div v-if="!matches.length" class="card p-8 text-center text-sm text-slate-500">
          <p class="mb-4">Bracket not generated yet.</p>
          <p v-if="confirmed.length < 2" class="text-amber-600">
            Need at least 2 confirmed teams to generate.
          </p>
          <button v-else-if="['draft','registration_open','registration_closed'].includes(tour.status)"
            class="btn-primary px-6" :disabled="busy === 'bracket'"
            @click="generateBracket">
            {{ busy === 'bracket' ? '⏳ Generating…' : '🎯 Generate Bracket' }}
          </button>
        </div>

        <!-- Round-robin list with score entry -->
        <div v-else-if="tour.format === 'round_robin'" class="space-y-2">
          <div v-for="m in matches" :key="m.id"
            class="card p-3 border transition"
            :class="m.status === 'completed' ? 'border-emerald-200 bg-emerald-50' : 'border-cyan-200/40'">
            <div class="flex items-center gap-3">
              <div class="flex-1 min-w-0 text-xs font-semibold text-slate-700 truncate">
                {{ m.team_a_name ?? 'TBD' }}
              </div>
              <div class="shrink-0 flex items-center gap-2 font-extrabold text-sm">
                <span :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-400'">
                  {{ m.score_a ?? '—' }}
                </span>
                <span class="text-slate-300 font-normal text-xs">vs</span>
                <span :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-400'">
                  {{ m.score_b ?? '—' }}
                </span>
              </div>
              <div class="flex-1 min-w-0 text-right text-xs font-semibold text-slate-700 truncate">
                {{ m.team_b_name ?? 'TBD' }}
              </div>
              <button v-if="m.status !== 'completed' && m.status !== 'bye'"
                class="shrink-0 btn-ghost text-xs px-2 py-1"
                @click="openScoreModal(m)">
                Score
              </button>
              <span v-else-if="m.status === 'completed'"
                class="shrink-0 text-[10px] text-emerald-600 font-bold">Done</span>
            </div>
          </div>
        </div>

        <!-- Single elimination bracket with score entry -->
        <div v-else>
          <div v-for="rd in rounds" :key="rd.round" class="mb-6">
            <h3 class="label mb-2">{{ roundLabel(rd.round, totalRounds) }}</h3>
            <div class="space-y-2">
              <div v-for="m in rd.matches" :key="m.id"
                class="card border p-3 transition"
                :class="matchStatusClass(m.status)">

                <div v-if="m.status === 'bye'" class="text-xs text-slate-400 italic text-center py-1">
                  BYE — auto advance
                </div>
                <template v-else>
                  <div class="flex items-center gap-3">
                    <!-- Team A -->
                    <div class="flex-1 min-w-0">
                      <p class="text-xs font-semibold truncate"
                        :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-700'">
                        {{ m.team_a_name ?? 'TBD' }}
                        <span v-if="m.winner_id === m.team_a_id" class="ml-1">🏆</span>
                      </p>
                    </div>
                    <!-- Scores -->
                    <div class="shrink-0 flex items-center gap-2 font-bold text-sm">
                      <span :class="m.winner_id === m.team_a_id ? 'text-emerald-700' : 'text-slate-400'">
                        {{ m.score_a ?? '—' }}
                      </span>
                      <span class="text-slate-300 text-xs font-normal">vs</span>
                      <span :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-400'">
                        {{ m.score_b ?? '—' }}
                      </span>
                    </div>
                    <!-- Team B -->
                    <div class="flex-1 min-w-0 text-right">
                      <p class="text-xs font-semibold truncate"
                        :class="m.winner_id === m.team_b_id ? 'text-emerald-700' : 'text-slate-700'">
                        <span v-if="m.winner_id === m.team_b_id" class="mr-1">🏆</span>
                        {{ m.team_b_name ?? 'TBD' }}
                      </p>
                    </div>
                    <!-- Score button -->
                    <button v-if="m.status === 'scheduled' && m.team_a_id && m.team_b_id"
                      class="shrink-0 btn-ghost text-xs px-2 py-1"
                      @click="openScoreModal(m)">
                      Score
                    </button>
                  </div>
                </template>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── SETTINGS TAB ── -->
      <div v-if="tab === 'settings'" class="fade-up space-y-4">
        <div class="card p-4 space-y-4">
          <div>
            <label class="label">Name</label>
            <input v-model="settings.name" class="input" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Max Teams</label>
              <select v-model="settings.max_teams" class="input">
                <option v-for="n in [4,8,12,16,24,32]" :key="n" :value="n">{{ n }}</option>
              </select>
            </div>
            <div>
              <label class="label">Emirate</label>
              <select v-model="settings.emirate" class="input">
                <option value="">— Any —</option>
                <option v-for="e in emirates" :key="e" :value="e">{{ e }}</option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Entry Fee (AED)</label>
              <input v-model="settings.entry_fee" type="number" min="0" class="input" />
            </div>
            <div>
              <label class="label">Reg. Closes</label>
              <input v-model="settings.registration_end" type="date" class="input" />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Start Date</label>
              <input v-model="settings.start_date" type="date" class="input" />
            </div>
            <div>
              <label class="label">End Date</label>
              <input v-model="settings.end_date" type="date" class="input" />
            </div>
          </div>
          <div>
            <label class="label">Venue</label>
            <input v-model="settings.venue" class="input" placeholder="Venue name" />
          </div>
          <div>
            <label class="label">Venue Address</label>
            <input v-model="settings.venue_address" class="input" placeholder="Full address" />
          </div>
          <div>
            <label class="label">Prize Info</label>
            <input v-model="settings.prize_info" class="input" placeholder="1st: AED 500…" />
          </div>
          <div>
            <label class="label">Description</label>
            <textarea v-model="settings.description" class="input resize-none" rows="3" />
          </div>
        </div>

        <p v-if="err" class="text-rose-500 text-sm">{{ err }}</p>
        <p v-if="settingsOk" class="text-emerald-600 text-sm">✅ Saved</p>
        <button class="btn-primary w-full" :disabled="settingsBusy" @click="saveSettings">
          {{ settingsBusy ? 'Saving…' : 'Save Changes' }}
        </button>
      </div>
    </template>
  </div>

  <!-- ── Score Modal ── -->
  <Teleport to="body">
    <div v-if="scoreModal"
      class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.6); backdrop-filter:blur(4px)"
      @click.self="scoreModal = null">
      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#f8fafc; border:1px solid rgba(0,168,204,.25)">

        <h3 class="font-display font-bold text-slate-800 text-lg mb-1">Record Result</h3>
        <p class="text-xs text-slate-500 mb-5">
          {{ scoreModal.match.team_a_name ?? 'Team A' }} vs {{ scoreModal.match.team_b_name ?? 'Team B' }}
        </p>

        <div class="grid grid-cols-2 gap-4 mb-4">
          <div>
            <label class="label">{{ scoreModal.match.team_a_name ?? 'Team A' }}</label>
            <input v-model="scoreModal.scoreA" type="number" min="0" class="input text-center text-xl font-bold"
              placeholder="0" />
          </div>
          <div>
            <label class="label">{{ scoreModal.match.team_b_name ?? 'Team B' }}</label>
            <input v-model="scoreModal.scoreB" type="number" min="0" class="input text-center text-xl font-bold"
              placeholder="0" />
          </div>
        </div>

        <p v-if="scoreErr" class="text-rose-500 text-sm mb-3">{{ scoreErr }}</p>

        <div class="flex gap-3">
          <button class="btn-ghost flex-1" @click="scoreModal = null">Cancel</button>
          <button class="btn-primary flex-1" :disabled="scoreBusy" @click="submitScore">
            {{ scoreBusy ? 'Saving…' : 'Save Result' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
