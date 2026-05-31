<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const router = useRouter()
const { user } = useAuth()
const { clubs, currentClub } = useClub()

// ── Data ──
const allClubs    = ref([])
const topPlayers  = ref([])
const myRequests  = ref([])
const loadingClubs   = ref(true)
const loadingPlayers = ref(true)
const playersError   = ref(null)
const showAllPlayers = ref(false)

// ── Filters ──
const searchQ       = ref('')
const emirateFilter = ref('')
const activeTab     = ref('clubs')   // 'clubs' | 'players'

const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

// ── Computed ──
const myClubIds = computed(() => clubs.value.map(c => c.club_id))

const requestMap = computed(() => {
  const m = {}
  myClubIds.value.forEach(id => { m[id] = 'member' })
  myRequests.value.forEach(r => { if (!m[r.club_id]) m[r.club_id] = r.status })
  return m
})

const filteredClubs = computed(() => {
  let list = allClubs.value
  if (emirateFilter.value)
    list = list.filter(c => c.emirates === emirateFilter.value)
  if (searchQ.value.trim()) {
    const q = searchQ.value.trim().toLowerCase()
    list = list.filter(c =>
      c.name.toLowerCase().includes(q) ||
      (c.facility_name || '').toLowerCase().includes(q) ||
      (c.facility_address || '').toLowerCase().includes(q)
    )
  }
  // Own clubs always first, then sorted by club_score
  return [...list].sort((a, b) => {
    const aOwn = myClubIds.value.includes(a.id) ? 1 : 0
    const bOwn = myClubIds.value.includes(b.id) ? 1 : 0
    if (bOwn !== aOwn) return bOwn - aOwn
    return (b.club_rank ?? 999) - (a.club_rank ?? 999) // lower rank number = better
  })
})

const filteredPlayers = computed(() => {
  let list = topPlayers.value
  if (emirateFilter.value)
    list = list.filter(p => p.emirates === emirateFilter.value)
  if (searchQ.value.trim()) {
    const q = searchQ.value.trim().toLowerCase()
    list = list.filter(p =>
      p.public_name.toLowerCase().includes(q) ||
      p.club_name.toLowerCase().includes(q)
    )
  }
  return showAllPlayers.value ? list : list.slice(0, 15)
})

// ── Load ──
async function loadData() {
  loadingClubs.value = true; loadingPlayers.value = true
  const tasks = [
    supabase.rpc('get_public_clubs'),
    supabase.rpc('get_top_scorers', { p_limit: 200 }),
  ]
  if (user.value) tasks.push(supabase.from('join_requests').select('club_id, status'))
  const [clubsRes, playersRes, reqsRes] = await Promise.all(tasks)
  allClubs.value   = clubsRes.data    ?? []
  topPlayers.value = playersRes.data  ?? []
  myRequests.value = reqsRes?.data    ?? []
  if (playersRes.error) playersError.value = playersRes.error.message
  loadingClubs.value = false; loadingPlayers.value = false
}

onMounted(loadData)

// ── Actions ──
const busy = ref(false)
const note = ref(null)

async function requestJoin(clubId) {
  if (!user.value) { router.push('/login'); return }
  busy.value = true; note.value = null
  const { error } = await supabase.rpc('request_join', { p_club_id: clubId })
  if (error) { note.value = { ok: false, t: error.message } }
  else {
    myRequests.value = myRequests.value.filter(r => r.club_id !== clubId)
    myRequests.value.push({ club_id: clubId, status: 'pending' })
    note.value = { ok: true, t: 'Request sent! The manager will review shortly.' }
  }
  busy.value = false
}

// ── Helpers ──
const rankIcon = (i) => ['🥇','🥈','🥉'][i] ?? `#${i+1}`
const activityLabel = (m30) =>
  m30 === 0 ? 'Inactive' : m30 < 5 ? 'Occasional' : m30 < 15 ? 'Active' : 'Very Active'
const activityColor = (m30) =>
  m30 === 0 ? 'text-slate-600' : m30 < 5 ? 'text-amber-400' : m30 < 15 ? 'text-cyan-400' : 'text-emerald-400'
</script>

