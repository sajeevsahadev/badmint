<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { deviceIcon, deviceName } from '../utils/formatters'

const router = useRouter()
const { user } = useAuth()

// ── Tab state ──
const tab = ref('stats')
function switchTab(t) {
  tab.value = t; err.value = ''
  if (t === 'security' && !sessions.value.length) loadSessions()
  if (t === 'blog' && !blogPosts.value.length) loadBlog()
}

// ── Blog ──
const blogPosts   = ref([])
const blogLoading = ref(false)
const blogSaving  = ref(false)
const blogMsg     = ref('')
const blankPost = () => ({ id: null, slug: '', title: '', excerpt: '', cover_url: '', body: '', meta_description: '', keywords: '', published: true, publish_at: '' })
const editingPost = ref(blankPost())

function slugify(s) {
  return (s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80)
}
// ISO → value for <input type=datetime-local> in local time
function toLocalInput(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}
const isScheduled = p => p.publish_at && new Date(p.publish_at) > new Date()
const fmtSchedule = iso => new Date(iso).toLocaleString('en', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })

async function loadBlog() {
  blogLoading.value = true
  const { data } = await supabase.from('blog_posts')
    .select('id, slug, title, excerpt, cover_url, body, meta_description, keywords, published, publish_at')
    .order('publish_at', { ascending: false })
  blogPosts.value = data ?? []
  blogLoading.value = false
}
function newPost()  { editingPost.value = blankPost(); blogMsg.value = '' }
function editPost(p) { editingPost.value = { ...p, publish_at: toLocalInput(p.publish_at) }; blogMsg.value = '' }
async function savePost() {
  const p = editingPost.value
  if (!p.title.trim() || !p.body.trim()) { blogMsg.value = 'Title and body are required.'; return }
  if (!p.slug.trim()) p.slug = slugify(p.title)
  blogSaving.value = true; blogMsg.value = ''
  const row = {
    slug: p.slug.trim(), title: p.title.trim(), excerpt: p.excerpt?.trim() || null,
    cover_url: p.cover_url?.trim() || null, body: p.body, meta_description: p.meta_description?.trim() || null,
    keywords: p.keywords?.trim() || null, published: p.published,
    publish_at: p.publish_at ? new Date(p.publish_at).toISOString() : new Date().toISOString(),
  }
  const q = p.id
    ? supabase.from('blog_posts').update(row).eq('id', p.id)
    : supabase.from('blog_posts').insert(row)
  const { error } = await q
  blogSaving.value = false
  if (error) { blogMsg.value = error.message; return }
  blogMsg.value = '✅ Saved'
  await loadBlog()
  editingPost.value = blankPost()
}
async function deletePost(p) {
  if (!confirm(`Delete "${p.title}"? This cannot be undone.`)) return
  const { error } = await supabase.from('blog_posts').delete().eq('id', p.id)
  if (error) { blogMsg.value = error.message; return }
  await loadBlog()
  if (editingPost.value.id === p.id) editingPost.value = blankPost()
}

const TABS = [
  { v: 'stats',       l: '📊 Stats' },
  { v: 'users',       l: '👥 Users' },
  { v: 'clubs',       l: '🏸 Clubs' },
  { v: 'facilities',  l: '🏢 Facilities' },
  { v: 'tournaments', l: '🏆 Tournaments' },
  { v: 'roles',       l: '🎖️ Roles' },
  { v: 'announcements', l: '📢 Announcements' },
  { v: 'security',    l: '🔐 Security' },
  { v: 'chats',       l: '💬 Chats' },
  { v: 'blog',        l: '✍️ Blog' },
]

// ── Data ──
const users       = ref([])
const clubs       = ref([])
const facilities  = ref([])
const tournaments = ref([])
const stats       = ref(null)
const sessions    = ref([])
const sessionsLoading = ref(false)
// Login-audit filtering (client-side over the loaded rows)
const sessionFilter = ref('')
const sessionActiveOnly = ref(false)
const filteredSessions = computed(() => {
  let list = sessions.value
  if (sessionActiveOnly.value) list = list.filter(s => s.is_active)
  const q = sessionFilter.value.trim().toLowerCase()
  if (!q) return list
  return list.filter(s => [
    s.full_name, s.email, s.phone, s.ip_address,
    deviceName(s.user_agent), sessionLocation(s), s.club_name,
  ].some(v => String(v || '').toLowerCase().includes(q)))
})
const chatClubId  = ref('')
const chatMessages = ref([])
const chatLoading = ref(false)
const search      = ref('')
const loading     = ref(true)
const err         = ref('')
const ok          = ref('')
let _okTimer = null
onUnmounted(() => clearTimeout(_okTimer))

function flash(msg) {
  ok.value = msg
  clearTimeout(_okTimer)
  _okTimer = setTimeout(() => { ok.value = '' }, 3000)
}

// ── Grant role modal ──
const grantPanel = ref(null)
const grantForm  = ref({ role: 'tournament_director', quota: 1, notes: '' })
const granting   = ref(false)

// ── Delete confirm modal (shared: clubs / facilities / tournaments) ──
const deleteModal = ref(null)   // { type, id, name, warning }
const deleting    = ref(false)

// ── Rename club modal ──
const renameModal = ref(null)   // { id, name }
const renaming    = ref(false)

// ── Edit facility modal ──
const editFacModal = ref(null)  // { id, name, address, emirate, courts_count }
const saving       = ref(false)

// ── Add facility modal ──
const addFacModal = ref(null)
const addingFac   = ref(false)

// ── Boot ──
async function checkAdmin() {
  const { data } = await supabase.rpc('get_my_roles')
  if (!(data ?? []).some(r => r.role === 'app_admin')) router.replace('/dashboard')
}

onMounted(async () => {
  await checkAdmin()
  loading.value = true
  await Promise.all([loadUsers(), loadStats(), loadClubs(), loadFacilities(), loadTournaments()])
  loading.value = false
})

