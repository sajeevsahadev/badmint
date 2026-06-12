<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const { user } = useAuth()

const tab      = ref('users')   // users | stats | roles
const users    = ref([])
const stats    = ref(null)
const search   = ref('')
const loading  = ref(true)
const err      = ref('')
const ok       = ref('')

// Grant role panel
const grantPanel = ref(null)  // { userId, email, name }
const grantForm  = ref({ role: 'tournament_director', quota: 1, notes: '' })
const granting   = ref(false)

async function checkAdmin() {
  const { data } = await supabase.rpc('get_my_roles')
  if (!(data ?? []).some(r => r.role === 'app_admin')) {
    router.replace('/dashboard')
  }
}

async function loadUsers() {
  loading.value = true
  err.value = ''
  const { data, error } = await supabase.rpc('get_all_users', {
    p_search: search.value.trim() || null
  })
  loading.value = false
  if (error) { err.value = error.message; return }
  users.value = data ?? []
}

async function loadStats() {
  const { data, error } = await supabase.rpc('get_platform_stats')
  if (!error) stats.value = data
}

onMounted(async () => {
  await checkAdmin()
  await Promise.all([loadUsers(), loadStats()])
})

async function openGrant(u) {
  grantPanel.value = { userId: u.user_id, email: u.email, name: u.full_name || u.nickname || u.email }
  const existingDir = (u.roles ?? []).find(r => r.role === 'tournament_director')
  grantForm.value = {
    role:  'tournament_director',
    quota: existingDir?.tournament_quota ?? 1,
    notes: existingDir?.notes ?? ''
  }
}

async function grant() {
  err.value = ''; ok.value = ''; granting.value = true
  const { error } = await supabase.rpc('grant_role', {
    p_user_id:          grantPanel.value.userId,
    p_role:             grantForm.value.role,
    p_tournament_quota: grantForm.value.role === 'tournament_director'
                        ? Number(grantForm.value.quota) : null,
    p_facility_id:      null,
    p_notes:            grantForm.value.notes || null,
  })
  granting.value = false
  if (error) { err.value = error.message; return }
  ok.value = `Role granted to ${grantPanel.value.name}`
  grantPanel.value = null
  await loadUsers()
}

async function revoke(userId, role, name) {
  if (!confirm(`Remove ${role} from ${name}?`)) return
  err.value = ''; ok.value = ''
  const { error } = await supabase.rpc('revoke_role', { p_user_id: userId, p_role: role })
  if (error) { err.value = error.message; return }
  ok.value = `${role} revoked from ${name}`
  await loadUsers()
}

async function makeAdmin(u) {
  if (!confirm(`Make ${u.full_name || u.email} a super admin? This cannot be undone easily.`)) return
  err.value = ''; ok.value = ''
  const { error } = await supabase.rpc('grant_role', {
    p_user_id: u.user_id, p_role: 'app_admin',
    p_tournament_quota: null, p_facility_id: null,
    p_notes: 'Granted via admin panel'
  })
  if (error) { err.value = error.message; return }
  ok.value = 'Admin role granted'
  await loadUsers()
}

const roleChip = r => ({
  app_admin:            'badge bg-rose-50 text-rose-700 border border-rose-200',
  tournament_director:  'badge bg-violet-50 text-violet-700 border border-violet-200',
  facility_manager:     'badge bg-emerald-50 text-emerald-700 border border-emerald-200',
}[r] ?? 'badge-pending')

const roleLabel = r => ({
  app_admin: '👑 Admin', tournament_director: '🏆 Director', facility_manager: '🏢 Facility Mgr'
}[r] ?? r)

const fmtDate = d => d ? new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short', year:'numeric' }) : '—'

const filteredUsers = computed(() => users.value)

const statItems = computed(() => stats.value ? [
  { l: 'Total Users',        v: stats.value.total_users,       icon: '👥' },
  { l: 'Clubs',              v: stats.value.total_clubs,        icon: '🏸' },
  { l: 'Members',            v: stats.value.total_members,      icon: '📋' },
  { l: 'Matches Recorded',   v: stats.value.total_matches,      icon: '🎯' },
  { l: 'Tournaments',        v: stats.value.total_tournaments,  icon: '🏆' },
  { l: 'Live Now',           v: stats.value.live_tournaments,   icon: '🔴' },
  { l: 'Facilities',         v: stats.value.total_facilities,   icon: '🏢' },
  { l: 'Directors',          v: stats.value.directors,          icon: '🎖️' },
  { l: 'Matches (30d)',      v: stats.value.matches_last_30d,   icon: '📈' },
  { l: 'New Users (7d)',     v: stats.value.new_users_last_7d,  icon: '✨' },
] : [])
</script>

