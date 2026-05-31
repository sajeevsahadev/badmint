<script setup>
import { ref, watch, onMounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { clubs, currentClub, loadClubs, createClub, isManager } = useClub()

const EMIRATES = ['Abu Dhabi','Dubai','Sharjah','Ajman','Umm Al Quwain','Ras Al Khaimah','Fujairah']

const newClub      = ref('')
const cfg          = ref(null)
const members      = ref([])
const requests     = ref([])
const inviteEmail  = ref('')
const inviteLink   = ref('')
const note         = ref(null)
const cfgNote      = ref(null)
const inviteNote   = ref(null)
const facNote      = ref(null)
const busy         = ref(false)

// Existing facility info (club's own fields)
const facility = ref({ emirates: '', facility_name: '', facility_address: '', maps_url: '', description: '' })

// Facility Master
const linkedFacility = ref(null)
const facSearch      = ref('')
const facResults     = ref([])
const newFac         = ref({ name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' })
const newFacNote     = ref(null)

const pendingRequests = computed(() => requests.value.filter(r => r.status === 'pending'))

async function load() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id
  const [{ data: c }, { data: m }, { data: r }, { data: playerNames }] = await Promise.all([
    supabase.from('ranking_config').select('*').eq('club_id', cid).single(),
    supabase.from('club_members').select('user_id, role').eq('club_id', cid),
    isManager()
      ? supabase.from('join_requests').select('*').eq('club_id', cid).order('created_at', { ascending: false })
      : { data: [] },
    // player display_names for this club (linked accounts only)
    supabase.from('players').select('user_id, display_name').eq('club_id', cid).not('user_id', 'is', null),
  ])
  cfg.value      = c
  requests.value = r ?? []

  // Enrich members with names from user_profiles (nickname > full_name) then players fallback
  const memberIds = (m ?? []).map(x => x.user_id)
  const { data: profiles } = memberIds.length
    ? await supabase.from('user_profiles').select('user_id, nickname, full_name').in('user_id', memberIds)
    : { data: [] }

  const profileMap = Object.fromEntries((profiles ?? []).map(p => [p.user_id, p]))
  const playerMap  = Object.fromEntries((playerNames ?? []).map(p => [p.user_id, p]))

  members.value = (m ?? []).map(member => ({
    ...member,
    display:
      profileMap[member.user_id]?.nickname ||
      profileMap[member.user_id]?.full_name ||
      playerMap[member.user_id]?.display_name ||
      '—',
  }))

  // Load current club facility info
  const { data: clubInfo } = await supabase.from('clubs')
    .select('emirates, facility_name, facility_address, maps_url, description, facility_id')
    .eq('id', cid).single()
  if (clubInfo) {
    facility.value.emirates         = clubInfo.emirates         ?? ''
    facility.value.facility_name    = clubInfo.facility_name    ?? ''
    facility.value.facility_address = clubInfo.facility_address ?? ''
    facility.value.maps_url         = clubInfo.maps_url         ?? ''
    facility.value.description      = clubInfo.description      ?? ''
    // Load linked facility master
    if (clubInfo.facility_id) {
      const { data: fac } = await supabase.from('facilities')
        .select('id, name, address, emirate').eq('id', clubInfo.facility_id).single()
      linkedFacility.value = fac ?? null
    } else {
      linkedFacility.value = null
    }
  }
}

onMounted(() => { loadClubs(); load() })
watch(currentClub, load)

// ── Create club ──
async function make() {
  if (!newClub.value.trim()) return
  busy.value = true; note.value = null
  try {
    await createClub(newClub.value.trim())
    newClub.value = ''
    note.value = { ok: true, t: '✅ Club created! You are now the owner.' }
  } catch (e) {
    note.value = { ok: false, t: e.message }
  }
  busy.value = false
}

// ── Ranking config ──
async function saveCfg() {
  const { elo_weight, participation_weight } = cfg.value
  const sum = Number(elo_weight) + Number(participation_weight)
  if (Math.abs(sum - 1) > 0.01) {
    cfgNote.value = { ok: false, t: `Skill + Attendance must total 1.0 (currently ${sum.toFixed(2)}).` }
    return
  }
  busy.value = true; cfgNote.value = null
  const { error } = await supabase.from('ranking_config')
    .update({ elo_weight, participation_weight, k_factor: 24 })
    .eq('club_id', currentClub.value.club_id)
  busy.value = false
  cfgNote.value = error
    ? { ok: false, t: `Save failed: ${error.message}` }
    : { ok: true, t: '✅ Weights saved. Leaderboard updates immediately.' }
}

// ── Join request actions ──
async function approveRequest(id) {
  const { error } = await supabase.rpc('approve_join', { p_request_id: id })
  if (error) { note.value = { ok: false, t: error.message }; return }
  requests.value = requests.value.map(r => r.id === id ? { ...r, status: 'approved' } : r)
}

async function rejectRequest(id) {
  const { error } = await supabase.rpc('reject_join', { p_request_id: id })
  if (error) { note.value = { ok: false, t: error.message }; return }
  requests.value = requests.value.map(r => r.id === id ? { ...r, status: 'rejected' } : r)
}

// ── Email invite ──
async function generateInvite() {
  if (!inviteEmail.value.trim()) return
  busy.value = true; inviteNote.value = null; inviteLink.value = ''
  const { data, error } = await supabase.rpc('invite_member', {
    p_club_id: currentClub.value.club_id,
    p_email: inviteEmail.value.trim(),
  })
  busy.value = false
  if (error) {
    inviteNote.value = { ok: false, t: error.message }
  } else {
    inviteLink.value = `${window.location.origin}/join?token=${data}`
    inviteNote.value = { ok: true, t: 'Invite link generated! Share it with the player.' }
  }
}

function copyLink() {
  navigator.clipboard.writeText(inviteLink.value)
  inviteNote.value = { ok: true, t: '✅ Link copied to clipboard!' }
}

function mailtoLink() {
  const club = currentClub.value?.clubs?.name ?? 'our club'
  const subj = encodeURIComponent(`You're invited to join ${club} on Badmint`)
  const body = encodeURIComponent(
    `Hi!\n\nYou've been invited to join "${club}" on Badmint — the smart ranking app for badminton teams.\n\nClick the link below to join:\n${inviteLink.value}\n\nThe link expires in 7 days.\n\nSee you on the court! 🏸`
  )
  return `mailto:${inviteEmail.value}?subject=${subj}&body=${body}`
}

// ── Save facility info ──
async function saveFacility() {
  busy.value = true; facNote.value = null
  const { error } = await supabase.rpc('update_club_facility', {
    p_club_id:          currentClub.value.club_id,
    p_emirates:         facility.value.emirates         || null,
    p_facility_name:    facility.value.facility_name    || null,
    p_facility_address: facility.value.facility_address || null,
    p_maps_url:         facility.value.maps_url         || null,
    p_description:      facility.value.description      || null,
  })
  busy.value = false
  facNote.value = error
    ? { ok: false, t: error.message }
    : { ok: true, t: '✅ Facility info saved. Visible on the Explore page.' }
}

// ── Facility Master functions ──
async function searchFacilities() {
  if (!facSearch.value.trim()) { facResults.value = []; return }
  const { data } = await supabase.rpc('get_facilities', { p_search: facSearch.value.trim() })
  facResults.value = (data ?? []).slice(0, 5)
}

async function linkFacility(f) {
  busy.value = true
  await supabase.rpc('set_club_facility', {
    p_club_id: currentClub.value.club_id,
    p_facility_id: f.id
  })
  linkedFacility.value = f
  facResults.value = []; facSearch.value = ''
  busy.value = false
}

async function unlinkFacility() {
  busy.value = true
  await supabase.rpc('set_club_facility', {
    p_club_id: currentClub.value.club_id,
    p_facility_id: null
  })
  linkedFacility.value = null
  busy.value = false
}

async function createAndLinkFacility() {
  if (!newFac.value.name.trim()) return
  busy.value = true; newFacNote.value = null
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
  if (error) { newFacNote.value = { ok: false, t: error.message }; busy.value = false; return }
  await supabase.rpc('set_club_facility', { p_club_id: currentClub.value.club_id, p_facility_id: fId })
  linkedFacility.value = { id: fId, name: newFac.value.name, address: newFac.value.address }
  newFac.value = { name:'', address:'', emirate:'', maps_url:'', image_url:'', phone:'', website:'', description:'' }
  newFacNote.value = { ok: true, t: '✅ Facility created and linked!' }
  busy.value = false
}

async function changeRole(userId, newRole) {
  const { error } = await supabase
    .from('club_members')
    .update({ role: newRole })
    .eq('club_id', currentClub.value.club_id)
    .eq('user_id', userId)
  if (error) {
    note.value = { ok: false, t: 'Role update failed: ' + error.message }
  } else {
    members.value = members.value.map(m =>
      m.user_id === userId ? { ...m, role: newRole } : m
    )
  }
}

const roleLabel = r => ({ owner: '👑 Owner', manager: '🛠 Manager', player: '🏸 Player' }[r] ?? r)
</script>

<template>
  <PageHeader icon="⚙️" title="Manage" subtitle="Clubs, members, and ranking settings">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-white">Create a Club</strong> — Each club has its own roster, matches, and leaderboard. You become the owner.</p>
        <p><strong class="text-white">Roles:</strong> 👑 Owner has full control. 🛠 Manager records matches. 🏸 Player views dashboards.</p>
        <p><strong class="text-white">Join Requests</strong> — Players who request to join appear here. Approve to add them.</p>
        <p><strong class="text-white">Invite by Email</strong> — Generate a 7-day invite link and send it to anyone.</p>
        <p><strong class="text-white">Ranking Weights</strong> — Tune skill vs attendance. Must add to 1.0. K-factor controls Elo swing per match.</p>
      </div>
    </template>
  </PageHeader>

  <!-- ── Pending Join Requests ── -->
  <div v-if="currentClub && isManager() && requests.length" class="card-violet p-4 mb-4 fade-up">
    <div class="flex items-center justify-between mb-3">
      <div class="label mb-0">Join Requests — {{ currentClub.clubs?.name }}</div>
      <span v-if="pendingRequests.length" class="badge-dot">{{ pendingRequests.length }}</span>
    </div>

    <div class="space-y-2">
      <div v-for="r in requests" :key="r.id"
        class="flex items-center gap-3 py-2.5 px-3 rounded-xl bg-white/[0.03] border border-white/[0.06]">
        <!-- Avatar initial -->
        <div class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
          style="background: linear-gradient(135deg, rgba(168,85,247,.3), rgba(0,229,255,.2));">
          {{ (r.user_name || '?').charAt(0).toUpperCase() }}
        </div>
        <!-- Info -->
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold text-slate-100 truncate">{{ r.user_name }}</div>
          <div class="text-[10px] text-slate-500 truncate">{{ r.user_email }}</div>
        </div>
        <!-- Status / actions -->
        <div class="shrink-0 flex items-center gap-1.5">
          <span v-if="r.status !== 'pending'"
            :class="r.status === 'approved' ? 'badge-approved' : 'badge-rejected'">
            {{ r.status }}
          </span>
          <template v-else>
            <button class="btn-success text-xs px-2.5 py-1" @click="approveRequest(r.id)">Approve</button>
            <button class="btn-danger text-xs px-2.5 py-1" @click="rejectRequest(r.id)">Decline</button>
          </template>
        </div>
      </div>
    </div>
  </div>

  <!-- ── Invite by Email ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Invite by Email — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Generate a personal invite link and share it via email, WhatsApp, or any channel.
      Links expire in 7 days.
    </p>

    <div class="flex gap-2 mb-3">
      <input v-model="inviteEmail" class="input" type="email"
        placeholder="player@email.com" @keyup.enter="generateInvite" />
      <button class="btn-violet shrink-0 px-4" :disabled="busy || !inviteEmail.trim()"
        @click="generateInvite">
        Generate
      </button>
    </div>

    <!-- Generated link -->
    <div v-if="inviteLink" class="rounded-xl bg-white/[0.04] border border-white/[0.08] p-3 mb-3 fade-up">
      <div class="label mb-1">Invite Link</div>
      <div class="text-xs text-slate-300 break-all font-mono mb-2.5 select-all">{{ inviteLink }}</div>
      <div class="flex gap-2">
        <button class="btn-primary flex-1 py-2 text-xs" @click="copyLink">
          📋 Copy Link
        </button>
        <a :href="mailtoLink()" class="btn-ghost flex-1 py-2 text-xs text-center">
          ✉️ Open in Email
        </a>
      </div>
    </div>

    <p v-if="inviteNote" class="text-xs rounded-xl px-3 py-2"
      :class="inviteNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ inviteNote.t }}
    </p>
  </div>

  <!-- ── Create club ── -->
  <div class="card p-4 mb-4 fade-up">
    <div class="label">Create a New Club</div>
    <div class="flex gap-2">
      <input v-model="newClub" class="input" placeholder="e.g. Kore Smashers, Court B…"
        @keyup.enter="make" maxlength="50" />
      <button class="btn-primary shrink-0 px-4" :disabled="busy || !newClub.trim()" @click="make">
        Create
      </button>
    </div>
    <p class="text-[11px] text-slate-500 mt-2">
      Each club has its own players, matches, and leaderboard. Switch between clubs using the selector at the top.
    </p>
    <p v-if="note" class="mt-2 text-xs rounded-xl px-3 py-2"
      :class="note.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ note.t }}
    </p>
  </div>

  <!-- ── Ranking weights ── -->
  <div v-if="currentClub && isManager() && cfg" class="card p-4 mb-4 fade-up">
    <div class="label">Ranking Weights — {{ currentClub.clubs?.name }}</div>
    <div class="grid grid-cols-3 gap-3 mb-3">
      <div>
        <label class="label">Skill (Elo)</label>
        <input v-model.number="cfg.elo_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Skill weight</div>
      </div>
      <div>
        <label class="label">Attendance</label>
        <input v-model.number="cfg.participation_weight" type="number" step="0.05" min="0" max="1" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Regularity weight</div>
      </div>
      <div>
        <label class="label">K-factor</label>
        <div class="input text-center text-slate-500 bg-white/[0.02] cursor-not-allowed select-none">24</div>
        <div class="text-[10px] text-slate-600 mt-1">Fixed · not editable</div>
      </div>
    </div>

    <div class="rounded-xl px-3 py-2 text-xs text-slate-400 mb-3"
      style="background:rgba(255,255,255,.03); border:1px solid rgba(255,255,255,.06)">
      Split: Skill
      <strong class="text-neon">{{ Math.round(cfg.elo_weight * 100) }}%</strong>
      + Attendance
      <strong class="text-violet">{{ Math.round(cfg.participation_weight * 100) }}%</strong>
      = {{ Math.round((cfg.elo_weight + cfg.participation_weight) * 100) }}%
      <span v-if="Math.abs(cfg.elo_weight + cfg.participation_weight - 1) > 0.01"
        class="text-amber-400"> ⚠️ must equal 100%</span>
      <span v-else class="text-neon"> ✓</span>
    </div>

    <p v-if="cfgNote" class="text-xs rounded-xl px-3 py-2 mb-3"
      :class="cfgNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ cfgNote.t }}
    </p>
    <button class="btn-ghost w-full" :disabled="busy" @click="saveCfg">Save Ranking Weights</button>
  </div>

  <!-- ── Members ── -->
  <div v-if="currentClub && members.length" class="card p-4 mb-4 fade-up">
    <div class="label">Members — {{ currentClub.clubs?.name }}</div>
    <div v-for="m in members" :key="m.user_id"
      class="flex items-center justify-between py-2.5 border-b border-white/[0.05] last:border-0 gap-2">
      <div class="flex-1 min-w-0">
        <div class="text-sm font-semibold text-slate-100 truncate">{{ m.display }}</div>
        <div class="text-[10px] text-slate-600 font-mono">{{ m.user_id.slice(0, 8) }}…</div>
      </div>
      <select
        v-if="currentClub.role === 'owner' || (currentClub.role === 'manager' && m.role !== 'owner')"
        :value="m.role"
        class="text-xs rounded-lg border border-white/10 bg-white/[0.05] px-2 py-1 outline-none cursor-pointer"
        @change="changeRole(m.user_id, $event.target.value)">
        <option value="player">🏸 Player</option>
        <option value="manager">🛠 Manager</option>
        <option v-if="currentClub.role === 'owner'" value="owner">👑 Owner</option>
      </select>
      <span v-else class="text-xs shrink-0">{{ roleLabel(m.role) }}</span>
    </div>
  </div>

  <!-- ── Facility / Location info ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">Club Location &amp; Facility — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Optional · Shown on the Explore page so new players can find your court.
    </p>
    <div class="space-y-3">
      <div>
        <label class="label">Emirates</label>
        <select v-model="facility.emirates" class="input">
          <option value="">— Select Emirates —</option>
          <option v-for="e in EMIRATES" :key="e" :value="e">{{ e }}</option>
        </select>
      </div>
      <div>
        <label class="label">Facility / Academy Name</label>
        <input v-model="facility.facility_name" class="input"
          placeholder="e.g. Dubai Sports City, GEMS School Courts" maxlength="80" />
      </div>
      <div>
        <label class="label">Address</label>
        <input v-model="facility.facility_address" class="input"
          placeholder="e.g. Al Barsha, Dubai" maxlength="120" />
      </div>
      <div>
        <label class="label">Google Maps Link <span class="text-slate-600">(optional)</span></label>
        <input v-model="facility.maps_url" class="input" type="url"
          placeholder="https://maps.app.goo.gl/…" />
      </div>
      <div>
        <label class="label">Description <span class="text-slate-600">(optional)</span></label>
        <textarea v-model="facility.description" class="input resize-none" rows="2"
          placeholder="Who can join, what time you play…" maxlength="200" />
      </div>
    </div>
    <p v-if="facNote" class="mt-3 text-xs rounded-xl px-3 py-2"
      :class="facNote.ok ? 'bg-emerald-500/15 text-emerald-300' : 'bg-rose-500/15 text-rose-300'">
      {{ facNote.t }}
    </p>
    <button class="btn-ghost w-full mt-3" :disabled="busy" @click="saveFacility">
      Save Facility Info
    </button>
  </div>

  <!-- ── Facility Master: Create or link ── -->
  <div v-if="currentClub && isManager()" class="card p-4 mb-4 fade-up">
    <div class="label">🏟️ Facility Master — {{ currentClub.clubs?.name }}</div>
    <p class="text-[11px] text-slate-500 mb-3">
      Create a facility profile that any club can link to. Once linked, matches automatically
      show as bookings on the facility's public page.
    </p>

    <!-- Linked facility status -->
    <div v-if="linkedFacility" class="flex items-center justify-between mb-3 p-3 rounded-xl"
      style="background:rgba(0,229,255,.07); border:1px solid rgba(0,229,255,.2)">
      <div>
        <div class="text-sm font-semibold text-neon">{{ linkedFacility.name }}</div>
        <div class="text-[10px] text-slate-500">{{ linkedFacility.address }}</div>
      </div>
      <div class="flex gap-2">
        <RouterLink :to="'/facility/' + linkedFacility.id"
          class="text-xs text-neon hover:opacity-75 transition">View →</RouterLink>
        <button class="text-xs text-slate-500 hover:text-rose-400 transition"
          @click="unlinkFacility">Unlink</button>
      </div>
    </div>

    <!-- Search + link existing facility -->
    <div class="mb-3">
      <label class="label">Search &amp; Link Existing Facility</label>
      <div class="flex gap-2">
        <input v-model="facSearch" class="input text-sm" placeholder="Type facility name…"
          @input="searchFacilities" />
        <button class="btn-ghost shrink-0 px-3 text-sm" @click="searchFacilities">Search</button>
      </div>
      <div v-if="facResults.length" class="mt-2 space-y-1">
        <button v-for="f in facResults" :key="f.id"
          class="w-full text-left text-sm px-3 py-2 rounded-xl border border-white/10 hover:border-cyan-500/30 hover:bg-white/[0.03] transition"
          @click="linkFacility(f)">
          <span class="font-medium text-slate-200">{{ f.name }}</span>
          <span v-if="f.address" class="text-slate-500 ml-2 text-xs">{{ f.address }}</span>
        </button>
      </div>
    </div>

    <!-- Create new facility -->
    <details class="group">
      <summary class="text-xs text-neon cursor-pointer hover:opacity-75 transition list-none flex items-center gap-1">
        <span class="group-open:rotate-90 transition-transform inline-block">▶</span>
        Create a New Facility Profile
      </summary>
      <div class="mt-3 space-y-2">
        <input v-model="newFac.name" class="input text-sm" placeholder="Facility name *" />
        <input v-model="newFac.address" class="input text-sm" placeholder="Address" />
        <select v-model="newFac.emirate" class="input text-sm">
          <option value="">— Emirates —</option>
          <option v-for="e in EMIRATES" :key="e" :value="e">{{ e }}</option>
        </select>
        <input v-model="newFac.maps_url" class="input text-sm" placeholder="Google Maps URL" />
        <input v-model="newFac.image_url" class="input text-sm" placeholder="Facility photo URL (paste image link)" />
        <input v-model="newFac.phone" class="input text-sm" placeholder="Phone" />
        <input v-model="newFac.website" class="input text-sm" placeholder="Website" />
        <textarea v-model="newFac.description" class="input resize-none text-sm" rows="2"
          placeholder="Description (courts available, parking, etc.)" />
        <p v-if="newFacNote" class="text-xs"
          :class="newFacNote.ok ? 'text-emerald-400' : 'text-rose-400'">{{ newFacNote.t }}</p>
        <button class="btn-violet w-full text-sm" :disabled="busy || !newFac.name.trim()"
          @click="createAndLinkFacility">
          🏟️ Create &amp; Link to This Club
        </button>
      </div>
    </details>
  </div>

  <!-- ── Browse / Join more clubs ── -->
  <RouterLink to="/join"
    class="card mb-4 p-4 flex items-center justify-between text-sm text-slate-400
           hover:border-white/15 transition-all duration-200 fade-up">
    <div class="flex items-center gap-3">
      <span class="text-2xl">🏟️</span>
      <div>
        <div class="font-semibold text-slate-200">Browse &amp; Join Other Clubs</div>
        <div class="text-[11px] text-slate-500">Find teams and request to join</div>
      </div>
    </div>
    <span class="text-slate-600 text-lg">→</span>
  </RouterLink>

  <!-- ── Club list ── -->
  <div v-if="clubs.length" class="card p-4 fade-up">
    <div class="label">Your Clubs</div>
    <div v-for="c in clubs" :key="c.club_id"
      class="flex items-center justify-between py-2.5 border-b border-white/[0.05] last:border-0">
      <div>
        <div class="text-sm font-semibold">{{ c.clubs?.name }}</div>
        <div class="text-[10px] text-slate-500">{{ roleLabel(c.role) }}</div>
      </div>
      <span v-if="currentClub?.club_id === c.club_id" class="badge-member">Active</span>
    </div>
  </div>
</template>