// ── Loaders ──
async function loadUsers() {
  err.value = ''
  const { data, error } = await supabase.rpc('get_all_users', {
    p_search: search.value.trim() || null
  })
  if (error) { err.value = error.message; return }
  users.value = data ?? []
}

async function loadAdminChat() {
  if (!chatClubId.value) { chatMessages.value = []; return }
  chatLoading.value = true; err.value = ''
  const { data, error } = await supabase.rpc('get_club_messages', { p_club_id: chatClubId.value, p_limit: 100 })
  chatLoading.value = false
  if (error) { err.value = error.message; return }
  chatMessages.value = data ?? []
}

async function loadSessions() {
  sessionsLoading.value = true; err.value = ''
  const { data, error } = await supabase.rpc('admin_get_sessions', { p_limit: 300 })
  sessionsLoading.value = false
  if (error) { err.value = error.message; return }
  sessions.value = data ?? []
}

async function loadStats() {
  const { data } = await supabase.rpc('get_platform_stats')
  if (data) stats.value = data
}

async function loadClubs() {
  const { data, error } = await supabase.rpc('admin_get_clubs')
  if (!error) clubs.value = data ?? []
}

async function loadFacilities() {
  const { data, error } = await supabase.rpc('admin_get_facilities')
  if (error) { err.value = error.message; return }
  facilities.value = data ?? []
}

async function loadTournaments() {
  const { data, error } = await supabase.rpc('admin_get_tournaments')
  if (!error) tournaments.value = data ?? []
}

// ── Grant / revoke roles ──
function openGrant(u) {
  grantPanel.value = {
    userId: u.user_id,
    email:  u.email,
    name:   u.full_name || u.nickname || u.email,
  }
  const existingDir = (u.roles ?? []).find(r => r.role === 'tournament_director')
  grantForm.value = {
    role:  'tournament_director',
    quota: existingDir?.tournament_quota ?? 1,
    notes: existingDir?.notes ?? '',
  }
}

async function grant() {
  err.value = ''; granting.value = true
  const { error } = await supabase.rpc('grant_role', {
    p_user_id:          grantPanel.value.userId,
    p_role:             grantForm.value.role,
    p_tournament_quota: grantForm.value.role === 'tournament_director' ? Number(grantForm.value.quota) : null,
    p_facility_id:      null,
    p_notes:            grantForm.value.notes || null,
  })
  granting.value = false
  if (error) { err.value = error.message; return }
  flash(`Role granted to ${grantPanel.value.name}`)
  grantPanel.value = null
  await loadUsers()
}

async function revoke(userId, role, name) {
  if (!confirm(`Remove ${role} from ${name}?`)) return
  err.value = ''
  const { error } = await supabase.rpc('revoke_role', { p_user_id: userId, p_role: role })
  if (error) { err.value = error.message; return }
  flash(`${role} revoked from ${name}`)
  await loadUsers()
}

// ── Club actions ──
function openRename(c) {
  renameModal.value = { id: c.club_id, name: c.name }
}

async function saveRename() {
  if (!renameModal.value.name.trim()) return
  renaming.value = true
  const { error } = await supabase.rpc('admin_rename_club', {
    p_club_id: renameModal.value.id,
    p_name:    renameModal.value.name.trim(),
  })
  renaming.value = false
  if (error) { err.value = error.message; return }
  flash('Club renamed')
  renameModal.value = null
  await loadClubs()
}

// ── Facility actions ──
function openEditFacility(f) {
  editFacModal.value = {
    id:           f.id,
    name:         f.name,
    address:      f.address ?? '',
    emirate:      f.emirate ?? '',
    courts_count: f.courts_count ?? '',
    image_url:    f.image_url ?? '',
  }
}

async function saveEditFacility() {
  if (!editFacModal.value.name.trim()) return
  saving.value = true
  const { error } = await supabase.rpc('admin_update_facility', {
    p_id:           editFacModal.value.id,
    p_name:         editFacModal.value.name.trim(),
    p_address:      editFacModal.value.address  || null,
    p_emirate:      editFacModal.value.emirate  || null,
    p_courts_count: editFacModal.value.courts_count ? Number(editFacModal.value.courts_count) : null,
    p_image_url:    editFacModal.value.image_url || null,
  })
  saving.value = false
  if (error) { err.value = error.message; return }
  flash('Facility updated')
  editFacModal.value = null
  await loadFacilities()
}

function openAddFacility() {
  addFacModal.value = { name: '', address: '', emirate: '', courts_count: '', image_url: '' }
}

async function saveAddFacility() {
  if (!addFacModal.value.name.trim()) return
  addingFac.value = true
  const { error } = await supabase.rpc('admin_create_facility', {
    p_name:         addFacModal.value.name.trim(),
    p_address:      addFacModal.value.address     || null,
    p_emirate:      addFacModal.value.emirate     || null,
    p_courts_count: addFacModal.value.courts_count ? Number(addFacModal.value.courts_count) : null,
    p_image_url:    addFacModal.value.image_url   || null,
  })
  addingFac.value = false
  if (error) { err.value = error.message; return }
  flash('Facility created')
  addFacModal.value = null
  await Promise.all([loadFacilities(), loadStats()])
}

// ── Shared delete (clubs / facilities / tournaments) ──
function openDelete(type, id, name, warning) {
  deleteModal.value = { type, id, name, warning }
}

