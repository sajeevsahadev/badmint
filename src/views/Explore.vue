<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import { useGeo } from '../composables/useGeo'
import { countryName } from '../utils/countries'

const router = useRouter()
const { user } = useAuth()
const { clubs, currentClub, loadClubs } = useClub()
const { countryCode, flagEmoji, detectCountry } = useGeo()

// ── Data ──
const allClubs      = ref([])
const allFacilities = ref([])
const myRequests    = ref([])
const loadingClubs  = ref(true)
const loadingFac    = ref(true)

// ── Filters ──
const searchQ   = ref('')
const activeTab = ref('clubs')   // 'clubs' | 'facilities'

// Country filter — defaults to the visitor's IP-detected country (server-side
// filtered via get_public_clubs(p_country_code); see JoinClub.vue for the
// same pattern and the scale rationale).
const countryFilter  = ref(countryCode.value || '')
const countryOptions = ref([])
async function loadCountryOptions() {
  const { data } = await supabase.rpc('get_club_countries')
  countryOptions.value = data ?? []
}

// ── Computed ──
const myClubIds = computed(() => clubs.value.map(c => c.club_id))

const requestMap = computed(() => {
  const m = {}
  myClubIds.value.forEach(id => { m[id] = 'member' })
  myRequests.value.forEach(r => {
    if (!m[r.club_id] && r.status === 'pending') m[r.club_id] = 'pending'
  })
  return m
})

const filteredClubs = computed(() => {
  let list = allClubs.value
  if (searchQ.value.trim()) {
    const q = searchQ.value.trim().toLowerCase()
    list = list.filter(c =>
      c.name.toLowerCase().includes(q) ||
      (c.facility_name || '').toLowerCase().includes(q) ||
      (c.facility_address || '').toLowerCase().includes(q)
    )
  }
  return [...list].sort((a, b) => {
    const aOwn = myClubIds.value.includes(a.id) ? 1 : 0
    const bOwn = myClubIds.value.includes(b.id) ? 1 : 0
    if (bOwn !== aOwn) return bOwn - aOwn
    return (b.club_rank ?? 999) - (a.club_rank ?? 999)
  })
})

const filteredFacilities = computed(() => {
  let list = allFacilities.value
  if (searchQ.value.trim()) {
    const q = searchQ.value.trim().toLowerCase()
    list = list.filter(f =>
      f.name.toLowerCase().includes(q) ||
      (f.address || '').toLowerCase().includes(q)
    )
  }
  return list
})

// ── Load ──
async function loadData() {
  loadingClubs.value = true; loadingFac.value = true
  const tasks = [
    supabase.rpc('get_public_clubs', { p_country_code: countryFilter.value || null }),
    supabase.rpc('get_facilities'),
  ]
  if (user.value) tasks.push(supabase.from('join_requests').select('club_id, status'))
  const [clubsRes, facRes, reqsRes] = await Promise.all(tasks)
  allClubs.value      = clubsRes.data ?? []
  allFacilities.value = facRes.data   ?? []
  myRequests.value    = reqsRes?.data ?? []
  loadingClubs.value = false; loadingFac.value = false
}

onMounted(async () => {
  loadCountryOptions()
  await detectCountry()
  if (!countryFilter.value && countryCode.value) countryFilter.value = countryCode.value
  await loadData()
})
watch(countryFilter, loadData)

// ── Actions ──
const busy        = ref(false)
const note        = ref(null)
const confirmClub = ref(null)   // club being confirmed for join request

