<script setup>
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { clubs, loadClubs, selectClub } = useClub()

// ── State ──
const allClubs     = ref([])
const myRequests   = ref([])
const loading      = ref(true)
const busy         = ref(false)
const note         = ref(null)

// Invite token flow
const inviteStep   = ref(null)  // null | 'onboarding' | 'accepting' | 'success' | 'error'
const inviteError  = ref('')

// Onboarding form (shown for new users coming via invite link)
const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']
const form = ref({ fullName: '', nickname: '', phone: '', emirate: '', country: 'UAE' })
const formErrors = ref({})
const search = ref('')

// ── Status map ──
const statusMap = computed(() => {
  const map = {}
  clubs.value.forEach(c => { map[c.club_id] = 'member' })
  myRequests.value.forEach(r => { if (!map[r.club_id]) map[r.club_id] = r.status })
  return map
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return q ? allClubs.value.filter(c => c.name.toLowerCase().includes(q)) : allClubs.value
})

// ── Load ──
async function load() {
  loading.value = true
  const tasks = [supabase.rpc('get_public_clubs')]
  if (user.value) tasks.push(supabase.from('join_requests').select('club_id, status'))
  const [clubsRes, reqsRes] = await Promise.all(tasks)
  allClubs.value   = clubsRes.data   ?? []
  myRequests.value = reqsRes?.data   ?? []
  loading.value    = false
}

// ── Invite token flow ──
async function handleToken(token) {
  if (!user.value) return  // router guard ensures user is logged in before reaching here

  // Check if this user already has a profile (nickname set)
  const { data: prof } = await supabase
    .from('user_profiles')
    .select('nickname, full_name')
    .eq('user_id', user.value.id)
    .maybeSingle()

  if (prof?.nickname) {
    // Returning user — skip onboarding, accept directly
    await acceptInvite(token)
  } else {
    // New user — pre-fill what we know from Google
    form.value.fullName  = user.value.user_metadata?.full_name ?? ''
    form.value.nickname  = (user.value.user_metadata?.full_name ?? '').split(' ')[0]
    inviteStep.value = 'onboarding'
  }
}

function validateForm() {
  formErrors.value = {}
  if (!form.value.fullName.trim())  formErrors.value.fullName  = 'Full name is required'
  if (!form.value.nickname.trim())  formErrors.value.nickname  = 'Nickname is required'
  return Object.keys(formErrors.value).length === 0
}

async function submitOnboarding() {
  if (!validateForm()) return
  busy.value = true
  // Save profile first
  const { error: profErr } = await supabase.rpc('upsert_profile', {
    p_nickname:  form.value.nickname.trim(),
    p_full_name: form.value.fullName.trim(),
    p_phone:     form.value.phone.trim()   || null,
    p_emirate:   form.value.emirate        || null,
    p_country:   form.value.country        || 'UAE',
  })
  if (profErr) { inviteError.value = profErr.message; inviteStep.value = 'error'; busy.value = false; return }

  await acceptInvite(route.query.token)
}

async function acceptInvite(token) {
  inviteStep.value = 'accepting'
  const { data: clubId, error } = await supabase.rpc('accept_invite', { p_token: token })
  if (error) {
    inviteStep.value = 'error'
    inviteError.value = error.message
    busy.value = false
    return
  }
  inviteStep.value = 'success'
  await loadClubs()
  const joined = clubs.value.find(c => c.club_id === clubId)
  if (joined) selectClub(joined)
  setTimeout(() => router.push('/dashboard'), 1800)
  busy.value = false
}

// ── Join request ──
async function requestJoin(clubId) {
  busy.value = true; note.value = null
  const { error } = await supabase.rpc('request_join', { p_club_id: clubId })
  if (error) {
    note.value = { ok: false, t: error.message }
  } else {
    myRequests.value = myRequests.value.filter(r => r.club_id !== clubId)
    myRequests.value.push({ club_id: clubId, status: 'pending' })
    note.value = { ok: true, t: 'Join request sent! The manager will review shortly.' }
  }
  busy.value = false
}

onMounted(async () => {
  await loadClubs()
  await load()
  if (route.query.token) handleToken(route.query.token)
})
</script>