async function confirmDelete() {
  deleting.value = true; err.value = ''
  const { type, id } = deleteModal.value
  let error
  if (type === 'club')       ({ error } = await supabase.rpc('admin_delete_club',       { p_club_id:       id }))
  if (type === 'facility')   ({ error } = await supabase.rpc('admin_delete_facility',   { p_id:            id }))
  if (type === 'tournament') ({ error } = await supabase.rpc('delete_tournament',       { p_tournament_id: id }))
  deleting.value = false
  if (error) { err.value = error.message; deleteModal.value = null; return }
  flash(`${deleteModal.value.name} deleted`)
  const name = deleteModal.value.name
  deleteModal.value = null
  if (type === 'club')       await Promise.all([loadClubs(), loadStats()])
  if (type === 'facility')   await Promise.all([loadFacilities(), loadStats()])
  if (type === 'tournament') await Promise.all([loadTournaments(), loadStats()])
}


// ── Announcements ──
const annSubject  = ref('')
const annBody     = ref('')
const annSending  = ref(false)
const annSuccess  = ref('')   // "Sent to N members"
const annErr      = ref('')

async function sendAnnouncement() {
  if (!annSubject.value.trim() || !annBody.value.trim()) return
  annSending.value = true; annSuccess.value = ''; annErr.value = ''
  const { data, error } = await supabase.functions.invoke('send-announcement', {
    body: { subject: annSubject.value.trim(), body: annBody.value.trim() }
  })
  annSending.value = false
  if (error) { annErr.value = error.message || 'Failed to send announcement'; return }
  annSuccess.value = data?.sent_count != null ? `Sent to ${data.sent_count} members` : 'Announcement sent'
  annSubject.value = ''
  annBody.value = ''
}

const roleChip = r => ({
  app_admin:           'bg-rose-50 text-rose-700 border-rose-200',
  tournament_director: 'bg-violet-50 text-violet-700 border-violet-200',
  facility_manager:    'bg-emerald-50 text-emerald-700 border-emerald-200',
}[r] ?? 'bg-slate-100 text-slate-500 border-slate-200')

const roleLabel = r => ({
  app_admin: '👑 Admin', tournament_director: '🏆 Director', facility_manager: '🏢 Facility Mgr',
}[r] ?? r)

const statusChip = s => ({
  draft:             'bg-slate-100 text-slate-500',
  registration_open: 'bg-emerald-50 text-emerald-700',
  live:              'bg-rose-50 text-rose-700',
  completed:         'bg-slate-100 text-slate-600',
  cancelled:         'bg-slate-50 text-slate-400',
}[s] ?? 'bg-slate-100 text-slate-500')