<template>
  <!-- Search bar -->
  <div class="mb-4 fade-up">
    <div class="relative mb-3">
      <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-500">🔍</span>
      <input v-model="searchQ" class="input pl-10"
        :placeholder="activeTab === 'clubs' ? 'Search clubs or facilities…' : 'Search players or clubs…'" />
    </div>
    <!-- Emirate filter chips -->
    <div class="flex gap-1.5 overflow-x-auto pb-1 scrollbar-none">
      <button v-for="e in ['', ...EMIRATES]" :key="e"
        class="shrink-0 text-[10px] font-semibold px-2.5 py-1 rounded-full border transition-all duration-200"
        :class="emirateFilter === e
          ? 'bg-cyan-500/20 border-cyan-500/50 text-cyan-400'
          : 'border-white/10 text-slate-500 hover:border-white/25'"
        @click="emirateFilter = e">
        {{ e || 'All UAE' }}
      </button>
    </div>
  </div>

  <!-- Tab switcher -->
  <div class="flex gap-1 mb-5 p-1 rounded-xl fade-up" style="background:rgba(255,255,255,.04); border:1px solid rgba(255,255,255,.07)">
    <button v-for="tab in [{id:'clubs',label:'🏢 Clubs'},{id:'players',label:'🏆 Top Players'}]"
      :key="tab.id"
      class="flex-1 text-sm font-semibold py-2 rounded-lg transition-all duration-200"
      :class="activeTab === tab.id
        ? 'text-slate-950 shadow-sm'
        : 'text-slate-400 hover:text-slate-300'"
      :style="activeTab === tab.id ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)' : ''"
      @click="activeTab = tab.id">
      {{ tab.label }}
    </button>
  </div>

  <!-- ── Note ── -->
  <div v-if="note" class="mb-4 rounded-xl px-4 py-2.5 text-sm fade-up"
    :class="note.ok ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/20'
                    : 'bg-rose-500/15 text-rose-300 border border-rose-500/20'">
    {{ note.t }}
  </div>

  <!-- ══════════════ CLUBS TAB ══════════════ -->
  <div v-if="activeTab === 'clubs'" class="space-y-3 fade-up">

    <div v-if="loadingClubs" class="space-y-3">
      <div v-for="i in 5" :key="i" class="h-24 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!filteredClubs.length" class="card p-8 text-center">
      <div class="text-3xl mb-3">🏸</div>
      <p class="text-slate-400 text-sm">No clubs found. Be the first to create one!</p>
      <button class="btn-primary mt-4 px-6" @click="router.push('/manage')">Create a Club</button>
    </div>

    <div v-for="(club, i) in filteredClubs" :key="club.id"
      class="card p-4 transition-all duration-200"
      :class="myClubIds.includes(club.id) ? 'card-neon' : 'hover:border-white/15'">

      <!-- Top row: rank + name + emirate + status -->
      <div class="flex items-start justify-between gap-2 mb-2">
        <div class="flex items-start gap-2.5 min-w-0">
          <div class="text-xl shrink-0 mt-0.5">{{ rankIcon(i) }}</div>
          <div class="min-w-0">
            <RouterLink :to="'/club/' + club.id"
              class="font-bold text-slate-100 hover:text-neon transition-colors block truncate">
              {{ club.name }}
            </RouterLink>
            <div class="text-[11px] text-slate-500 truncate">
              {{ [club.facility_name, club.emirates].filter(Boolean).join(' · ') || 'No facility info' }}
            </div>
          </div>
        </div>
        <!-- Action button -->
        <div class="shrink-0">
          <span v-if="requestMap[club.id] === 'member'" class="badge-member">✓ My Club</span>
          <span v-else-if="requestMap[club.id] === 'pending'" class="badge-pending">⏳ Pending</span>
          <span v-else-if="requestMap[club.id] === 'approved'" class="badge-approved">Approved</span>
          <button v-else class="btn-primary text-xs px-3 py-1.5" :disabled="busy"
            @click="requestJoin(club.id)">
            Join
          </button>
        </div>
      </div>

      <!-- Stats row -->
      <div class="grid grid-cols-4 gap-2 mt-3">
        <div class="text-center">
          <div class="text-sm font-bold text-neon">{{ club.club_score ?? 10 }}</div>
          <div class="text-[9px] text-slate-600 uppercase tracking-wider">Score</div>
        </div>
        <div class="text-center">
          <div class="text-sm font-bold text-slate-200">{{ club.total_members }}</div>
          <div class="text-[9px] text-slate-600 uppercase tracking-wider">Members</div>
        </div>
        <div class="text-center">
          <div class="text-sm font-bold text-slate-200">{{ club.active_30d }}</div>
          <div class="text-[9px] text-slate-600 uppercase tracking-wider">Active/mo</div>
        </div>
        <div class="text-center">
          <div class="text-sm font-bold" :class="activityColor(club.matches_30d)">
            {{ club.matches_30d }}
          </div>
          <div class="text-[9px] text-slate-600 uppercase tracking-wider">Matches/mo</div>
        </div>
      </div>

      <!-- Facility address + maps link -->
      <div v-if="club.facility_address || club.maps_url" class="mt-2.5 pt-2.5 border-t border-white/[0.05] flex items-center justify-between gap-2">
        <span class="text-[11px] text-slate-500 truncate">📍 {{ club.facility_address }}</span>
        <a v-if="club.maps_url" :href="club.maps_url" target="_blank" rel="noopener"
          class="shrink-0 text-[11px] text-neon hover:opacity-80 transition">Maps →</a>
      </div>
    </div>

    <!-- Join prompt for non-logged-in users -->
    <div v-if="!user" class="card-neon p-6 text-center mt-4">
      <div class="text-3xl mb-3">🏸</div>
      <p class="font-bold gradient-text text-lg mb-1">Join Your Team on Badmint</p>
      <p class="text-slate-400 text-sm mb-4">Free Elo rankings for UAE badminton courts. Sign in with Google to get started.</p>
      <button class="btn-primary px-8" @click="router.push('/login')">Sign In Free →</button>
    </div>
  </div>

  <!-- ══════════════ TOP PLAYERS TAB ══════════════ -->
  <div v-else class="fade-up">

    <div v-if="loadingPlayers" class="space-y-2">
      <div v-for="i in 8" :key="i" class="h-12 shimmer rounded-xl" />
    </div>

    <div v-else-if="playersError" class="card p-6 text-center fade-up"
      style="border-color:rgba(244,63,94,.3)">
      <div class="text-2xl mb-2">⚠️</div>
      <p class="text-rose-400 text-sm font-semibold mb-1">Could not load players</p>
      <p class="text-slate-500 text-xs">{{ playersError }}</p>
      <p class="text-slate-600 text-xs mt-2">Run <code class="text-slate-400">v2_schema.sql</code> again in Supabase SQL Editor.</p>
    </div>

    <div v-else-if="!filteredPlayers.length" class="card p-8 text-center text-slate-400 text-sm">
      <div class="text-3xl mb-3">🏆</div>
      <p>No players yet. Record at least 1 match to appear here.</p>
    </div>

    <div v-else>
      <!-- Header -->
      <div class="card overflow-hidden">
        <div class="px-4 py-2.5 border-b border-white/[0.06] grid grid-cols-12 text-[9px] uppercase tracking-wider text-slate-600">
          <span class="col-span-1">#</span>
          <span class="col-span-5">Player</span>
          <span class="col-span-3 text-right">Club</span>
          <span class="col-span-1 text-right">Elo</span>
          <span class="col-span-2 text-right">W%</span>
        </div>

        <div v-for="(p, i) in filteredPlayers" :key="p.player_id"
          class="grid grid-cols-12 items-center px-4 py-2.5 border-b border-white/[0.04] last:border-0 transition-colors hover:bg-white/[0.02]"
          :class="i < 3 ? 'bg-white/[0.01]' : ''">
          <span class="col-span-1 text-sm font-bold" :class="i < 3 ? 'text-gold' : 'text-slate-500'">
            {{ ['🥇','🥈','🥉'][i] ?? p.global_rank }}
          </span>
          <div class="col-span-5">
            <div class="text-sm font-semibold text-slate-100 truncate">{{ p.public_name }}</div>
            <div class="text-[10px] text-slate-600">{{ p.emirates }}</div>
          </div>
          <div class="col-span-3 text-right text-[11px] text-slate-400 truncate pl-1">{{ p.club_name }}</div>
          <div class="col-span-1 text-right text-sm font-bold text-neon">{{ p.elo }}</div>
          <div class="col-span-2 text-right text-xs text-slate-400">{{ p.win_pct }}%</div>
        </div>
      </div>

      <!-- Show all button -->
      <div v-if="!showAllPlayers && topPlayers.length > 15" class="mt-3 text-center">
        <button class="btn-ghost px-8 text-sm" @click="showAllPlayers = true">
          Show All {{ topPlayers.length }} Players
        </button>
      </div>
    </div>
  </div>
</template>