<template>
  <div>
    <!-- Header -->
    <div class="mb-5">
      <div class="flex items-center gap-2 mb-1">
        <span class="badge bg-rose-50 text-rose-700 border border-rose-200">👑 Super Admin</span>
      </div>
      <h1 class="font-display text-2xl font-extrabold gradient-text">Admin Panel</h1>
      <p class="text-xs text-slate-400 mt-1">Platform management — Badminton 360</p>
    </div>

    <!-- Alerts -->
    <div v-if="err" class="rounded-xl px-4 py-3 mb-3 text-sm text-rose-600 bg-rose-50 border border-rose-200">
      ⚠️ {{ err }}
    </div>
    <div v-if="ok" class="rounded-xl px-4 py-3 mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200">
      ✅ {{ ok }}
    </div>

    <!-- Tabs -->
    <div class="flex gap-1 mb-5 border border-slate-200 rounded-2xl p-1 bg-white">
      <button v-for="t in [{v:'users',l:'👥 Users'},{v:'stats',l:'📊 Stats'},{v:'roles',l:'🎖️ Roles'}]"
        :key="t.v"
        class="flex-1 py-2 text-xs font-semibold rounded-xl transition-all"
        :class="tab === t.v ? 'bg-rose-600 text-white shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="tab = t.v">
        {{ t.l }}
      </button>
    </div>

    <!-- ── USERS TAB ───────────────────────────────────────────────── -->
    <div v-if="tab === 'users'" class="space-y-3">
      <!-- Search -->
      <div class="flex gap-2">
        <input v-model="search" class="input flex-1" placeholder="Search by email, name, or nickname…"
          @keyup.enter="loadUsers" />
        <button class="btn-primary px-4" @click="loadUsers">Search</button>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="space-y-2">
        <div v-for="i in 5" :key="i" class="h-20 shimmer rounded-2xl" />
      </div>

      <!-- User list -->
      <div v-else class="space-y-2">
        <div v-for="u in filteredUsers" :key="u.user_id" class="card p-4">
          <div class="flex items-start justify-between gap-2 mb-2">
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-slate-800 text-sm truncate">
                {{ u.full_name || u.nickname || '—' }}
              </p>
              <p class="text-xs text-slate-400 truncate">{{ u.email }}</p>
              <p class="text-[10px] text-slate-300 mt-0.5">
                Joined {{ fmtDate(u.created_at) }}
                <span v-if="u.last_sign_in">· Last seen {{ fmtDate(u.last_sign_in) }}</span>
                <span v-if="u.tournaments_created > 0"> · {{ u.tournaments_created }} tournament(s)</span>
              </p>
            </div>
            <button class="shrink-0 btn-ghost text-xs px-3 py-1.5"
              @click="openGrant(u)">
              + Grant Role
            </button>
          </div>

          <!-- Current roles -->
          <div v-if="u.roles?.length" class="flex flex-wrap gap-1.5">
            <div v-for="r in u.roles" :key="r.role"
              class="flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-full border text-[11px] font-semibold"
              :class="roleChip(r.role).replace('badge ','')">
              {{ roleLabel(r.role) }}
              <span v-if="r.role === 'tournament_director' && r.tournament_quota !== null"
                class="text-[9px] opacity-70">({{ r.tournament_quota }} quota)</span>
              <button class="ml-0.5 opacity-60 hover:opacity-100 transition"
                @click="revoke(u.user_id, r.role, u.full_name || u.email)"
                title="Revoke">✕</button>
            </div>
          </div>
          <p v-else class="text-[11px] text-slate-300">No special roles</p>
        </div>

        <p v-if="!filteredUsers.length && !loading"
          class="text-center text-sm text-slate-400 py-6">
          No users found.
        </p>
      </div>
    </div>

    <!-- ── STATS TAB ───────────────────────────────────────────────── -->
    <div v-if="tab === 'stats'" class="space-y-4 fade-up">
      <div v-if="!stats" class="card p-8 text-center text-slate-400">Loading stats…</div>

      <div v-else>
        <div class="grid grid-cols-2 gap-3 mb-4">
          <div v-for="s in statItems" :key="s.l" class="card p-4">
            <p class="text-[10px] text-slate-400 uppercase tracking-widest mb-1">{{ s.l }}</p>
            <div class="flex items-center gap-2">
              <span class="text-xl">{{ s.icon }}</span>
              <span class="text-2xl font-extrabold text-neon">{{ s.v ?? 0 }}</span>
            </div>
          </div>
        </div>

        <!-- By emirate -->
        <div v-if="stats.clubs_by_emirate" class="card p-4">
          <p class="label mb-3">Clubs by Emirate</p>
          <div class="space-y-2">
            <div v-for="(count, emirate) in stats.clubs_by_emirate" :key="emirate"
              class="flex items-center gap-3">
              <span class="text-xs font-medium text-slate-600 w-28 shrink-0">{{ emirate }}</span>
              <div class="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                <div class="h-full rounded-full bg-gradient-to-r from-cyan-400 to-violet-500"
                  :style="{ width: Math.min(100, count / Math.max(...Object.values(stats.clubs_by_emirate)) * 100) + '%' }">
                </div>
              </div>
              <span class="text-xs font-bold text-slate-500 w-6 text-right shrink-0">{{ count }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── ROLES TAB ───────────────────────────────────────────────── -->
    <div v-if="tab === 'roles'" class="space-y-4 fade-up">
      <div class="card p-4">
        <h3 class="font-bold text-slate-800 mb-3">Role Permissions</h3>
        <div class="space-y-3 text-sm">
          <div class="flex gap-3 pb-3 border-b border-slate-100">
            <span class="text-xl w-8 shrink-0">👑</span>
            <div>
              <p class="font-semibold text-rose-700">App Admin</p>
              <p class="text-xs text-slate-500 mt-0.5">Full platform control. Grant/revoke roles. View all data. Unlimited tournament creation.</p>
            </div>
          </div>
          <div class="flex gap-3 pb-3 border-b border-slate-100">
            <span class="text-xl w-8 shrink-0">🏆</span>
            <div>
              <p class="font-semibold text-violet-700">Tournament Director</p>
              <p class="text-xs text-slate-500 mt-0.5">Can create tournaments up to their quota. Manages bracket, registrations, results. Default quota: 1.</p>
            </div>
          </div>
          <div class="flex gap-3">
            <span class="text-xl w-8 shrink-0">🏢</span>
            <div>
              <p class="font-semibold text-emerald-700">Facility Manager</p>
              <p class="text-xs text-slate-500 mt-0.5">Manages their linked facility: schedule, bookings, court promotions. Linked to one facility.</p>
            </div>
          </div>
        </div>
      </div>

      <div class="card-amber p-4">
        <p class="text-xs font-bold text-amber-700 mb-1">⚠️ Tournament Creation Policy</p>
        <p class="text-xs text-slate-600 leading-relaxed">
          Regular users and club managers <strong>cannot</strong> create tournaments.
          They must contact you (the admin) to request permission.
          You then either create the tournament yourself or grant them a
          <strong>tournament_director</strong> role with a quota of 1.
        </p>
      </div>

      <!-- Directors list -->
      <div class="card overflow-hidden">
        <div class="px-4 py-3 border-b border-slate-100">
          <p class="text-xs font-bold text-slate-600">Current Tournament Directors</p>
        </div>
        <div v-for="u in users.filter(u => u.roles?.some(r => r.role === 'tournament_director'))"
          :key="u.user_id"
          class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
          <div class="flex-1 min-w-0">
            <p class="text-sm font-semibold text-slate-800 truncate">{{ u.full_name || u.nickname || u.email }}</p>
            <p class="text-xs text-slate-400 truncate">{{ u.email }}</p>
          </div>
          <div class="text-right shrink-0">
            <p class="text-xs font-bold text-violet-600">
              {{ u.tournaments_created }} /
              {{ u.roles.find(r => r.role === 'tournament_director')?.tournament_quota ?? '∞' }}
            </p>
            <p class="text-[9px] text-slate-400">created / quota</p>
          </div>
        </div>
        <p v-if="!users.some(u => u.roles?.some(r => r.role === 'tournament_director'))"
          class="px-4 py-6 text-sm text-slate-400 text-center">
          No directors yet. Search for a user above and grant the role.
        </p>
      </div>
    </div>
  </div>

  <!-- ── Grant Role Modal ── -->
  <Teleport to="body">
    <div v-if="grantPanel"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5); backdrop-filter:blur(4px)"
      @click.self="grantPanel = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc; border:1px solid rgba(220,38,38,.2)">

        <div class="flex items-center justify-between mb-4">
          <div>
            <h3 class="font-display font-bold text-slate-800">Grant Role</h3>
            <p class="text-xs text-slate-400 mt-0.5 truncate">{{ grantPanel.email }}</p>
          </div>
          <button class="text-slate-400 hover:text-slate-700 text-xl" @click="grantPanel = null">✕</button>
        </div>

        <div class="space-y-4">
          <div>
            <label class="label">Role</label>
            <select v-model="grantForm.role" class="input">
              <option value="tournament_director">🏆 Tournament Director</option>
              <option value="facility_manager">🏢 Facility Manager</option>
              <option value="app_admin">👑 App Admin (caution!)</option>
            </select>
          </div>

          <div v-if="grantForm.role === 'tournament_director'">
            <label class="label">Tournament Quota</label>
            <input v-model="grantForm.quota" type="number" min="1" max="100" class="input"
              placeholder="How many tournaments can they create?" />
            <p class="text-[10px] text-slate-400 mt-1">
              Counts non-cancelled tournaments. Currently created: {{ grantPanel ? users.find(u => u.user_id === grantPanel.userId)?.tournaments_created ?? 0 : 0 }}
            </p>
          </div>

          <div>
            <label class="label">Notes (optional)</label>
            <input v-model="grantForm.notes" class="input"
              placeholder="e.g. Ramadan Cup 2026 — requested 3 Apr" />
          </div>
        </div>

        <div class="flex gap-3 mt-5">
          <button class="btn-ghost flex-1" @click="grantPanel = null">Cancel</button>
          <button class="flex-1 btn py-2.5 text-white font-bold"
            style="background:linear-gradient(135deg,#dc2626,#9f1239)"
            :disabled="granting"
            @click="grant">
            {{ granting ? 'Granting…' : 'Grant Role' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