const fmtDate  = d => d ? new Date(d).toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' }) : '—'
const fmtDateTime = d => d ? new Date(d).toLocaleString('en-AE', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
const sessionLocation = s => [s.city, s.region, s.country].filter(Boolean).join(', ') || '—'
const fmtShort = d => d ? new Date(d).toLocaleDateString('en-AE', { day: 'numeric', month: 'short' }) : '—'

const statItems = computed(() => !stats.value ? [] : [
  { l: 'Total Users',      v: stats.value.total_users,       icon: '👥', tab: 'users' },
  { l: 'Clubs',            v: stats.value.total_clubs,        icon: '🏸', tab: 'clubs' },
  { l: 'Members',          v: stats.value.total_members,      icon: '📋', tab: 'clubs' },
  { l: 'Matches Recorded', v: stats.value.total_matches,      icon: '🎯', tab: null },
  { l: 'Tournaments',      v: stats.value.total_tournaments,  icon: '🏆', tab: 'tournaments' },
  { l: 'Live Now',         v: stats.value.live_tournaments,   icon: '🔴', tab: 'tournaments' },
  { l: 'Facilities',       v: stats.value.total_facilities,   icon: '🏢', tab: 'facilities' },
  { l: 'Directors',        v: stats.value.directors,          icon: '🎖️', tab: 'roles' },
  { l: 'Matches (30d)',    v: stats.value.matches_last_30d,   icon: '📈', tab: null },
  { l: 'New Users (7d)',   v: stats.value.new_users_last_7d,  icon: '✨', tab: 'users' },
])
</script>

<template>
  <div>
    <!-- Header -->
    <div class="mb-5">
      <div class="flex items-center gap-2 mb-1">
        <span class="badge bg-rose-50 text-rose-700 border border-rose-200">👑 Super Admin</span>
      </div>
      <h1 class="font-display text-2xl font-extrabold gradient-text">Admin Panel</h1>
      <p class="text-xs text-slate-400 mt-1">Platform management · Badminton 360</p>
    </div>

    <!-- Alerts -->
    <div v-if="err" class="rounded-xl px-4 py-3 mb-3 text-sm text-rose-600 bg-rose-50 border border-rose-200">⚠️ {{ err }}</div>
    <div v-if="ok"  class="rounded-xl px-4 py-3 mb-3 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200">✅ {{ ok }}</div>

    <!-- Tab bar — wraps to multiple rows so it scales as features grow
         (no horizontal scrolling). -->
    <div class="flex flex-wrap gap-1.5 mb-5">
      <button v-for="t in TABS" :key="t.v"
        class="px-3 py-1.5 text-xs font-semibold rounded-full transition-all border"
        :class="tab === t.v
          ? 'bg-rose-600 text-white border-rose-600 shadow-sm'
          : 'bg-white text-slate-500 border-slate-200 hover:text-slate-700 hover:border-slate-300'"
        @click="switchTab(t.v)">
        {{ t.l }}
      </button>
    </div>

    <!-- Global loading shimmer -->
    <div v-if="loading" class="space-y-2">
      <div v-for="i in 6" :key="i" class="h-20 shimmer rounded-2xl" />
    </div>

    <template v-else>

      <!-- ── STATS ─────────────────────────────────────────────────────── -->
      <div v-if="tab === 'stats'" class="space-y-4 fade-up">
        <div v-if="!stats" class="card p-8 text-center text-slate-400">Loading stats…</div>
        <template v-else>
          <div class="grid grid-cols-2 gap-3">
            <div v-for="s in statItems" :key="s.l" class="card p-4 transition-all"
              :class="s.tab ? 'cursor-pointer hover:ring-1 hover:ring-cyan-400/40 active:scale-[0.98]' : ''"
              @click="s.tab && switchTab(s.tab)">
              <p class="text-[10px] text-slate-400 uppercase tracking-widest mb-1">{{ s.l }}</p>
              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-2">
                  <span class="text-xl">{{ s.icon }}</span>
                  <span class="text-2xl font-extrabold text-neon">{{ s.v ?? 0 }}</span>
                </div>
                <span v-if="s.tab" class="text-[10px] text-slate-500">›</span>
              </div>
            </div>
          </div>
          <div v-if="stats.clubs_by_emirate" class="card p-4">
            <p class="label mb-3">Clubs by Region</p>
            <div class="space-y-2">
              <div v-for="(count, emirate) in stats.clubs_by_emirate" :key="emirate"
                class="flex items-center gap-3">
                <span class="text-xs text-slate-600 w-28 shrink-0 truncate">{{ emirate || 'Unknown' }}</span>
                <div class="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                  <div class="h-full rounded-full bg-gradient-to-r from-cyan-400 to-violet-500"
                    :style="{ width: Math.min(100, count / Math.max(...Object.values(stats.clubs_by_emirate)) * 100) + '%' }" />
                </div>
                <span class="text-xs font-bold text-slate-500 w-5 text-right shrink-0">{{ count }}</span>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- ── USERS ─────────────────────────────────────────────────────── -->
      <div v-if="tab === 'users'" class="space-y-3 fade-up">
        <div class="flex gap-2">
          <input v-model="search" class="input flex-1" placeholder="Search by email, name, or nickname…"
            @keyup.enter="loadUsers" />
          <button class="btn-primary px-4" @click="loadUsers">Search</button>
        </div>
        <div class="space-y-2">
          <div v-for="u in users" :key="u.user_id" class="card p-4">
            <div class="flex items-start justify-between gap-2 mb-2">
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-slate-800 text-sm truncate">{{ u.full_name || u.nickname || '—' }}</p>
                <p class="text-xs text-slate-400 truncate">{{ u.email }}</p>
                <p class="text-[10px] text-slate-300 mt-0.5">
                  Joined {{ fmtDate(u.created_at) }}
                  <span v-if="u.last_sign_in"> · Last {{ fmtDate(u.last_sign_in) }}</span>
                  <span v-if="u.tournaments_created > 0"> · {{ u.tournaments_created }} tournament(s)</span>
                </p>
                <p v-if="u.login_count > 0 || u.last_ip" class="text-[10px] text-slate-400 mt-0.5">
                  <span v-if="u.login_count">{{ u.login_count }} session(s)</span>
                  <span v-if="u.last_ip" class="font-mono"> · {{ deviceIcon(u.last_user_agent) }} {{ u.last_ip }}</span>
                </p>
              </div>
              <button class="shrink-0 btn-ghost text-xs px-3 py-1.5" @click="openGrant(u)">+ Role</button>
            </div>
            <div v-if="u.roles?.length" class="flex flex-wrap gap-1.5">
              <div v-for="r in u.roles" :key="r.role"
                class="flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-full border text-[11px] font-semibold"
                :class="roleChip(r.role)">
                {{ roleLabel(r.role) }}
                <span v-if="r.role === 'tournament_director' && r.tournament_quota !== null"
                  class="text-[9px] opacity-70">({{ r.tournament_quota }})</span>
                <button class="ml-0.5 opacity-60 hover:opacity-100 transition"
                  @click="revoke(u.user_id, r.role, u.full_name || u.email)" title="Revoke">✕</button>
              </div>
            </div>
            <p v-else class="text-[11px] text-slate-300">No special roles</p>
          </div>
          <p v-if="!users.length" class="text-center text-sm text-slate-400 py-6">No users found.</p>
        </div>
      </div>

      <!-- ── CLUBS ─────────────────────────────────────────────────────── -->
      <div v-if="tab === 'clubs'" class="space-y-3 fade-up">
        <p class="text-xs text-slate-400">{{ clubs.length }} clubs on platform</p>
        <div class="space-y-2">
          <div v-for="c in clubs" :key="c.club_id" class="card p-4">
            <div class="flex items-start gap-2">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span v-if="c.club_rank" class="text-xs font-bold text-gold shrink-0">#{{ c.club_rank }}</span>
                  <p class="font-semibold text-slate-800 text-sm truncate">{{ c.name }}</p>
                </div>
                <p class="text-xs text-slate-400 truncate mt-0.5">
                  {{ c.owner_name || c.owner_email || 'Unknown owner' }}
                  <span v-if="c.owner_email" class="text-slate-300"> · {{ c.owner_email }}</span>
                </p>
                <div class="flex items-center gap-3 mt-1 flex-wrap">
                  <span class="text-[10px] text-slate-400">👥 {{ c.member_count }}</span>
                  <span class="text-[10px] text-slate-400">🎯 {{ c.matches_30d }}/mo</span>
                  <span class="text-[10px] text-slate-400">📅 {{ fmtShort(c.created_at) }}</span>
                </div>
              </div>
              <div class="flex items-center gap-1.5 shrink-0 ml-auto">
                <RouterLink :to="'/club/' + c.club_id + '?admin=1'"
                  class="text-xs border border-slate-200 text-slate-500 hover:text-neon hover:border-cyan-400/40 transition rounded-lg px-3 py-2 min-h-[36px] flex items-center"
                  title="View club">👁</RouterLink>
                <button class="text-xs border border-slate-200 text-slate-500 hover:text-neon hover:border-cyan-400/40 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="Rename" @click="openRename(c)">✏️</button>
                <button class="text-xs border border-slate-200 text-slate-400 hover:text-rose-500 hover:border-rose-300 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="Delete"
                  @click="openDelete('club', c.club_id, c.name, 'Permanently deletes ALL matches, Elo history, and player data for this club. Cannot be undone.')">
                  🗑
                </button>
              </div>
            </div>
          </div>
          <p v-if="!clubs.length" class="text-center text-sm text-slate-400 py-6">No clubs yet.</p>
        </div>
      </div>

      <!-- ── FACILITIES ─────────────────────────────────────────────────── -->
      <div v-if="tab === 'facilities'" class="space-y-3 fade-up">
        <div class="flex items-center justify-between">
          <p class="text-xs text-slate-400">{{ facilities.length }} facilities on platform</p>
          <button class="btn-primary text-xs px-3 py-1.5 min-h-[36px]" @click="openAddFacility">+ Add Facility</button>
        </div>
        <div class="space-y-2">
          <div v-for="f in facilities" :key="f.id" class="card p-4">
            <div class="flex items-start gap-2">
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-slate-800 text-sm truncate">{{ f.name }}</p>
                <p class="text-xs text-slate-400 mt-0.5 truncate">
                  <span v-if="f.emirate">{{ f.emirate }}</span>
                  <span v-if="f.address" class="text-slate-300"> · {{ f.address }}</span>
                </p>
                <div class="flex items-center gap-3 mt-1 flex-wrap">
                  <span v-if="f.courts_count" class="text-[10px] text-slate-400">🏟 {{ f.courts_count }} courts</span>
                  <span class="text-[10px] text-slate-400">🏸 {{ f.clubs_count }} club(s) linked</span>
                  <span class="text-[10px] text-slate-400">📅 {{ fmtShort(f.created_at) }}</span>
                </div>
                <p v-if="f.creator_email" class="text-[10px] text-slate-300 mt-0.5">by {{ f.creator_email }}</p>
              </div>
              <div class="flex items-center gap-1.5 shrink-0 ml-auto">
                <button class="text-xs border border-slate-200 text-slate-500 hover:text-neon hover:border-cyan-400/40 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="Edit" @click="openEditFacility(f)">✏️</button>
                <button class="text-xs border border-slate-200 text-slate-400 hover:text-rose-500 hover:border-rose-300 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="Delete"
                  @click="openDelete('facility', f.id, f.name, 'Unlinks all clubs, removes all schedule slots and booking history. Cannot be undone.')">
                  🗑
                </button>
              </div>
            </div>
          </div>
          <p v-if="!facilities.length" class="text-center text-sm text-slate-400 py-6">No facilities yet.</p>
        </div>
      </div>

      <!-- ── TOURNAMENTS ────────────────────────────────────────────────── -->
      <div v-if="tab === 'tournaments'" class="space-y-3 fade-up">
        <p class="text-xs text-slate-400">{{ tournaments.length }} tournaments total</p>
        <div class="space-y-2">
          <div v-for="t in tournaments" :key="t.id" class="card p-4">
            <div class="flex items-start gap-2">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <p class="font-semibold text-slate-800 text-sm">{{ t.name }}</p>
                  <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full" :class="statusChip(t.status)">
                    {{ t.status.replace('_', ' ') }}
                  </span>
                </div>
                <p class="text-xs text-slate-400 truncate mt-0.5">
                  {{ t.club_name || 'No club' }}
                  <span class="text-slate-300"> · {{ t.format === 'single_elimination' ? 'Knock-out' : 'Round Robin' }}</span>
                </p>
                <div class="flex items-center gap-3 mt-1 flex-wrap">
                  <span class="text-[10px] text-slate-400">🏅 {{ t.registration_count }}/{{ t.max_teams }} teams</span>
                  <span v-if="t.start_date" class="text-[10px] text-slate-400">📅 {{ fmtShort(t.start_date) }}</span>
                </div>
                <p v-if="t.creator_email" class="text-[10px] text-slate-300 mt-0.5">by {{ t.creator_email }}</p>
              </div>
              <div class="flex items-center gap-1.5 shrink-0 ml-auto">
                <RouterLink :to="'/tournament/' + t.id"
                  class="text-xs border border-slate-200 text-slate-500 hover:text-neon hover:border-cyan-400/40 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="View">👁</RouterLink>
                <button class="text-xs border border-slate-200 text-slate-400 hover:text-rose-500 hover:border-rose-300 transition rounded-lg px-3 py-2 min-h-[36px]"
                  title="Delete"
                  @click="openDelete('tournament', t.id, t.name, 'Deletes all registrations, bracket matches, and results. Cannot be undone.')">
                  🗑
                </button>
              </div>
            </div>
          </div>
          <p v-if="!tournaments.length" class="text-center text-sm text-slate-400 py-6">No tournaments yet.</p>
        </div>
      </div>

      <!-- ── ANNOUNCEMENTS ────────────────────────────────────────────── -->
      <div v-if="tab === 'announcements'" class="space-y-4 fade-up">
        <div class="card p-4">
          <h3 class="font-bold text-slate-800 mb-4">Send Announcement</h3>
          <div v-if="annSuccess" class="rounded-xl px-4 py-3 mb-4 text-sm text-emerald-700 bg-emerald-50 border border-emerald-200">✅ {{ annSuccess }}</div>
          <div v-if="annErr"     class="rounded-xl px-4 py-3 mb-4 text-sm text-rose-600   bg-rose-50   border border-rose-200">⚠️ {{ annErr }}</div>
          <div class="space-y-3">
            <div>
              <label class="label">Subject <span class="text-rose-400">*</span></label>
              <input v-model="annSubject" class="input" maxlength="150"
                placeholder="e.g. New tournament this weekend!" />
            </div>
            <div>
              <label class="label">Message <span class="text-rose-400">*</span></label>
              <textarea v-model="annBody" class="input resize-none" rows="5"
                placeholder="Write your announcement…" />
            </div>
            <p class="text-[11px] text-slate-400">Will be sent to all members with announcements enabled in their email settings.</p>
          </div>
          <button class="btn-primary w-full mt-4"
            :disabled="annSending || !annSubject.trim() || !annBody.trim()"
            @click="sendAnnouncement">
            <span v-if="annSending" class="inline-flex items-center gap-2">
              <svg class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"/>
              </svg>
              Sending…
            </span>
            <span v-else>📢 Send Announcement</span>
          </button>
        </div>
      </div>

      <!-- ── ROLES ─────────────────────────────────────────────────────── -->
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
            Grant a <strong>Tournament Director</strong> role with a quota of 1, or create it yourself.
          </p>
        </div>

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
                {{ u.tournaments_created }} / {{ u.roles.find(r => r.role === 'tournament_director')?.tournament_quota ?? '∞' }}
              </p>
              <p class="text-[9px] text-slate-400">created / quota</p>
            </div>
          </div>
          <p v-if="!users.some(u => u.roles?.some(r => r.role === 'tournament_director'))"
            class="px-4 py-6 text-sm text-slate-400 text-center">
            No directors yet.
          </p>
        </div>
      </div>

      <!-- ── Security / Login Audit ─────────────────────────────────── -->
      <div v-if="tab === 'security'" class="space-y-3 fade-up">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-sm font-bold text-slate-800">Login Audit</p>
            <p class="text-[11px] text-slate-500">
              Newest first ·
              <template v-if="sessionFilter.trim() || sessionActiveOnly">{{ filteredSessions.length }} of {{ sessions.length }}</template>
              <template v-else>{{ sessions.length }}</template>
              logins
            </p>
          </div>
          <button class="btn-ghost text-xs px-3 py-1.5" :disabled="sessionsLoading" @click="loadSessions">
            {{ sessionsLoading ? '…' : '↻ Refresh' }}
          </button>
        </div>

        <!-- Filter bar -->
        <div v-if="sessions.length" class="flex flex-wrap items-center gap-2">
          <div class="relative flex-1 min-w-[180px]">
            <span class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm">🔍</span>
            <input v-model="sessionFilter" placeholder="Filter by name, email, phone, IP, device, location…"
              class="w-full rounded-xl border border-slate-200 bg-white pl-9 pr-8 py-2 text-xs text-slate-700 outline-none focus:border-cyan-400" />
            <button v-if="sessionFilter" class="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
              @click="sessionFilter = ''">✕</button>
          </div>
          <label class="flex items-center gap-1.5 text-xs text-slate-600 cursor-pointer select-none whitespace-nowrap">
            <input type="checkbox" v-model="sessionActiveOnly" class="w-3.5 h-3.5 rounded accent-emerald-500" />
            Active only
          </label>
        </div>

        <div v-if="sessionsLoading" class="card p-8 text-center text-sm text-slate-400">Loading logins…</div>
        <div v-else-if="!sessions.length" class="card p-8 text-center text-sm text-slate-400">No logins recorded yet.</div>
        <div v-else-if="!filteredSessions.length" class="card p-8 text-center text-sm text-slate-400">
          No logins match “{{ sessionFilter }}”.
        </div>

        <div v-else class="card overflow-x-auto">
          <table class="w-full text-xs min-w-[720px]">
            <thead>
              <tr class="text-left text-slate-500 border-b border-slate-100">
                <th class="py-2.5 px-3 font-semibold">User</th>
                <th class="py-2.5 px-3 font-semibold">Contact</th>
                <th class="py-2.5 px-3 font-semibold">IP address</th>
                <th class="py-2.5 px-3 font-semibold">Device</th>
                <th class="py-2.5 px-3 font-semibold">Location</th>
                <th class="py-2.5 px-3 font-semibold">Club</th>
                <th class="py-2.5 px-3 font-semibold text-right">Logged in</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="s in filteredSessions" :key="s.session_id" class="border-b border-slate-50 last:border-0 align-top">
                <td class="py-2.5 px-3">
                  <div class="font-semibold text-slate-800 whitespace-nowrap">{{ s.full_name || '—' }}</div>
                  <span v-if="s.is_active" class="inline-block mt-0.5 text-[9px] font-bold text-emerald-600">● active</span>
                </td>
                <td class="py-2.5 px-3">
                  <div class="text-slate-600 truncate max-w-[180px]">{{ s.email || '—' }}</div>
                  <div class="text-slate-400">{{ s.phone || '—' }}</div>
                </td>
                <td class="py-2.5 px-3 font-mono text-slate-700 whitespace-nowrap">{{ s.ip_address || '—' }}</td>
                <td class="py-2.5 px-3 whitespace-nowrap">
                  <span class="mr-1">{{ deviceIcon(s.user_agent) }}</span>{{ deviceName(s.user_agent) }}
                </td>
                <td class="py-2.5 px-3 text-slate-600">{{ sessionLocation(s) }}</td>
                <td class="py-2.5 px-3 text-slate-600 whitespace-nowrap">{{ s.club_name || '—' }}</td>
                <td class="py-2.5 px-3 text-right text-slate-500 whitespace-nowrap">{{ fmtDateTime(s.logged_in_at) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-[10px] text-slate-400 px-1">
          IP location is approximate (from the device's network at login) and for security review only.
        </p>
      </div>

      <!-- ── Club Chats (read-only oversight) ──────────────────────────── -->
      <div v-if="tab === 'chats'" class="space-y-3 fade-up">
        <div class="card p-4">
          <label class="label">Club</label>
          <select v-model="chatClubId" class="input" @change="loadAdminChat">
            <option value="">— Select a club —</option>
            <option v-for="c in clubs" :key="c.club_id" :value="c.club_id">{{ c.name }}</option>
          </select>
          <p class="text-[11px] text-slate-500 mt-2">Read-only view of a club's chat, for moderation and safety.</p>
        </div>

        <div v-if="chatLoading" class="card p-8 text-center text-sm text-slate-400">Loading messages…</div>
        <div v-else-if="chatClubId && !chatMessages.length" class="card p-8 text-center text-sm text-slate-400">No messages in this club yet.</div>

        <div v-else-if="chatMessages.length" class="card p-3 space-y-2 max-h-[60vh] overflow-y-auto">
          <div v-for="m in chatMessages" :key="m.id" class="flex items-start gap-2">
            <div class="w-8 h-8 rounded-full bg-slate-100 flex items-center justify-center text-xs font-bold text-slate-500 shrink-0">
              {{ (m.sender_name || '?').charAt(0).toUpperCase() }}
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-xs font-semibold text-slate-700">
                {{ m.sender_name }}
                <span class="text-[10px] font-normal text-slate-400 ml-1">{{ fmtDateTime(m.created_at) }}</span>
              </p>
              <p class="text-sm text-slate-600 break-words whitespace-pre-wrap">{{ m.body }}</p>
            </div>
          </div>
        </div>
      </div>

      <!-- ══════════════ BLOG ══════════════ -->
      <div v-if="tab === 'blog'" class="space-y-4 fade-up">
        <div class="flex items-center justify-between">
          <p class="text-sm text-slate-500">Write posts for <RouterLink to="/blog" class="text-neon font-semibold">/blog</RouterLink> (public + SEO).</p>
          <button class="btn-primary text-xs px-3 py-1.5" @click="newPost">＋ New post</button>
        </div>

        <!-- Editor -->
        <div class="card p-4 space-y-3">
          <p class="font-bold text-slate-700 text-sm">{{ editingPost.id ? 'Edit post' : 'New post' }}</p>
          <div>
            <label class="label">Title</label>
            <input v-model="editingPost.title" class="input" placeholder="How to…"
              @blur="!editingPost.slug && (editingPost.slug = slugify(editingPost.title))" />
          </div>
          <div class="grid sm:grid-cols-2 gap-3">
            <div>
              <label class="label">Slug (URL)</label>
              <input v-model="editingPost.slug" class="input" placeholder="how-to-track-matches" />
            </div>
            <div>
              <label class="label">Cover image URL</label>
              <input v-model="editingPost.cover_url" class="input" placeholder="https://…/cover.png" />
            </div>
          </div>
          <div>
            <label class="label">Excerpt (short summary)</label>
            <input v-model="editingPost.excerpt" class="input" maxlength="200" placeholder="One-line teaser shown on cards" />
          </div>
          <div class="grid sm:grid-cols-2 gap-3">
            <div>
              <label class="label">Meta description (SEO, ~155 chars)</label>
              <input v-model="editingPost.meta_description" class="input" maxlength="170" />
            </div>
            <div>
              <label class="label">Keywords (comma-separated)</label>
              <input v-model="editingPost.keywords" class="input" placeholder="badminton, score tracking, …" />
            </div>
          </div>
          <div>
            <label class="label">Body (HTML — use &lt;h2&gt;, &lt;p&gt;, &lt;ul&gt;&lt;li&gt;, &lt;strong&gt;, &lt;a&gt;)</label>
            <textarea v-model="editingPost.body" rows="10" class="input font-mono text-xs" placeholder="<p>Your article…</p>"></textarea>
          </div>
          <div class="grid sm:grid-cols-2 gap-3">
            <div>
              <label class="label">Publish date &amp; time (leave empty = now)</label>
              <input v-model="editingPost.publish_at" type="datetime-local" class="input" />
              <p class="text-[11px] text-slate-400 mt-1">A future time schedules the post — it stays hidden until then.</p>
            </div>
            <label class="flex items-end gap-2 text-sm text-slate-600 pb-2">
              <input type="checkbox" v-model="editingPost.published" /> Published (uncheck = draft)
            </label>
          </div>
          <div class="flex items-center gap-3">
            <button class="btn-primary px-5 py-2 text-sm" :disabled="blogSaving" @click="savePost">
              {{ blogSaving ? 'Saving…' : (editingPost.id ? 'Update post' : 'Publish post') }}
            </button>
            <button v-if="editingPost.id" class="btn-ghost px-4 py-2 text-sm" @click="newPost">Cancel</button>
            <span v-if="blogMsg" class="text-xs" :class="blogMsg.startsWith('✅') ? 'text-emerald-600' : 'text-rose-500'">{{ blogMsg }}</span>
          </div>
        </div>

        <!-- Existing posts -->
        <div v-if="blogLoading" class="card p-6 text-center text-sm text-slate-400">Loading…</div>
        <div v-else-if="!blogPosts.length" class="card p-6 text-center text-sm text-slate-400">No posts yet.</div>
        <div v-else class="space-y-2">
          <div v-for="p in blogPosts" :key="p.id" class="card p-3 flex items-center gap-3">
            <img v-if="p.cover_url" :src="p.cover_url" alt="" class="w-14 h-10 rounded object-cover shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-semibold text-slate-700 truncate">{{ p.title }}</p>
              <p class="text-[11px]" :class="isScheduled(p) ? 'text-amber-600 font-semibold' : 'text-slate-400'">
                /blog/{{ p.slug }} ·
                <template v-if="!p.published">Draft</template>
                <template v-else-if="isScheduled(p)">⏱ Scheduled {{ fmtSchedule(p.publish_at) }}</template>
                <template v-else>Live</template>
              </p>
            </div>
            <button class="btn-ghost text-xs px-2 py-1" @click="editPost(p)">Edit</button>
            <button class="text-xs px-2 py-1 text-rose-500 hover:bg-rose-50 rounded" @click="deletePost(p)">Delete</button>
          </div>
        </div>
      </div>

    </template>
  </div>

  <!-- ── Modals ─────────────────────────────────────────────────────── -->
  <Teleport to="body">

    <!-- Grant Role Modal -->
    <div v-if="grantPanel"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5);backdrop-filter:blur(4px)"
      @click.self="grantPanel = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc;border:1px solid rgba(220,38,38,.2)">
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
              Currently created: {{ users.find(u => u.user_id === grantPanel.userId)?.tournaments_created ?? 0 }}
            </p>
          </div>
          <div>
            <label class="label">Notes (optional)</label>
            <input v-model="grantForm.notes" class="input" placeholder="e.g. Ramadan Cup 2026 request" />
          </div>
        </div>
        <div class="flex gap-3 mt-5">
          <button class="btn-ghost flex-1" @click="grantPanel = null">Cancel</button>
          <button class="flex-1 py-2.5 rounded-xl text-white font-bold transition"
            style="background:linear-gradient(135deg,#dc2626,#9f1239)"
            :disabled="granting" @click="grant">
            {{ granting ? 'Granting…' : 'Grant Role' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Delete Confirm Modal -->
    <div v-if="deleteModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5);backdrop-filter:blur(4px)"
      @click.self="deleteModal = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc;border:1px solid rgba(220,38,38,.2)">
        <div class="text-center mb-5">
          <div class="text-4xl mb-3">🗑️</div>
          <h3 class="font-display font-bold text-slate-800 text-lg capitalize">Delete {{ deleteModal.type }}?</h3>
          <p class="text-sm font-semibold text-rose-600 mt-1">{{ deleteModal.name }}</p>
          <p class="text-xs text-slate-500 mt-2 leading-relaxed">{{ deleteModal.warning }}</p>
        </div>
        <div class="flex gap-3">
          <button class="btn-ghost flex-1" @click="deleteModal = null">Cancel</button>
          <button class="flex-1 py-2.5 rounded-xl text-white font-bold transition"
            style="background:linear-gradient(135deg,#dc2626,#9f1239)"
            :disabled="deleting" @click="confirmDelete">
            {{ deleting ? 'Deleting…' : 'Yes, Delete' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Rename Club Modal -->
    <div v-if="renameModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5);backdrop-filter:blur(4px)"
      @click.self="renameModal = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc;border:1px solid rgba(0,229,255,.2)">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-display font-bold text-slate-800">Rename Club</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl" @click="renameModal = null">✕</button>
        </div>
        <input v-model="renameModal.name" class="input mb-4" maxlength="50"
          placeholder="New club name" @keyup.enter="saveRename" />
        <div class="flex gap-3">
          <button class="btn-ghost flex-1" @click="renameModal = null">Cancel</button>
          <button class="btn-primary flex-1" :disabled="renaming || !renameModal.name.trim()" @click="saveRename">
            {{ renaming ? 'Saving…' : 'Rename' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Add Facility Modal -->
    <div v-if="addFacModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5);backdrop-filter:blur(4px)"
      @click.self="addFacModal = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc;border:1px solid rgba(0,229,255,.2)">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-display font-bold text-slate-800">Add Facility</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl min-w-[44px] min-h-[44px] flex items-center justify-center" @click="addFacModal = null">✕</button>
        </div>
        <div class="space-y-3">
          <div>
            <label class="label">Name <span class="text-rose-400">*</span></label>
            <input v-model="addFacModal.name" class="input" maxlength="100" placeholder="Facility name" />
          </div>
          <div>
            <label class="label">Address</label>
            <input v-model="addFacModal.address" class="input" maxlength="200" placeholder="Street address" />
          </div>
          <div>
            <label class="label">City / Region</label>
            <input v-model="addFacModal.emirate" class="input" maxlength="100" placeholder="e.g. Dubai, Mumbai, Riyadh" />
          </div>
          <div>
            <label class="label">Courts</label>
            <input v-model="addFacModal.courts_count" type="number" min="1" max="50" class="input"
              placeholder="Number of courts" />
          </div>
          <div>
            <label class="label">Image URL <span class="text-slate-400">(optional)</span></label>
            <input v-model="addFacModal.image_url" class="input" placeholder="https://…" />
          </div>
        </div>
        <div class="flex gap-3 mt-5">
          <button class="btn-ghost flex-1" @click="addFacModal = null">Cancel</button>
          <button class="btn-primary flex-1" :disabled="addingFac || !addFacModal.name.trim()" @click="saveAddFacility">
            {{ addingFac ? 'Creating…' : 'Create Facility' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Edit Facility Modal -->
    <div v-if="editFacModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center"
      style="background:rgba(0,0,0,.5);backdrop-filter:blur(4px)"
      @click.self="editFacModal = null">
      <div class="w-full max-w-md rounded-t-3xl sm:rounded-3xl p-6"
        style="background:#f8fafc;border:1px solid rgba(0,229,255,.2)">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-display font-bold text-slate-800">Edit Facility</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl" @click="editFacModal = null">✕</button>
        </div>
        <div class="space-y-3">
          <div>
            <label class="label">Name *</label>
            <input v-model="editFacModal.name" class="input" maxlength="100" placeholder="Facility name" />
          </div>
          <div>
            <label class="label">Address</label>
            <input v-model="editFacModal.address" class="input" maxlength="200" placeholder="Street address" />
          </div>
          <div>
            <label class="label">City / Region</label>
            <input v-model="editFacModal.emirate" class="input" maxlength="100" placeholder="e.g. Dubai, Mumbai, Riyadh" />
          </div>
          <div>
            <label class="label">Courts</label>
            <input v-model="editFacModal.courts_count" type="number" min="1" max="50" class="input"
              placeholder="Number of courts" />
          </div>
          <div>
            <label class="label">Image URL</label>
            <input v-model="editFacModal.image_url" class="input" maxlength="500" placeholder="https://…" />
          </div>
        </div>
        <div class="flex gap-3 mt-5">
          <button class="btn-ghost flex-1" @click="editFacModal = null">Cancel</button>
          <button class="btn-primary flex-1" :disabled="saving || !editFacModal.name.trim()" @click="saveEditFacility">
            {{ saving ? 'Saving…' : 'Save Changes' }}
          </button>
        </div>
      </div>
    </div>

  </Teleport>
</template>
