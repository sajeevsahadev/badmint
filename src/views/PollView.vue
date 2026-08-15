<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import Avatar from '../components/Avatar.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { avatarMap, loadAvatars } = usePlayerAvatars()

const schedule = ref(null)
const loading  = ref(true)
const voting   = ref(null)
const votes    = ref([])
const showVotes    = ref(false)
const votesLoading = ref(false)
const copied   = ref(false)
const error    = ref(null)
const voteError = ref(null)
// Only club members may respond; non-members can view but not vote.
const canVote = computed(() => !!user.value && schedule.value?.is_member === true)
const isNonMember = computed(() => !!user.value && schedule.value?.is_member === false)
let _copiedTimer = null
onUnmounted(() => clearTimeout(_copiedTimer))

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
  if (isNonMember.value) return   // guarded in UI; server also rejects
  voting.value = option
  voteError.value = null
  const { error: err } = await supabase.rpc('vote_schedule', {
    p_schedule_id: schedule.value.id,
    p_vote:        option
  })
  if (err) {
    voteError.value = err.message
  } else {
    await loadSchedule()
  }
  voting.value = null
}

function joinClub() {
  if (!user.value) {
    sessionStorage.setItem('bm_after_login', route.fullPath)
    router.push('/login')
  } else {
    router.push(`/club/${schedule.value.club_id}`)
  }
}

async function loadVotes() {
  votesLoading.value = true
  const { data } = await supabase.rpc('get_schedule_votes', {
    p_schedule_id: schedule.value.id
  })
  votes.value = data ?? []
  await loadAvatars(votes.value.map(v => v.user_id))
  votesLoading.value = false
  showVotes.value = true
}

async function copyLink() {
  await navigator.clipboard.writeText(window.location.href)
  copied.value = true
  clearTimeout(_copiedTimer)
  _copiedTimer = setTimeout(() => { copied.value = false }, 2000)
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
        <div v-if="canVote" class="grid grid-cols-2 gap-3 mb-4">
          <button
            @click="castVote('attending')"
            :disabled="voting !== null || schedule.status === 'cancelled' || isNonMember"
            class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
            :class="schedule.my_vote === 'attending'
              ? 'bg-emerald-500/15 border-emerald-500/60'
              : 'border-[rgba(15,23,42,0.10)] hover:border-emerald-500/30 active:opacity-70'">
            <span class="text-3xl">✅</span>
            <span class="text-sm font-semibold text-slate-200">Attending</span>
            <span class="text-3xl font-bold text-emerald-400">{{ schedule.attending_count }}</span>
          </button>
          <button
            @click="castVote('not_attending')"
            :disabled="voting !== null || schedule.status === 'cancelled' || isNonMember"
            class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
            :class="schedule.my_vote === 'not_attending'
              ? 'bg-rose-500/15 border-rose-500/60'
              : 'border-[rgba(15,23,42,0.10)] hover:border-rose-500/30 active:opacity-70'">
            <span class="text-3xl">❌</span>
            <span class="text-sm font-semibold text-slate-200">Not Attending</span>
            <span class="text-3xl font-bold text-rose-400">{{ schedule.not_attending_count }}</span>
          </button>
        </div>

        <!-- Not signed in -->
        <div v-if="!user" class="rounded-xl px-3 py-3 mb-3 text-center text-xs"
          style="background:rgba(0,168,204,.08); border:1px solid rgba(0,168,204,.25)">
          <p class="text-slate-600 mb-2">Sign in to respond to this poll.</p>
          <button class="btn-primary text-xs px-4 py-2" @click="joinClub">Sign in</button>
        </div>

        <!-- Signed in but not a member of this club -->
        <div v-else-if="isNonMember" class="rounded-xl px-3 py-3 mb-3 text-center text-xs"
          style="background:rgba(251,191,36,.10); border:1px solid rgba(251,191,36,.35)">
          <p class="text-amber-700 font-semibold mb-1">You're not a member of {{ schedule.club_name }}</p>
          <p class="text-slate-500 mb-2">Join the club first to mark your attendance.</p>
          <button class="btn-primary text-xs px-4 py-2" @click="joinClub">Join {{ schedule.club_name }}</button>
        </div>

        <!-- Member: vote status -->
        <div v-else class="text-center text-xs mb-3">
          <span v-if="schedule.my_vote" :class="schedule.my_vote === 'attending' ? 'text-emerald-500' : 'text-rose-500'">
            Your vote: {{ schedule.my_vote === 'attending' ? 'Attending ✓' : 'Not Attending ✓' }}
            <button class="ml-2 text-slate-500 underline"
              @click="castVote(schedule.my_vote === 'attending' ? 'not_attending' : 'attending')">
              change
            </button>
          </span>
          <span v-else class="text-slate-500">Tap a button to respond</span>
        </div>

        <p v-if="voteError" class="text-center text-xs text-rose-500 mb-3">⚠ {{ voteError }}</p>

        <!-- Total + view votes (members only) -->
        <div v-if="canVote" class="flex items-center justify-between text-xs text-slate-600">
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
            class="flex items-center gap-3 py-2.5 border-b border-[rgba(15,23,42,0.05)] last:border-0">
            <Avatar :name="v.display_name || '?'" :src="avatarMap[v.user_id]" :size="32" />
            <div class="flex-1 min-w-0">
              <div class="text-sm font-medium text-slate-100 truncate">{{ v.display_name || 'Unknown' }}</div>
              <div class="text-[10px] text-slate-500">{{ timeAgo(v.voted_at) }}</div>
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