// ── Create Facility (inline modal) ──
const showCreateFacility = ref(false)
const facBusy  = ref(false)
const facNote  = ref(null)
const newFac   = ref({ name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' })

async function createFacility() {
  if (!newFac.value.name.trim()) return
  facBusy.value = true; facNote.value = null
  const { data: fId, error } = await supabase.rpc('create_facility', {
    p_name:        newFac.value.name.trim(),
    p_address:     newFac.value.address     || null,
    p_emirate:     newFac.value.emirate     || null,
    p_maps_url:    newFac.value.maps_url    || null,
    p_image_url:   newFac.value.image_url   || null,
    p_phone:       newFac.value.phone       || null,
    p_website:     newFac.value.website     || null,
    p_description: newFac.value.description || null,
  })
  facBusy.value = false
  if (error) { facNote.value = { ok: false, t: error.message }; return }
  // Reload facilities and close modal
  const { data } = await supabase.rpc('get_facilities')
  allFacilities.value = data ?? []
  newFac.value = { name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' }
  facNote.value = null
  showCreateFacility.value = false
}

function confirmJoin(club) {
  if (!user.value) { router.push('/login'); return }
  const memberCount  = clubs.value.length
  const pendingCount = myRequests.value.filter(r => r.status === 'pending').length
  if (memberCount + pendingCount >= 10) {
    note.value = { ok: false, t: 'You can join or send requests to a maximum of 10 clubs. Leave a club or revoke a pending request first.' }
    return
  }
  confirmClub.value = club
}

async function requestJoin(clubId) {
  confirmClub.value = null
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

async function joinPublic(club) {
  if (!user.value) { router.push('/login'); return }
  busy.value = true; note.value = null
  const { error } = await supabase.rpc('join_club_public', { p_club_id: club.id })
  if (error) { note.value = { ok: false, t: error.message } }
  else {
    await loadClubs()
    note.value = { ok: true, t: `Joined ${club.name}! 🎉` }
  }
  busy.value = false
}

async function revokeRequest(clubId) {
  busy.value = true; note.value = null
  const { error } = await supabase.rpc('revoke_join_request', { p_club_id: clubId })
  if (error) { note.value = { ok: false, t: error.message } }
  else {
    myRequests.value = myRequests.value.filter(r => r.club_id !== clubId)
    note.value = { ok: true, t: 'Join request cancelled.' }
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
  <!-- Search bar + country filter (clubs only) -->
  <div class="flex gap-2 mb-4 fade-up">
    <div class="relative flex-1">
      <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none select-none leading-none">🔍</span>
      <input v-model="searchQ" class="input pl-11"
        placeholder="Search clubs and facilities…" />
    </div>
    <select v-if="activeTab === 'clubs'" v-model="countryFilter" class="input w-auto shrink-0" style="max-width:9.5rem">
      <option value="">🌍 All Countries</option>
      <option v-for="c in countryOptions" :key="c.country_code" :value="c.country_code">
        {{ flagEmoji(c.country_code) }} {{ countryName(c.country_code) }}
      </option>
    </select>
  </div>

  <!-- Tab switcher -->
  <div class="flex gap-1 mb-5 p-1 rounded-xl fade-up" style="background:rgba(255,255,255,.04); border:1px solid rgba(255,255,255,.07)">
    <button v-for="tab in [
        { id:'clubs',      label:'🏢 Clubs'      },
        { id:'facilities', label:'🏟️ Facilities' },
      ]"
      :key="tab.id"
      class="flex-1 text-xs font-semibold py-2.5 rounded-lg transition-all duration-200"
      :class="activeTab === tab.id ? 'text-slate-950 shadow-sm' : 'text-slate-400 hover:text-slate-300'"
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
      <button class="btn-primary mt-4 px-6" @click="router.push('/create-club')">Create a Club</button>
    </div>

    <div v-for="(club, i) in filteredClubs" :key="club.id"
      class="card p-4 transition-all duration-200"
      :class="myClubIds.includes(club.id) ? 'card-neon' : 'hover:border-[rgba(15,23,42,0.15)]'">

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
            <div v-if="club.join_policy === 'closed'" class="text-[11px] text-amber-500 mt-0.5">🔒 Closed — invite only</div>
            <div v-else-if="club.join_policy === 'public'" class="text-[11px] text-emerald-500 mt-0.5">⚡ Instant join</div>
          </div>
        </div>
        <!-- Action button -->
        <div class="shrink-0 flex flex-col items-end gap-1">
          <span v-if="requestMap[club.id] === 'member'" class="badge-member">✓ My Club</span>
          <span v-else-if="requestMap[club.id] === 'pending'" class="badge-pending">⏳ Pending</span>
          <span v-else-if="requestMap[club.id] === 'approved'" class="badge-approved">Approved</span>
          <span v-else-if="club.join_policy === 'closed'" class="badge text-slate-400" style="border:1px solid rgba(100,116,139,.4)">Closed</span>
          <button v-else-if="club.join_policy === 'public'" class="btn-primary text-xs px-3 py-1.5" :disabled="busy"
            @click="joinPublic(club)">
            ⚡ Join
          </button>
          <button v-else class="btn-primary text-xs px-3 py-1.5" :disabled="busy"
            @click="confirmJoin(club)">
            Join
          </button>
          <button v-if="requestMap[club.id] === 'pending'"
            class="text-[10px] text-rose-400 hover:text-rose-300 transition-colors leading-none mt-0.5"
            :disabled="busy" @click="revokeRequest(club.id)">
            ✕ Revoke
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
      <div v-if="club.facility_address || club.maps_url" class="mt-2.5 pt-2.5 border-t border-[rgba(15,23,42,0.05)] flex items-center justify-between gap-2">
        <span class="text-[11px] text-slate-500 truncate">📍 {{ club.facility_address }}</span>
        <a v-if="club.maps_url" :href="club.maps_url" target="_blank" rel="noopener"
          class="shrink-0 text-[11px] text-neon hover:opacity-80 transition">Maps →</a>
      </div>
    </div>

    <!-- Join prompt for non-logged-in users -->
    <div v-if="!user" class="card-neon p-6 text-center mt-4">
      <div class="text-3xl mb-3">🏸</div>
      <p class="font-bold gradient-text text-lg mb-1">Join Your Team on Badminton 360</p>
      <p class="text-slate-400 text-sm mb-4">Free Elo rankings for badminton courts everywhere. Sign in with Google to get started.</p>
      <button class="btn-primary px-8" @click="router.push('/login')">Sign In Free →</button>
    </div>
  </div>

  <!-- ══════════════ FACILITIES TAB ══════════════ -->
  <div v-else-if="activeTab === 'facilities'" class="fade-up">

    <div v-if="loadingFac" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
    </div>

    <div v-else-if="!filteredFacilities.length" class="card p-8 text-center">
      <div class="text-3xl mb-3">🏟️</div>
      <p class="text-slate-400 text-sm mb-4">No facilities listed yet.</p>
      <button v-if="user" class="btn-primary px-6 text-sm"
        @click="showCreateFacility = true">+ Add Your Facility</button>
      <RouterLink v-else to="/login" class="btn-primary px-6 text-sm">Sign in to Add</RouterLink>
    </div>

    <div v-else class="space-y-3">
      <RouterLink v-for="f in filteredFacilities" :key="f.id" :to="'/facility/' + f.id"
        class="card p-4 flex gap-3 transition-all duration-200 hover:border-[rgba(15,23,42,0.20)] hover:card-neon">

        <!-- Thumbnail -->
        <div class="w-14 h-14 rounded-xl overflow-hidden shrink-0">
          <img v-if="f.image_url" :src="f.image_url" :alt="f.name" class="w-full h-full object-cover" />
          <div v-else class="w-full h-full flex items-center justify-center font-black text-slate-950 text-sm"
            style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
            {{ (f.name ?? '?').slice(0, 2).toUpperCase() }}
          </div>
        </div>

        <!-- Info -->
        <div class="flex-1 min-w-0">
          <div class="font-bold text-slate-100 truncate">{{ f.name }}</div>
          <div class="text-[11px] text-slate-500 mt-0.5 truncate">
            {{ [f.address, f.emirate].filter(Boolean).join(' · ') }}
          </div>
          <div class="flex items-center gap-3 mt-1.5">
            <span class="text-[10px] text-neon font-semibold">{{ f.club_count }} club{{ f.club_count !== 1 ? 's' : '' }}</span>
            <span v-if="f.upcoming_count > 0" class="text-[10px] text-amber-400">
              {{ f.upcoming_count }} upcoming session{{ f.upcoming_count !== 1 ? 's' : '' }}
            </span>
          </div>
        </div>

        <span class="text-slate-700 text-sm self-center shrink-0">›</span>
      </RouterLink>

      <!-- Add facility CTA -->
      <button v-if="user"
        class="card p-4 w-full flex items-center justify-center gap-2 text-sm text-slate-500
               hover:text-neon hover:border-[rgba(15,23,42,0.15)] transition-all duration-200"
        @click="showCreateFacility = true">
        + Add Your Facility
      </button>
    </div>
  </div>

  <!-- ── Join Confirmation modal ── -->
  <Teleport to="body">
    <div v-if="confirmClub"
      class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.65); backdrop-filter:blur(4px)"
      @click.self="confirmClub = null">
      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#0d1a2e; border:1px solid rgba(0,229,255,.2); box-shadow:0 8px 40px rgba(0,0,0,.6)">
        <div class="text-3xl text-center mb-3">🏸</div>
        <h3 class="font-display text-lg font-bold text-center text-slate-100 mb-1">Send Join Request?</h3>
        <p class="text-sm text-slate-400 text-center mb-5">
          Request to join <span class="text-neon font-semibold">{{ confirmClub.name }}</span>.
          The manager will review and approve your request.
        </p>
        <div class="flex gap-3">
          <button class="btn-ghost flex-1 py-3 text-sm" @click="confirmClub = null">Cancel</button>
          <button class="btn-primary flex-1 py-3 text-sm" :disabled="busy"
            @click="requestJoin(confirmClub.id)">
            {{ busy ? 'Sending…' : 'Send Request' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>

  <!-- ── Create Facility modal ── -->
  <Teleport to="body">
    <div v-if="showCreateFacility"
      class="fixed inset-0 z-50 flex items-end"
      style="background:rgba(0,0,0,.65); backdrop-filter:blur(4px)"
      @click.self="showCreateFacility = false">
      <div class="w-full max-h-[90vh] overflow-y-auto rounded-t-3xl px-5 pt-5 pb-10"
        style="background:#0d1a2e; border-top:1px solid rgba(0,229,255,.25);
               box-shadow:0 -8px 40px rgba(0,229,255,.12);">

        <!-- Handle -->
        <div class="w-12 h-1 rounded-full bg-white/20 mx-auto mb-5"/>

        <div class="flex items-center justify-between mb-5">
          <div>
            <h3 class="font-display text-lg font-bold text-slate-100">Add a Facility</h3>
            <p class="text-[11px] text-slate-400 mt-0.5">Listed publicly · any club can link to it</p>
          </div>
          <button class="text-slate-500 hover:text-slate-200 text-xl leading-none transition"
            @click="showCreateFacility = false">✕</button>
        </div>

        <div class="space-y-3">
          <div>
            <label class="label">Facility Name <span class="text-rose-400">*</span></label>
            <input v-model="newFac.name" class="input" placeholder="e.g. Dubai Sports City, GEMS School Courts"
              maxlength="80" />
          </div>
          <div>
            <label class="label">Address</label>
            <input v-model="newFac.address" class="input" placeholder="e.g. Al Barsha, Dubai" maxlength="120" />
          </div>
          <div>
            <label class="label">Emirates</label>
            <select v-model="newFac.emirate" class="input">
              <option value="">— Select —</option>
              <option v-for="e in EMIRATES" :key="e" :value="e">{{ e }}</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="label">Phone <span class="text-slate-600">(optional)</span></label>
              <input v-model="newFac.phone" class="input" placeholder="+971 …" />
            </div>
            <div>
              <label class="label">Website <span class="text-slate-600">(optional)</span></label>
              <input v-model="newFac.website" class="input" placeholder="https://…" />
            </div>
          </div>
          <div>
            <label class="label">Google Maps URL <span class="text-slate-600">(optional)</span></label>
            <input v-model="newFac.maps_url" class="input" placeholder="https://maps.app.goo.gl/…" />
          </div>
          <div>
            <label class="label">Photo URL <span class="text-slate-600">(optional)</span></label>
            <input v-model="newFac.image_url" class="input" placeholder="Paste any image link" />
          </div>
          <div>
            <label class="label">Description <span class="text-slate-600">(optional)</span></label>
            <textarea v-model="newFac.description" class="input resize-none" rows="2"
              placeholder="Courts available, parking, access notes…" maxlength="300" />
          </div>
        </div>

        <p v-if="facNote" class="mt-3 text-xs rounded-xl px-3 py-2"
          :class="facNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
          {{ facNote.t }}
        </p>

        <div class="flex gap-2 mt-5">
          <button class="btn-ghost flex-1 py-3 text-sm" @click="showCreateFacility = false">Cancel</button>
          <button class="btn-primary flex-1 py-3 text-sm" :disabled="facBusy || !newFac.name.trim()"
            @click="createFacility">
            {{ facBusy ? 'Creating…' : '🏟️ Create Facility' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
