<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { currentClub, isManager } = useClub()

const data     = ref(null)
const loading  = ref(true)
const tab      = ref('bracket') // bracket | teams | info
const regForm  = ref({ team_name: '', player_a: '', player_b: '' })
const regBusy  = ref(false)
const regErr   = ref('')
const regOk    = ref(false)
const wdBusy   = ref(null) // reg id being withdrawn

async function load() {
  loading.value = true
  const { data: d, error } = await supabase.rpc('get_tournament_detail', {
    p_tournament_id: route.params.id
  })
  if (error) { loading.value = false; return }
  data.value = d
  loading.value = false
}

onMounted(load)

const tour          = computed(() => data.value?.tournament)
const registrations = computed(() => data.value?.registrations ?? [])
const matches       = computed(() => data.value?.matches ?? [])
const standings     = computed(() => data.value?.standings ?? [])

const isDirector = computed(() => {
  if (!user.value || !tour.value) return false
  return tour.value.created_by === user.value.id || isManager()
})

const canRegister = computed(() => tour.value?.status === 'registration_open' && !!user.value)

const myReg = computed(() => {
  if (!user.value) return null
  return registrations.value.find(r => r.registered_by === user.value.id && r.status !== 'withdrawn')
})

// Bracket: group matches by round
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
  if (tour.value?.format === 'round_robin') return 'Matches'
  const fromEnd = total - r
  if (fromEnd === 0) return 'Final'
  if (fromEnd === 1) return 'Semi-final'
  if (fromEnd === 2) return 'Quarter-final'
  return `Round ${r}`
}

// Slot height doubles each round for bracket alignment
const slotHeight = r => 72 * Math.pow(2, r - 1)

async function register() {
  regErr.value = ''; regOk.value = false
  if (!regForm.value.team_name.trim()) { regErr.value = 'Team name is required'; return }
  if (!regForm.value.player_a.trim())  { regErr.value = 'Player A name is required'; return }
  regBusy.value = true
  const { error } = await supabase.rpc('register_for_tournament', {
    p_tournament_id: tour.value.id,
    p_team_name:     regForm.value.team_name.trim(),
    p_player_a_name: regForm.value.player_a.trim(),
    p_player_b_name: regForm.value.player_b.trim() || null,
  })
  regBusy.value = false
  if (error) { regErr.value = error.message; return }
  regOk.value = true
  regForm.value = { team_name: '', player_a: '', player_b: '' }
  await load()
}

async function withdraw(regId) {
  wdBusy.value = regId
  await supabase.rpc('withdraw_registration', { p_reg_id: regId })
  wdBusy.value = null
  await load()
}

const statusLabel = s => ({
  draft: 'Draft', registration_open: 'Registration Open',
  registration_closed: 'Closed', live: '🔴 Live',
  completed: 'Completed', cancelled: 'Cancelled'
}[s] ?? s)

const statusClass = s => ({
  draft: 'badge-pending',
  registration_open: 'badge-approved',
  live: 'badge bg-rose-50 text-rose-600 border border-rose-200',
  completed: 'badge bg-slate-100 text-slate-500 border border-slate-200',
}[s] ?? 'badge-pending')

const matchStatusClass = s => ({
  completed: 'border-slate-200 bg-white',
  bye: 'border-slate-100 bg-slate-50 opacity-60',
  scheduled: 'border-cyan-200/50 bg-white',
}[s] ?? 'border-slate-200 bg-white')

const fmtDate = d => d ? new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short', year:'numeric' }) : ''
</script>

