<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import Avatar from '../components/Avatar.vue'
import GamePlan from '../components/GamePlan.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { loadClubs } = useClub()
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
const joinError = ref(null)
let autoJoinTried = false
// Only club members may respond; non-members can view but not vote.
const canVote = computed(() => !!user.value && schedule.value?.is_member === true)
const isNonMember = computed(() => !!user.value && schedule.value?.is_member === false)
// Public clubs let anyone join instantly via the link (see scenarios 2 & 3).
const isPublicClub = computed(() => schedule.value?.join_policy === 'public')
let _copiedTimer = null
onUnmounted(() => clearTimeout(_copiedTimer))

const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
const DAYS   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']

const dateLabel = computed(() => {
  if (!schedule.value?.scheduled_date) return ''
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

// ── Time slot + attendee cap (both optional) ──
function fmtTime(t) {
  if (!t) return ''
  const [h, m] = t.split(':').map(Number)
  const ap = h >= 12 ? 'PM' : 'AM'
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${ap}`
}
const slotTime = computed(() => {
  const s = schedule.value
  if (!s?.start_time) return ''
  return s.end_time ? `${fmtTime(s.start_time)} – ${fmtTime(s.end_time)}` : fmtTime(s.start_time)
})
const maxAtt       = computed(() => schedule.value?.max_attendees || 0)
const presentCount = computed(() => {
  const a = schedule.value?.attending_count || 0
  return maxAtt.value ? Math.min(a, maxAtt.value) : a
})
const benchCount   = computed(() => {
  const a = schedule.value?.attending_count || 0
  return maxAtt.value ? Math.max(a - maxAtt.value, 0) : 0
})
const iAmBench = computed(() =>
  schedule.value?.my_vote === 'attending' && maxAtt.value > 0 && (schedule.value?.my_position || 0) > maxAtt.value
)

async function loadSchedule() {
  loading.value = true
  const { data, error: err } = await supabase.rpc('get_schedule_detail', {
    p_schedule_id: route.params.id
  })
  if (err || !data?.length) {
    error.value = 'Match day not found or the link has expired.'
    loading.value = false
    return
  }
  schedule.value = data[0]

  // Scenario 2: logged-in member of B360 but not of THIS club, and the club is
  // public → auto-join instantly, then re-fetch so the poll shows as a member.
  if (user.value && schedule.value.is_member === false && isPublicClub.value && !autoJoinTried) {
    autoJoinTried = true
    const { error: jerr } = await supabase.rpc('join_club_public', { p_club_id: schedule.value.club_id })
    sessionStorage.removeItem('bm_skip_intro')
    if (jerr) {
      joinError.value = jerr.message
    } else {
      // Refresh the app's club cache so the new membership is known app-wide.
      await loadClubs().catch(() => {})
      const { data: d2 } = await supabase.rpc('get_schedule_detail', { p_schedule_id: route.params.id })
      if (d2?.length) schedule.value = d2[0]
    }
  }
  loading.value = false
}

// Scenario 3: not signed in → sign in, then come back here and auto-join.
function signInToJoin() {
  sessionStorage.setItem('bm_after_login', route.fullPath)
  // Only suppress the first-run wizard when this poll's club will actually
  // auto-join them (public). Non-public sign-ins keep the normal onboarding.
  if (isPublicClub.value) sessionStorage.setItem('bm_skip_intro', '1')
  router.push('/login')
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
  <div class="min-h-screen px-4 pb-8 max-w-sm mx-auto" :class="user ? 'pt-[calc(env(safe-area-inset-top,0px)+3.25rem)]' : 'pt-8'">

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

      <!-- ── GATE: non-members. Public clubs get an instant-join path; others
           stay members-only. ── -->
      <div v-if="!canVote" class="card p-8 text-center">
        <!-- Not signed in -->
        <template v-if="!user">
          <div class="text-4xl mb-3">{{ isPublicClub ? '👋' : '🔒' }}</div>
          <template v-if="isPublicClub">
            <p class="font-semibold text-slate-700 mb-1">Join {{ schedule.club_name }}</p>
            <p class="text-sm text-slate-500 mb-5 leading-relaxed">Sign in and you'll join instantly and can vote in this poll.</p>
            <button class="btn-primary px-6 py-2.5" @click="signInToJoin">Sign in &amp; Join</button>
          </template>
          <template v-else>
            <p class="font-semibold text-slate-700 mb-1">Members only</p>
            <p class="text-sm text-slate-500 mb-5 leading-relaxed">Sign in to view and respond to this club's match poll.</p>
            <button class="btn-primary px-6 py-2.5" @click="signInToJoin">Sign in</button>
          </template>
        </template>
        <!-- Signed in but not a member -->
        <template v-else-if="isPublicClub">
          <!-- Only reached if auto-join failed (e.g. club cap). -->
          <div class="text-4xl mb-3">😕</div>
          <p class="font-semibold text-slate-700 mb-1">Couldn't join automatically</p>
          <p class="text-sm text-rose-500 mb-5 leading-relaxed">{{ joinError || 'Please try again in a moment.' }}</p>
          <RouterLink to="/dashboard" class="btn-ghost px-6 py-2.5">Open App</RouterLink>
        </template>
        <template v-else>
          <div class="text-4xl mb-3">🔒</div>
          <p class="font-semibold text-slate-700 mb-1">You're not a member of this club</p>
          <p class="text-sm text-slate-500 mb-5 leading-relaxed">This club is invite-only. Ask a club manager to add you.</p>
          <RouterLink to="/dashboard" class="btn-ghost px-6 py-2.5">Open App</RouterLink>
        </template>
      </div>

      <!-- ── MEMBER VIEW ── -->
      <template v-else>
        <!-- Schedule card -->
        <div class="card-neon p-5 mb-5">
          <div class="text-[10px] uppercase tracking-widest text-slate-500 mb-1">Match Day Poll</div>
          <h1 class="font-display text-xl font-bold gradient-text leading-snug">{{ dateLabel }}</h1>
          <div v-if="slotTime" class="text-sm text-slate-500 mt-1">🕒 {{ slotTime }}</div>
          <div v-if="venueName" class="text-sm text-slate-400 mt-1">📍 {{ venueName }}</div>
          <div class="text-xs text-slate-600 mt-0.5">{{ schedule.club_name }}</div>
          <div v-if="schedule.status === 'cancelled'"
            class="mt-2 inline-block text-xs bg-rose-500/20 text-rose-400 rounded px-2 py-0.5">Cancelled</div>
        </div>

        <!-- Poll -->
        <div class="card p-4 mb-4">
          <div class="grid grid-cols-2 gap-3 mb-4">
            <button @click="castVote('attending')" :disabled="voting !== null || schedule.status === 'cancelled'"
              class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
              :class="schedule.my_vote === 'attending' ? 'bg-emerald-500/15 border-emerald-500/60' : 'border-[rgba(15,23,42,0.10)] hover:border-emerald-500/30 active:opacity-70'">
              <span class="text-3xl">✅</span>
              <span class="text-sm font-semibold text-slate-700">Attending</span>
              <span class="text-3xl font-bold text-emerald-500">{{ schedule.attending_count }}</span>
            </button>
            <button @click="castVote('not_attending')" :disabled="voting !== null || schedule.status === 'cancelled'"
              class="rounded-2xl p-4 flex flex-col items-center gap-2 border transition"
              :class="schedule.my_vote === 'not_attending' ? 'bg-rose-500/15 border-rose-500/60' : 'border-[rgba(15,23,42,0.10)] hover:border-rose-500/30 active:opacity-70'">
              <span class="text-3xl">❌</span>
              <span class="text-sm font-semibold text-slate-700">Not Attending</span>
              <span class="text-3xl font-bold text-rose-500">{{ schedule.not_attending_count }}</span>
            </button>
          </div>

          <!-- Present / bench (only when a cap is set) -->
          <div v-if="maxAtt" class="text-center text-xs mb-2">
            <span class="text-slate-600">Present <b class="text-emerald-600">{{ presentCount }}</b> / {{ maxAtt }}</span>
            <span v-if="benchCount" class="text-slate-400"> · Bench {{ benchCount }}</span>
          </div>
          <div v-if="iAmBench" class="rounded-xl px-3 py-2 mb-3 text-center text-xs text-amber-700"
            style="background:rgba(251,191,36,.10);border:1px solid rgba(251,191,36,.35)">
            This slot is full — you're on the bench. You'll move up if someone drops out.
          </div>

          <div class="text-center text-xs mb-3">
            <span v-if="schedule.my_vote" :class="schedule.my_vote === 'attending' ? 'text-emerald-500' : 'text-rose-500'">
              Your vote: {{ schedule.my_vote === 'attending' ? 'Attending ✓' : 'Not Attending ✓' }}
              <button class="ml-2 text-slate-500 underline" @click="castVote(schedule.my_vote === 'attending' ? 'not_attending' : 'attending')">change</button>
            </span>
            <span v-else class="text-slate-500">Tap a button to respond</span>
          </div>
          <p v-if="voteError" class="text-center text-xs text-rose-500 mb-3">⚠ {{ voteError }}</p>

          <div class="flex items-center justify-between text-xs text-slate-600">
            <span>{{ totalVotes }} {{ totalVotes === 1 ? 'vote' : 'votes' }} total</span>
            <button class="underline text-slate-500 hover:text-slate-300 transition" @click="loadVotes">View Votes</button>
          </div>
        </div>

        <!-- Session game plan — read-only, updates live for everyone -->
        <GamePlan :schedule-id="schedule.id" :can-manage="false" class="mb-4" />
      </template>

      <!-- Votes list (inline, loads on demand) -->
      <div v-if="canVote && showVotes" class="card p-4 mb-4">
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
              <div class="text-sm font-medium text-slate-800 truncate">{{ v.display_name || 'Unknown' }}</div>
              <div class="text-[10px] text-slate-500">{{ timeAgo(v.voted_at) }}</div>
            </div>
            <span v-if="v.vote === 'attending' && !v.is_present"
              class="text-[9px] font-bold text-amber-600 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">BENCH</span>
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