<template>

  <!-- ══ INVITE TOKEN FLOW ══ -->
  <template v-if="route.query.token">

    <!-- Accepting spinner -->
    <div v-if="inviteStep === 'accepting'" class="card-neon p-8 text-center fade-up">
      <div class="text-4xl mb-3 animate-spin">🏸</div>
      <p class="text-neon font-semibold">Joining the club…</p>
    </div>

    <!-- Success -->
    <div v-else-if="inviteStep === 'success'" class="card p-8 text-center fade-up"
      style="border-color:rgba(16,185,129,.3)">
      <div class="text-5xl mb-3">🎉</div>
      <p class="font-display text-xl font-bold text-emerald-400 mb-1">You're in!</p>
      <p class="text-slate-400 text-sm">Redirecting to your new team…</p>
    </div>

    <!-- Error -->
    <div v-else-if="inviteStep === 'error'" class="card p-8 text-center fade-up"
      style="border-color:rgba(244,63,94,.3)">
      <div class="text-4xl mb-3">❌</div>
      <p class="text-rose-400 font-semibold mb-1">{{ inviteError }}</p>
      <p class="text-slate-500 text-xs">The link may have expired or already been used.</p>
    </div>

    <!-- ── Onboarding form ── -->
    <div v-else-if="inviteStep === 'onboarding'" class="fade-up">

      <!-- Header -->
      <div class="text-center mb-6">
        <div class="text-5xl mb-3" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.5))">🏸</div>
        <h2 class="font-display text-2xl font-extrabold gradient-text mb-1">Welcome to Badmint!</h2>
        <p class="text-slate-400 text-sm">Set up your profile before joining the club</p>
      </div>

      <!-- Avatar preview (initials) -->
      <div class="flex justify-center mb-5">
        <div class="relative">
          <div class="w-20 h-20 rounded-2xl flex items-center justify-center text-2xl font-black text-slate-950"
            style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
            {{ (form.nickname || form.fullName || '?').slice(0,2).toUpperCase() }}
          </div>
          <div class="absolute -bottom-1 -right-1 text-[10px] bg-slate-800 border border-white/10 rounded-lg px-1.5 py-0.5 text-slate-400">
            Photo coming soon
          </div>
        </div>
      </div>

      <div class="card p-4 space-y-4">

        <!-- Full name -->
        <div>
          <label class="label">Full Name <span class="text-rose-400">*</span></label>
          <input v-model="form.fullName" class="input" placeholder="e.g. Ahmed Al Mansouri" maxlength="60" />
          <p v-if="formErrors.fullName" class="text-[11px] text-rose-400 mt-1">{{ formErrors.fullName }}</p>
        </div>

        <!-- Nickname -->
        <div>
          <label class="label">Nickname / Public Name <span class="text-rose-400">*</span></label>
          <input v-model="form.nickname" class="input" placeholder="e.g. Flash, Smasher, King" maxlength="30" />
          <p class="text-[10px] text-slate-500 mt-1">This name appears on the leaderboard and explore page.</p>
          <p v-if="formErrors.nickname" class="text-[11px] text-rose-400 mt-1">{{ formErrors.nickname }}</p>
        </div>

        <!-- Phone -->
        <div>
          <label class="label">Phone Number <span class="text-slate-600">(optional)</span></label>
          <input v-model="form.phone" class="input" type="tel" placeholder="+971 50 123 4567" />
          <p class="text-[10px] text-slate-500 mt-1">Only visible to you — never shown to others.</p>
        </div>

        <!-- Emirates -->
        <div>
          <label class="label">Emirate <span class="text-slate-600">(optional)</span></label>
          <select v-model="form.emirate" class="input">
            <option value="">— Select your emirate —</option>
            <option v-for="e in EMIRATES" :key="e" :value="e">{{ e }}</option>
          </select>
        </div>

        <!-- Country -->
        <div>
          <label class="label">Country</label>
          <input v-model="form.country" class="input" placeholder="UAE" maxlength="40" />
        </div>

      </div>

      <button class="btn-primary w-full mt-4 py-3.5 text-base"
        :disabled="busy" @click="submitOnboarding">
        {{ busy ? 'Saving…' : '🏸 Complete &amp; Join Club' }}
      </button>

      <p class="text-center text-[10px] text-slate-600 mt-3">
        Your phone and email are always private. Only your nickname is public.
      </p>
    </div>

    <!-- Loading (token present but step not determined yet) -->
    <div v-else class="card p-8 text-center fade-up">
      <div class="text-3xl mb-3 animate-pulse">🏸</div>
      <p class="text-slate-400 text-sm">Checking invite…</p>
    </div>

  </template>

  <!-- ══ BROWSE CLUBS ══ -->
  <template v-else>

    <!-- Header -->
    <div class="mb-5 fade-up">
      <h2 class="font-display text-2xl font-bold gradient-text leading-tight">Find Your Team</h2>
      <p class="text-slate-400 text-sm mt-0.5">Browse clubs and request to join</p>
    </div>

    <!-- Search -->
    <div class="relative mb-4 fade-up">
      <span class="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400">🔍</span>
      <input v-model="search" class="input pl-10" placeholder="Search clubs…" />
    </div>

    <!-- Note -->
    <div v-if="note" class="mb-4 rounded-xl px-4 py-2.5 text-sm fade-up"
      :class="note.ok
        ? 'bg-emerald-500/15 text-emerald-300 border border-emerald-500/20'
        : 'bg-rose-500/15 text-rose-300 border border-rose-500/20'">
      {{ note.t }}
    </div>

    <!-- Skeletons -->
    <div v-if="loading" class="space-y-3">
      <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
    </div>

    <!-- Club list -->
    <div v-else class="space-y-3 fade-up">
      <div v-if="!filtered.length" class="card p-8 text-center text-slate-400">
        <div class="text-3xl mb-3">🏸</div>
        <p class="text-sm">No clubs found. Ask your manager to invite you directly.</p>
      </div>

      <div v-for="club in filtered" :key="club.id"
        class="card p-4 flex items-center justify-between gap-3 transition-all duration-200"
        :class="statusMap[club.id] === 'member' ? 'card-neon' : 'hover:border-white/15'">
        <div class="min-w-0">
          <div class="font-semibold text-slate-100 truncate">{{ club.name }}</div>
          <div class="text-[11px] text-slate-500 mt-0.5">
            👥 {{ club.member_count }} member{{ club.member_count !== 1 ? 's' : '' }}
            <span v-if="club.emirates"> · {{ club.emirates }}</span>
          </div>
        </div>
        <div class="shrink-0">
          <span v-if="statusMap[club.id] === 'member'"   class="badge-member">✓ Joined</span>
          <span v-else-if="statusMap[club.id] === 'approved'" class="badge-approved">Approved</span>
          <span v-else-if="statusMap[club.id] === 'rejected'" class="badge-rejected">Declined</span>
          <span v-else-if="statusMap[club.id] === 'pending'"  class="badge-pending">⏳ Pending</span>
          <button v-else class="btn-primary text-xs px-3 py-1.5" :disabled="busy"
            @click="requestJoin(club.id)">
            Request to Join
          </button>
        </div>
      </div>
    </div>
  </template>

</template>
