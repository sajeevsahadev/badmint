<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()

const schedule = ref(null)
const loading  = ref(true)
const voting   = ref(null)
const votes    = ref([])
const showVotes    = ref(false)
const votesLoading = ref(false)
const copied   = ref(false)
const error    = ref(null)

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
const DAYS   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']

const dateLabel = computed(() => {
  if (!schedule.value) return ''
  const [y, m, d] = schedule.value.scheduled_date.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  return `${MONTHS[m-1]} ${d} ${DAYS[dt.getDay()]}`
})

const venueName = computed(() =>
  schedule.value?.fac_name || schedule.value?.facility_name || null
)

const totalVotes = computed(() =>
  (schedule.value?.attending_count ?? 0) + (schedule.value?.not_attending_count ?? 0)
)

async function loadSchedule() {
  loading.value = true
  const { data, error: err } = await supabase.rpc('get_schedule_detail', {
    p_schedule_id: route.params.id
  })
  if (err || !data?.length) {
    error.value = 'Match day not found or the link has expired.'
  } else {
    schedule.value = data[0]
  }
  loading.value = false
}

async function castVote(option) {
  if (!user.value) {
    sessionStorage.setItem('bm_after_login', route.fullPath)
    router.push('/login')
    return
  }
  voting.value = option
  const { error: err } = await supabase.rpc('vote_schedule', {
    p_schedule_id: schedule.value.id,
    p_vote:        option
  })
  if (err) {
    alert(err.message)
  } else {
    await loadSchedule()
  }
  voting.value = null
}

async function loadVotes() {
  votesLoading.value = true
  const { data } = await supabase.rpc('get_schedule_votes', {
    p_schedule_id: schedule.value.id
  })
  votes.value = data ?? []
  votesLoading.value = false
  showVotes.value = true
}

async function copyLink() {
  await navigator.clipboard.writeText(window.location.href)
  copied.value = true
  setTimeout(() => { copied.value = false }, 2000)
}

