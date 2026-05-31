<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { clubs, loadClubs, selectClub } = useClub()

const allClubs     = ref([])
const myRequests   = ref([])   // { club_id, status }
const loading      = ref(true)
const busy         = ref(false)
const note         = ref(null)
const inviteResult = ref(null) // null | 'accepting' | 'success' | 'error'
const inviteMsg    = ref('')
const search       = ref('')

// Statuses keyed by club_id
const statusMap = computed(() => {
  const map = {}
  // already a member
  clubs.value.forEach(c => { map[c.club_id] = 'member' })
  // pending / rejected / approved requests
  myRequests.value.forEach(r => {
    if (!map[r.club_id]) map[r.club_id] = r.status
  })
  return map
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return q ? allClubs.value.filter(c => c.name.toLowerCase().includes(q)) : allClubs.value
})

async function load() {
  loading.value = true
  const [{ data: pub }, { data: reqs }] = await Promise.all([
    supabase.rpc('get_public_clubs'),
    supabase.from('join_requests').select('club_id, status'),
  ])
  allClubs.value   = pub ?? []
  myRequests.value = reqs ?? []
  loading.value    = false
}

async function requestJoin(clubId) {
  busy.value = true; note.value = null
  const { error } = await supabase.rpc('request_join', { p_club_id: clubId })
  if (error) {
    note.value = { ok: false, t: error.message }
  } else {
    myRequests.value = myRequests.value.filter(r => r.club_id !== clubId)
    myRequests.value.push({ club_id: clubId, status: 'pending' })
    note.value = { ok: true, t: 'Join request sent! The manager will review it shortly.' }
  }
  busy.value = false
}

// Accept an invite token from the URL query
async function acceptInvite(token) {
  inviteResult.value = 'accepting'
  const { data, error } = await supabase.rpc('accept_invite', { p_token: token })
  if (error) {
    inviteResult.value = 'error'
    inviteMsg.value = error.message
  } else {
    inviteResult.value = 'success'
    inviteMsg.value = 'You have joined the club!'
    await loadClubs()
    const joined = clubs.value.find(c => c.club_id === data)
    if (joined) selectClub(joined)
    setTimeout(() => router.push('/dashboard'), 1800)
  }
}

onMounted(async () => {
  await loadClubs()
  await load()
  const token = route.query.token
  if (token) acceptInvite(token)
})
</script>

<template>
  <!-- Invite token banner -->
  <div v-if="route.query.token" class="mb-5">
    <div v-if="inviteResult === 'accepting'" class="card-neon p-5 text-center fade-up">
      <div class="text-3xl mb-3 animate-spin">🏸</div>
      <p class="text-neon font-semibold">Accepting your invite…</p>
    </div>
    <div v-else-if="inviteResult === 'success'" class="card p-5 text-center fade-up"
      style="border-color:rgba(16,185,129,.3)">
      <div class="text-4xl mb-3">🎉</div>
      <p class="text-emerald-400 font-bold text-lg">You're in!</p>
      <p class="text-slate-400 text-sm mt-1">Redirecting to your new team…</p>
    </div>
    <div v-else-if="inviteResult === 'error'" class="card p-5 text-center fade-up"
      style="border-color:rgba(244,63,94,.3)">
      <div class="text-4xl mb-3">❌</div>
      <p class="text-rose-400 font-semibold">{{ inviteMsg }}</p>
      <p class="text-slate-500 text-xs mt-2">The link may have expired or already been used.</p>
    </div>
  </div>

  <!-- Header -->
  <div class="mb-6 fade-up" v-if="!route.query.token || inviteResult === 'error'">
    <div class="flex items-center gap-3 mb-1">
      <span class="text-3xl">🏟️</span>
      <div>
        <h2 class="font-display text-2xl font-bold gradient-text leading-tight">Find Your Team</h2>
        <p class="text-slate-400 text-sm">Browse clubs and request to join</p>
      </div>
    </div>
  </div>

  <!-- Search -->
  <div v-if="!route.query.token || inviteResult === 'error'" class="mb-4 fade-up">
    <div class="relative">
      <span class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm">🔍</span>
      <input v-model="search" class="input pl-9" placeholder="Search clubs…" />
    </div>
  </div>

  <!-- Status note -->
  <div v-if="note" class="mb-4 rounded-xl px-4 py-3 text-sm fade-up"
    :class="note.ok ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/20'
                    : 'bg-rose-500/15 text-rose-300 border border-rose-500/20'">
    {{ note.t }}
  </div>

  <!-- Loading skeletons -->
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="card h-20 shimmer" />
  </div>

  <!-- Club list -->
  <div v-else-if="!route.query.token || inviteResult === 'error'"
    class="space-y-3 fade-up">
    <div v-if="!filtered.length" class="card p-8 text-center text-slate-400">
      <div class="text-3xl mb-3">🏸</div>
      <p class="text-sm">No clubs found. Ask your manager to invite you directly.</p>
    </div>

    <div v-for="club in filtered" :key="club.id"
      class="card p-4 flex items-center justify-between gap-3 transition-all duration-200"
      :class="statusMap[club.id] === 'member' ? 'card-neon' : 'hover:border-white/15'">

      <!-- Info -->
      <div class="min-w-0">
        <div class="font-semibold text-slate-100 truncate">{{ club.name }}</div>
        <div class="text-[11px] text-slate-500 mt-0.5">
          👥 {{ club.member_count }} member{{ club.member_count !== 1 ? 's' : '' }}
        </div>
      </div>

      <!-- Action -->
      <div class="shrink-0">
        <span v-if="statusMap[club.id] === 'member'" class="badge-member">✓ Joined</span>
        <span v-else-if="statusMap[club.id] === 'approved'" class="badge-approved">Approved</span>
        <span v-else-if="statusMap[club.id] === 'rejected'" class="badge-rejected">Declined</span>
        <span v-else-if="statusMap[club.id] === 'pending'" class="badge-pending">⏳ Pending</span>
        <button v-else
          class="btn-primary text-xs px-3 py-1.5"
          :disabled="busy"
          @click="requestJoin(club.id)">
          Request to Join
        </button>
      </div>
    </div>
  </div>
</template>
