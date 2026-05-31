<script setup>
import { ref, watch, onMounted, computed } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { clubs, currentClub, loadClubs, createClub, isManager } = useClub()

const newClub      = ref('')
const cfg          = ref(null)
const members      = ref([])
const requests     = ref([])  // pending join requests
const inviteEmail  = ref('')
const inviteLink   = ref('')
const note         = ref(null)
const cfgNote      = ref(null)
const inviteNote   = ref(null)
const busy         = ref(false)

const pendingRequests = computed(() => requests.value.filter(r => r.status === 'pending'))

async function load() {
  if (!currentClub.value) return
  const cid = currentClub.value.club_id
  const [{ data: c }, { data: m }, { data: r }] = await Promise.all([
    supabase.from('ranking_config').select('*').eq('club_id', cid).single(),
    supabase.from('club_members').select('user_id, role').eq('club_id', cid),
    isManager()
      ? supabase.from('join_requests').select('*').eq('club_id', cid).order('created_at', { ascending: false })
      : { data: [] },
  ])
  cfg.value     = c
  members.value = m ?? []
  requests.value = r ?? []
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
  const { elo_weight, participation_weight, k_factor } = cfg.value
  const sum = Number(elo_weight) + Number(participation_weight)
  if (Math.abs(sum - 1) > 0.01) {
    cfgNote.value = { ok: false, t: `Skill + Attendance must total 1.0 (currently ${sum.toFixed(2)}).` }
    return
  }
  busy.value = true; cfgNote.value = null
  const { error } = await supabase.from('ranking_config')
    .update({ elo_weight, participation_weight, k_factor })
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
        <input v-model.number="cfg.k_factor" type="number" min="8" max="64" step="4" class="input text-center" />
        <div class="text-[10px] text-slate-500 mt-1">Elo swing/match</div>
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
      class="flex justify-between py-2.5 border-b border-white/[0.05] last:border-0 text-sm items-center">
      <span class="text-slate-400 text-xs font-mono truncate">{{ m.user_id.slice(0, 14) }}…</span>
      <span class="text-xs">{{ roleLabel(m.role) }}</span>
    </div>
    <p class="text-[11px] text-slate-500 mt-3">
      To promote someone to Manager: update their role in Supabase → Table Editor → club_members.
    </p>
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