function timeAgo(ts) {
  const d    = new Date(ts)
  const diff = Date.now() - d.getTime()
  const mins = Math.floor(diff / 60000)
  const hrs  = Math.floor(diff / 3600000)
  const days = Math.floor(diff / 86400000)
  if (mins < 1)  return 'just now'
  if (mins < 60) return `${mins}m ago`
  if (hrs  < 24) return `${hrs}h ago`
  if (days === 1) return 'yesterday'
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

onMounted(loadSchedule)
</script>

<template>
  <div class="min-h-screen px-4 py-8 max-w-sm mx-auto">

    <!-- Loading -->
    <div v-if="loading" class="text-center py-16 text-slate-500 animate-pulse">
      <div class="text-4xl mb-3">🏸</div>
      Loading match poll…
    </div>

    <!-- Error -->
    <div v-else-if="error" class="card p-8 text-center">
      <div class="text-3xl mb-3">😕</div>
      <p class="text-sm text-slate-400">{{ error }}</p>
    </div>

    <template v-else-if="schedule">

      <!-- App brand -->
      <div class="text-center mb-6">
        <div class="text-3xl mb-1" style="filter:drop-shadow(0 0 16px rgba(0,229,255,.5))">🏸</div>
        <div class="font-display font-extrabold text-lg gradient-text">Badminton 360</div>
        <div class="text-[10px] text-slate-600 tracking-widest uppercase">Your Club · Your Game · One App</div>
      </div>

      <!-- Schedule card -->
      <div class="card-neon p-5 mb-5">
        <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-1">Match Day Poll</div>
        <h1 class="font-display text-xl font-bold gradient-text leading-snug">
          {{ dateLabel }}
        </h1>
        <div v-if="venueName" class="text-sm text-slate-400 mt-1">📍 {{ venueName }}</div>
        <div class="text-xs text-slate-600 mt-0.5">{{ schedule.club_name }}</div>

        <div v-if="schedule.status === 'cancelled'"
          class="mt-2 inline-block text-xs bg-rose-500/20 text-rose-400 rounded px-2 py-0.5">
          Cancelled
        </div>
      </div>

      <!-- Poll -->
      <div class="card p-4 mb-4">
        <div class="grid grid-cols-2 gap-3 mb-4">
          <button
            @click="castVote('attending')"
            :disabled="voting !== null || schedule.status === 'cancelled'"
            class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
            :class="schedule.my_vote === 'attending'
              ? 'bg-emerald-500/15 border-emerald-500/60'
              : 'border-white/10 hover:border-emerald-500/30 active:opacity-70'">
            <span class="text-3xl">✅</span>
            <span class="text-sm font-semibold text-slate-200">Attending</span>
            <span class="text-3xl font-bold text-emerald-400">{{ schedule.attending_count }}</span>
          </button>
          <button
            @click="castVote('not_attending')"
            :disabled="voting !== null || schedule.status === 'cancelled'"
            class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
            :class="schedule.my_vote === 'not_attending'
              ? 'bg-rose-500/15 border-rose-500/60'
              : 'border-white/10 hover:border-rose-500/30 active:opacity-70'">
            <span class="text-3xl">❌</span>
            <span class="text-sm font-semibold text-slate-200">Not Attending</span>
            <span class="text-3xl font-bold text-rose-400">{{ schedule.not_attending_count }}</span>
          </button>
        </div>

        <!-- My vote status -->
        <div class="text-center text-xs mb-3">
          <span v-if="!user" class="text-slate-500">
            <button class="text-neon underline" @click="$router.push('/login')">Sign in</button> to cast your vote
          </span>
          <span v-else-if="schedule.my_vote" :class="schedule.my_vote === 'attending' ? 'text-emerald-400' : 'text-rose-400'">
            Your vote: {{ schedule.my_vote === 'attending' ? 'Attending ✓' : 'Not Attending ✓' }}
            <button class="ml-2 text-slate-500 underline"
              @click="castVote(schedule.my_vote === 'attending' ? 'not_attending' : 'attending')">
              change
            </button>
          </span>
          <span v-else class="text-slate-600">Tap a button to vote</span>
        </div>

        <!-- Total + view votes -->
        <div class="flex items-center justify-between text-xs text-slate-600">
          <span>{{ totalVotes }} {{ totalVotes === 1 ? 'vote' : 'votes' }} total</span>
          <button class="underline text-slate-500 hover:text-slate-300 transition"
            @click="loadVotes">View Votes</button>
        </div>
      </div>

      <!-- Votes list (inline, loads on demand) -->
      <div v-if="showVotes" class="card p-4 mb-4">
        <div class="flex items-center justify-between mb-3">
          <span class="text-xs font-semibold uppercase tracking-widest text-slate-500">Who Voted</span>
          <button @click="showVotes = false" class="text-xs text-slate-600">hide</button>
        </div>
        <div v-if="votesLoading" class="text-center text-sm text-slate-500 animate-pulse py-3">Loading…</div>
        <div v-else>
          <div v-if="votes.length === 0" class="text-sm text-slate-500 text-center py-3">No votes yet.</div>
          <div v-for="v in votes" :key="v.user_id"
            class="flex items-center gap-3 py-2.5 border-b border-white/5 last:border-0">
            <div class="w-8 h-8 rounded-full shrink-0 flex items-center justify-center text-xs font-bold text-slate-950"
              style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
              {{ (v.display_name || '?')[0].toUpperCase() }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium truncate">{{ v.display_name }}</div>
              <div class="text-[10px] text-slate-600">{{ timeAgo(v.voted_at) }}</div>
            </div>
            <span class="text-lg" :class="v.vote === 'attending' ? 'text-emerald-400' : 'text-rose-400'">
              {{ v.vote === 'attending' ? '✅' : '❌' }}
            </span>
          </div>
        </div>
      </div>

      <!-- Share / copy -->
      <div class="flex gap-2">
        <button class="btn-ghost flex-1 text-xs py-2.5" @click="copyLink">
          {{ copied ? '✓ Copied!' : '🔗 Copy Poll Link' }}
        </button>
        <RouterLink to="/dashboard" class="btn-ghost text-xs px-4 py-2.5">Open App</RouterLink>
      </div>

    </template>
  </div>
</template>