<template>
  <div>
    <!-- Loading -->
    <div v-if="loading" class="space-y-3">
      <div class="h-32 shimmer rounded-2xl" />
      <div class="h-10 shimmer rounded-xl" />
      <div class="h-48 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!data" class="card p-10 text-center">
      <p class="text-slate-500">Tournament not found.</p>
      <button class="btn-ghost mt-4" @click="router.push('/tournaments')">← Back</button>
    </div>

    <template v-else>
      <!-- Header card -->
      <div class="card-neon p-5 mb-4 fade-up">
        <div class="flex items-start justify-between gap-2 mb-3">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap mb-2">
              <span :class="statusClass(tour.status)">{{ statusLabel(tour.status) }}</span>
              <span class="badge bg-violet-50 text-violet-700 border border-violet-200">
                {{ tour.format === 'single_elimination' ? 'Knock-out' : 'Round Robin' }}
              </span>
            </div>
            <h1 class="font-display text-2xl font-bold gradient-text">{{ tour.name }}</h1>
            <p class="text-sm text-slate-500 mt-1">{{ tour.club_name }}</p>
          </div>
          <button v-if="isDirector" class="btn-ghost text-xs shrink-0"
            @click="router.push('/tournament/' + tour.id + '/manage')">
            ⚙️ Manage
          </button>
        </div>

        <!-- Key info grid -->
        <div class="grid grid-cols-2 gap-2 text-xs text-slate-600">
          <div v-if="tour.venue" class="flex items-center gap-1.5">
            <span>📍</span><span class="truncate">{{ tour.venue }}</span>
          </div>
          <div v-if="tour.emirate" class="flex items-center gap-1.5">
            <span>🇦🇪</span><span>{{ tour.emirate }}</span>
          </div>
          <div v-if="tour.start_date" class="flex items-center gap-1.5">
            <span>📅</span><span>{{ fmtDate(tour.start_date) }}</span>
          </div>
          <div v-if="tour.entry_fee" class="flex items-center gap-1.5">
            <span>💰</span><span>AED {{ tour.entry_fee }} per team</span>
          </div>
          <div v-if="tour.registration_end && tour.status === 'registration_open'" class="flex items-center gap-1.5 text-amber-600">
            <span>⏰</span><span>Reg. closes {{ fmtDate(tour.registration_end) }}</span>
          </div>
          <div class="flex items-center gap-1.5 text-neon font-semibold">
            <span>👥</span>
            <span>{{ registrations.filter(r=>r.status==='confirmed').length }} / {{ tour.max_teams }} teams</span>
          </div>
        </div>

        <div v-if="tour.prize_info" class="mt-3 text-xs text-amber-700 font-semibold">
          🏆 {{ tour.prize_info }}
        </div>
        <div v-if="tour.winner_team_name" class="mt-3 px-3 py-2 rounded-xl text-sm font-bold text-amber-700"
          style="background:rgba(217,119,6,.08); border:1px solid rgba(217,119,6,.25)">
          🥇 Winner: {{ tour.winner_team_name }}
        </div>
      </div>

      <!-- Tabs -->
      <div class="flex gap-1 mb-4 border border-slate-200 rounded-2xl p-1 bg-white">
        <button v-for="t in (tour.status === 'registration_open' || tour.status === 'draft'
            ? [{v:'teams',l:'Teams'},{v:'info',l:'Info'}]
            : tour.format === 'round_robin'
              ? [{v:'standings',l:'Standings'},{v:'bracket',l:'Matches'},{v:'teams',l:'Teams'},{v:'info',l:'Info'}]
              : [{v:'bracket',l:'Bracket'},{v:'teams',l:'Teams'},{v:'info',l:'Info'}])"
          :key="t.v"
          class="flex-1 py-2 text-xs font-semibold rounded-xl transition-all"
          :class="tab === t.v
            ? 'bg-cyan-600 text-white shadow-sm'
            : 'text-slate-500 hover:text-slate-700'"
          @click="tab = t.v">
          {{ t.l }}
        </button>
      </div>

      <!-- ── BRACKET TAB ── -->
      <div v-if="tab === 'bracket'" class="fade-up">
        <div v-if="!matches.length" class="card p-8 text-center text-slate-500 text-sm">
          <div class="text-3xl mb-3">🔖</div>
          Bracket not yet generated. Check back once registration closes.
        </div>

        <!-- Round-Robin match list -->
        <div v-else-if="tour.format === 'round_robin'" class="space-y-2">
          <div v-for="m in matches" :key="m.id"
            class="card p-3 border transition"
            :class="m.status === 'completed' ? 'border-slate-200' : 'border-cyan-200/40'">
            <div class="flex items-center gap-3">
              <div class="flex-1 min-w-0">
                <div class="text-xs font-semibold text-slate-700 truncate">{{ m.team_a_name ?? 'TBD' }}</div>
              </div>
              <div class="shrink-0 flex items-center gap-2 font-extrabold text-sm">
                <span :class="m.winner_id === m.team_a_id ? 'text-neon' : 'text-slate-400'">
                  {{ m.score_a ?? '—' }}
                </span>
                <span class="text-slate-300 font-normal text-xs">vs</span>
                <span :class="m.winner_id === m.team_b_id ? 'text-neon' : 'text-slate-400'">
                  {{ m.score_b ?? '—' }}
                </span>
              </div>
              <div class="flex-1 min-w-0 text-right">
                <div class="text-xs font-semibold text-slate-700 truncate">{{ m.team_b_name ?? 'TBD' }}</div>
              </div>
            </div>
          </div>
        </div>

        <!-- Single Elimination bracket — horizontal scroll -->
        <div v-else class="overflow-x-auto pb-4 -mx-4 px-4">
          <div class="flex gap-0" :style="{ minWidth: (totalRounds * 176) + 'px' }">
            <div v-for="(rd, ri) in rounds" :key="rd.round"
              class="flex flex-col"
              :style="{ width: '168px', marginRight: ri < rounds.length - 1 ? '8px' : '0' }">

              <!-- Round label -->
              <div class="text-[10px] uppercase tracking-widest font-bold text-slate-400 mb-2 px-1 text-center">
                {{ roundLabel(rd.round, totalRounds) }}
              </div>

              <!-- Match slots -->
              <div class="flex flex-col flex-1">
                <div v-for="m in rd.matches" :key="m.id"
                  class="flex items-center"
                  :style="{ height: slotHeight(rd.round) + 'px' }">

                  <div class="w-full rounded-xl border p-2 text-xs transition"
                    :class="matchStatusClass(m.status)">

                    <!-- BYE -->
                    <div v-if="m.status === 'bye'" class="text-center text-slate-400 py-1 italic text-[10px]">
                      BYE — auto advance
                    </div>

                    <!-- Real match -->
                    <template v-else>
                      <!-- Team A -->
                      <div class="flex items-center justify-between gap-1 py-1 border-b border-slate-100">
                        <span class="font-medium truncate"
                          :class="m.winner_id === m.team_a_id ? 'text-cyan-700 font-bold' : 'text-slate-600'">
                          {{ m.team_a_name ?? (m.team_a_id ? '…' : 'TBD') }}
                        </span>
                        <span class="shrink-0 font-bold"
                          :class="m.winner_id === m.team_a_id ? 'text-cyan-700' : 'text-slate-400'">
                          {{ m.score_a ?? '' }}
                        </span>
                      </div>
                      <!-- Team B -->
                      <div class="flex items-center justify-between gap-1 py-1">
                        <span class="font-medium truncate"
                          :class="m.winner_id === m.team_b_id ? 'text-cyan-700 font-bold' : 'text-slate-600'">
                          {{ m.team_b_name ?? (m.team_b_id ? '…' : 'TBD') }}
                        </span>
                        <span class="shrink-0 font-bold"
                          :class="m.winner_id === m.team_b_id ? 'text-cyan-700' : 'text-slate-400'">
                          {{ m.score_b ?? '' }}
                        </span>
                      </div>
                      <!-- Winner indicator -->
                      <div v-if="m.winner_name" class="mt-1 text-[9px] text-cyan-600 font-bold truncate">
                        🏆 {{ m.winner_name }}
                      </div>
                    </template>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── STANDINGS TAB (round robin) ── -->
      <div v-if="tab === 'standings'" class="fade-up">
        <div v-if="!standings.length" class="card p-8 text-center text-slate-500 text-sm">
          No matches played yet.
        </div>
        <div v-else class="card overflow-hidden">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-slate-100">
                <th class="px-4 py-2.5 text-left text-xs text-slate-400 font-semibold">Team</th>
                <th class="px-2 py-2.5 text-center text-xs text-slate-400 font-semibold">P</th>
                <th class="px-2 py-2.5 text-center text-xs text-slate-400 font-semibold">W</th>
                <th class="px-2 py-2.5 text-center text-xs text-slate-400 font-semibold">L</th>
                <th class="px-3 py-2.5 text-center text-xs text-slate-400 font-semibold">+/−</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(s, i) in standings" :key="s.registration_id"
                class="border-b border-slate-50 last:border-0"
                :class="i === 0 ? 'bg-amber-50' : ''">
                <td class="px-4 py-2.5">
                  <div class="flex items-center gap-2">
                    <span v-if="i === 0" class="text-base">🥇</span>
                    <span v-else-if="i === 1" class="text-base">🥈</span>
                    <span v-else-if="i === 2" class="text-base">🥉</span>
                    <span v-else class="text-slate-400 text-xs w-4 text-center">{{ i+1 }}</span>
                    <span class="font-semibold text-slate-800 text-sm">{{ s.team_name }}</span>
                    <span v-if="s.seed" class="text-[10px] text-slate-400">#{{ s.seed }}</span>
                  </div>
                </td>
                <td class="px-2 py-2.5 text-center text-slate-500">{{ s.played }}</td>
                <td class="px-2 py-2.5 text-center font-bold text-emerald-600">{{ s.wins }}</td>
                <td class="px-2 py-2.5 text-center text-rose-500">{{ s.losses }}</td>
                <td class="px-3 py-2.5 text-center text-xs"
                  :class="s.sets_for >= s.sets_against ? 'text-emerald-600' : 'text-rose-500'">
                  {{ s.sets_for - s.sets_against >= 0 ? '+' : '' }}{{ s.sets_for - s.sets_against }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- ── TEAMS TAB ── -->
      <div v-if="tab === 'teams'" class="fade-up space-y-3">

        <!-- Registration form -->
        <div v-if="canRegister && !myReg" class="card-neon p-4">
          <h3 class="font-bold text-slate-800 mb-3">Register Your Team</h3>
          <div class="space-y-3">
            <div>
              <label class="label">Team Name</label>
              <input v-model="regForm.team_name" class="input" placeholder="e.g. Smash Brothers" />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="label">Player A</label>
                <input v-model="regForm.player_a" class="input" placeholder="Name" />
              </div>
              <div>
                <label class="label">Player B</label>
                <input v-model="regForm.player_b" class="input" placeholder="Name (optional)" />
              </div>
            </div>
          </div>
          <p v-if="regErr" class="text-rose-500 text-xs mt-2">{{ regErr }}</p>
          <p v-if="regOk" class="text-emerald-600 text-xs mt-2">✅ Registration submitted! Waiting for director approval.</p>
          <button class="btn-primary w-full mt-4" :disabled="regBusy" @click="register">
            {{ regBusy ? 'Registering…' : 'Register' }}
          </button>
        </div>

        <!-- My pending reg -->
        <div v-if="myReg" class="card p-4 border-amber-200 border">
          <div class="flex items-center justify-between">
            <div>
              <p class="font-bold text-slate-800">{{ myReg.team_name }}</p>
              <p class="text-xs text-slate-500 mt-0.5">{{ myReg.player_a_name }}
                <span v-if="myReg.player_b_name"> · {{ myReg.player_b_name }}</span>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <span :class="myReg.status === 'confirmed' ? 'badge-approved' : 'badge-pending'">
                {{ myReg.status }}
              </span>
              <button v-if="myReg.status === 'pending'" class="text-xs text-rose-400 hover:text-rose-600"
                :disabled="wdBusy === myReg.id"
                @click="withdraw(myReg.id)">
                {{ wdBusy === myReg.id ? '…' : 'Withdraw' }}
              </button>
            </div>
          </div>
        </div>

        <!-- Not logged in prompt -->
        <div v-if="canRegister && !user" class="card p-4 text-center text-sm text-slate-500">
          <RouterLink to="/login" class="text-neon underline">Sign in</RouterLink> to register your team.
        </div>

        <!-- All teams list -->
        <div class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100">
            <h3 class="font-semibold text-slate-700 text-sm">
              Teams ({{ registrations.filter(r => r.status === 'confirmed').length }} confirmed)
            </h3>
          </div>
          <div v-if="!registrations.filter(r => r.status !== 'withdrawn').length"
            class="p-6 text-center text-sm text-slate-400">
            No registrations yet.
          </div>
          <div v-for="(r, i) in registrations.filter(r => r.status !== 'withdrawn')" :key="r.id"
            class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
            <div class="w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold"
              :class="r.status === 'confirmed' ? 'bg-cyan-50 text-cyan-700' : 'bg-slate-100 text-slate-400'">
              {{ r.seed ?? (i + 1) }}
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-slate-800 text-sm truncate">{{ r.team_name }}</p>
              <p class="text-xs text-slate-400 truncate">
                {{ r.player_a_name }}<span v-if="r.player_b_name"> · {{ r.player_b_name }}</span>
              </p>
            </div>
            <span :class="r.status === 'confirmed' ? 'badge-approved' : 'badge-pending'">
              {{ r.status }}
            </span>
          </div>
        </div>
      </div>

      <!-- ── INFO TAB ── -->
      <div v-if="tab === 'info'" class="fade-up space-y-4">
        <div class="card p-4 space-y-3">
          <div v-if="tour.description">
            <p class="label">Description</p>
            <p class="text-sm text-slate-700 whitespace-pre-line">{{ tour.description }}</p>
          </div>
          <div class="grid grid-cols-2 gap-3 text-sm">
            <div v-if="tour.venue_address">
              <p class="label">Venue</p>
              <p class="text-slate-700">{{ tour.venue_address }}</p>
              <a v-if="tour.maps_url" :href="tour.maps_url" target="_blank"
                class="text-neon text-xs underline">Open maps →</a>
            </div>
            <div>
              <p class="label">Format</p>
              <p class="text-slate-700">{{ tour.format === 'single_elimination' ? 'Single Elimination' : 'Round Robin' }}</p>
            </div>
            <div>
              <p class="label">Max Teams</p>
              <p class="text-slate-700">{{ tour.max_teams }}</p>
            </div>
            <div v-if="tour.entry_fee">
              <p class="label">Entry Fee</p>
              <p class="text-slate-700">AED {{ tour.entry_fee }}</p>
            </div>
          </div>
          <div v-if="!tour.description && !tour.venue_address" class="text-sm text-slate-400 text-center py-4">
            No additional info provided.
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
