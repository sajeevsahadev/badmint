<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import Avatar from '../components/Avatar.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'

const { avatarMap, loadAvatars } = usePlayerAvatars()
const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { clubs } = useClub()

const clubId      = route.params.id
const adminView   = ref(false)   // true when ?admin=1 and user is app_admin
const club        = ref(null)
const ranking     = ref(null)
const members     = ref([])
const leaderboard = ref([])
const loading     = ref(true)
const notMember   = ref(false)

// Join request state
const joinBusy    = ref(false)
const joinStatus  = ref(null)   // null | 'pending' | 'sent' | 'error'
const joinNote    = ref('')

const isMyClub  = computed(() => clubs.value.some(c => c.club_id === clubId))
const myRole    = computed(() => clubs.value.find(c => c.club_id === clubId)?.role)
const isManager = computed(() => ['owner','manager'].includes(myRole.value))

async function load() {
  loading.value = true
  notMember.value = false
  adminView.value = false

  // Check if this is an admin view request
  const wantsAdmin = route.query.admin === '1' && !!user.value
  if (wantsAdmin) {
    const { data: roles } = await supabase.rpc('get_my_roles')
    adminView.value = (roles ?? []).some(r => r.role === 'app_admin')
  }

  // Always fetch public club info via get_public_clubs (bypasses RLS)
  const [rankRes, lbRes] = await Promise.all([
    supabase.rpc('get_public_clubs'),
    supabase.rpc('get_club_leaderboard', { p_club_id: clubId }),
  ])

  const publicClub = (rankRes.data ?? []).find(c => c.id === clubId) ?? null
  ranking.value = publicClub

  if (!publicClub) {
    loading.value = false
    return
  }

  club.value = {
    id:               publicClub.id,
    name:             publicClub.name,
    emirates:         publicClub.emirates,
    facility_name:    publicClub.facility_name,
    facility_address: publicClub.facility_address,
    maps_url:         publicClub.maps_url,
    description:      publicClub.description,
    created_at:       publicClub.created_at,
  }

  leaderboard.value = (lbRes.data ?? []).filter(p => p.games > 0)
  loadAvatars(leaderboard.value.map(p => p.user_id))

  if (isMyClub.value || adminView.value) {
    // Member or admin — fetch full player list
    const memberRes = await supabase.rpc('get_club_players', { p_club_id: clubId })
    members.value = memberRes.data ?? []
    loadAvatars(members.value.map(m => m.user_id))
  } else {
    // Not a member — show limited view + join prompt
    notMember.value = true
    members.value   = []
    if (user.value) {
      const { data } = await supabase
        .from('join_requests')
        .select('status')
        .eq('club_id', clubId)
        .eq('user_id', user.value.id)
        .maybeSingle()
      if (data) joinStatus.value = data.status
    }
  }

  loading.value = false
}

async function sendJoinRequest() {
  joinBusy.value = true; joinNote.value = ''
  const { error } = await supabase.rpc('request_join', { p_club_id: clubId })
  joinBusy.value = false
  if (error) {
    joinNote.value = error.message
  } else {
    joinStatus.value = 'pending'
  }
}

onMounted(load)

const initials = name => (name ?? '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
const onlineColor = s => s === 'online' ? '#10b981' : s === 'recent' ? '#f59e0b' : '#475569'

// ── Rename ──
const renaming    = ref(false)
const renameValue = ref('')
const renameBusy  = ref(false)
const renameNote  = ref(null)

function startRename() {
  renameValue.value = club.value?.name ?? ''
  renameNote.value  = null
  renaming.value    = true
}
async function saveRename() {
  if (!renameValue.value.trim() || renameValue.value.trim() === club.value.name) {
    renaming.value = false; return
  }
  renameBusy.value = true; renameNote.value = null
  const { error } = await supabase.rpc('rename_club', {
    p_club_id: clubId,
    p_name:    renameValue.value.trim(),
  })
  renameBusy.value = false
  if (error) {
    renameNote.value = error.message
  } else {
    club.value = { ...club.value, name: renameValue.value.trim() }
    renaming.value = false
  }
}
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <div v-else-if="!club" class="card p-8 text-center text-slate-400">
    <p class="text-3xl mb-2">🏸</p>
    <p class="font-semibold mb-2">Club not found</p>
    <button class="btn-ghost px-6 text-sm mt-2" @click="router.back()">← Back</button>
  </div>

  <!-- Not a member banner (shown above club content) -->
  <div v-if="club && notMember" class="card-violet p-5 mb-4 text-center">
    <p class="text-2xl mb-1">🔒</p>
    <p class="font-bold text-slate-800 mb-1">You're not a member of this club</p>
    <p class="text-sm text-slate-500 mb-4">Only members can see the full roster and match history.</p>

    <div v-if="!user" class="space-y-2">
      <p class="text-sm text-slate-500">Sign in to send a join request.</p>
      <RouterLink to="/login" class="btn-primary inline-block px-6 py-2 text-sm">Sign In</RouterLink>
    </div>

    <div v-else-if="joinStatus === 'pending'" class="text-sm text-amber-600 font-medium">
      ⏳ Your join request is pending approval by the club manager.
    </div>
    <div v-else-if="joinStatus === 'approved'" class="text-sm text-emerald-600 font-medium">
      ✅ Your request was approved — refresh the page to see the full club.
    </div>
    <div v-else>
      <button class="btn-primary px-8 py-2 text-sm" :disabled="joinBusy" @click="sendJoinRequest">
        {{ joinBusy ? 'Sending…' : '📨 Send Join Request' }}
      </button>
      <p v-if="joinNote" class="text-rose-500 text-xs mt-2">{{ joinNote }}</p>
    </div>
  </div>

  <template v-else>
    <!-- Admin view banner -->
    <div v-if="adminView" class="mb-4 rounded-2xl bg-amber-50 border border-amber-300 px-4 py-3 flex items-center gap-3 fade-up">
      <span class="text-xl shrink-0">👑</span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-bold text-amber-800">You are viewing this club as Super Admin</p>
        <p class="text-xs text-amber-600">This view is only visible to admins. Members see a restricted version.</p>
      </div>
      <button class="shrink-0 text-xs text-amber-700 underline hover:no-underline" @click="router.back()">← Back to Admin</button>
    </div>

    <!-- Back -->
    <button v-else class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4"
      @click="router.back()">
      ← Back
    </button>

    <!-- Club header -->
    <div class="card-neon p-5 mb-4 fade-up">
      <div class="flex items-start gap-4">
        <!-- Club avatar -->
        <div class="w-16 h-16 rounded-2xl flex items-center justify-center text-xl font-black text-slate-950 shrink-0"
          style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
          {{ initials(club.name) }}
        </div>
        <div class="flex-1 min-w-0">
          <!-- Rename inline form -->
          <div v-if="renaming" class="flex items-center gap-2 mb-1">
            <input v-model="renameValue" class="input text-sm flex-1 py-1.5"
              maxlength="50" @keyup.enter="saveRename" @keyup.escape="renaming = false"
              ref="renameInput" />
            <button class="btn-primary text-xs px-3 py-1.5 shrink-0"
              :disabled="renameBusy || !renameValue.trim()"
              @click="saveRename">
              {{ renameBusy ? '…' : 'Save' }}
            </button>
            <button class="btn-ghost text-xs px-2.5 py-1.5 shrink-0"
              @click="renaming = false">✕</button>
          </div>
          <div v-else class="flex items-center gap-2">
            <h2 class="font-display text-xl font-extrabold gradient-text leading-tight">{{ club.name }}</h2>
            <button v-if="isManager" class="shrink-0 text-slate-600 hover:text-neon transition text-sm"
              title="Rename club" @click="startRename">✏️</button>
          </div>
          <p v-if="renameNote" class="text-xs text-rose-400 mt-1">{{ renameNote }}</p>

          <div class="flex flex-wrap gap-1.5 mt-1">
            <span v-if="club.emirates" class="badge-member text-[9px]">{{ club.emirates }}</span>
            <span v-if="isMyClub" class="badge-approved text-[9px]">{{ myRole }}</span>
          </div>
          <p v-if="club.description" class="text-xs text-slate-400 mt-2 leading-relaxed">{{ club.description }}</p>
        </div>
      </div>

      <!-- Manage button (for managers) -->
      <RouterLink v-if="isManager" to="/manage"
        class="mt-3 block text-center text-xs text-neon border border-cyan-500/25 rounded-xl py-2 hover:opacity-80 transition">
        ⚙️ Manage This Club
      </RouterLink>
    </div>

    <!-- Club score stats -->
    <div v-if="ranking" class="grid grid-cols-4 gap-2 mb-4 fade-up">
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-gold">#{{ ranking.club_rank }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Rank</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-neon">{{ ranking.club_score }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Score</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-slate-200">{{ members.length }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Members</div>
      </div>
      <button class="card p-3 text-center cursor-pointer hover:border-violet-400/40 transition-all active:scale-95"
        @click="router.push('/matches')">
        <div class="text-lg font-extrabold text-violet">{{ ranking.matches_30d }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Matches/mo</div>
      </button>
    </div>

    <!-- Facility info -->
    <div v-if="club.facility_name || club.facility_address || club.maps_url"
      class="card p-4 mb-4 fade-up">
      <div class="label">📍 Facility</div>
      <div v-if="club.facility_name" class="text-sm font-semibold text-slate-200 mb-0.5">{{ club.facility_name }}</div>
      <div v-if="club.facility_address" class="text-xs text-slate-400 mb-2">{{ club.facility_address }}</div>
      <a v-if="club.maps_url" :href="club.maps_url" target="_blank" rel="noopener"
        class="inline-flex items-center gap-1.5 text-xs text-neon hover:opacity-80 transition border border-cyan-500/20 rounded-lg px-3 py-1.5">
        🗺️ Open in Google Maps
      </a>
    </div>

    <!-- Members leaderboard -->
    <div class="card overflow-hidden fade-up">
      <div class="px-4 py-3 border-b border-[rgba(15,23,42,0.06)] flex items-center justify-between">
        <span class="text-xs font-bold text-slate-200">
          🏆 Leaderboard
          <span class="text-slate-500 font-normal ml-1">({{ members.filter(m => m.is_active).length }} active)</span>
        </span>
        <RouterLink v-if="isManager" to="/players"
          class="text-xs text-neon hover:opacity-80 transition">
          + Add Player
        </RouterLink>
      </div>

      <!-- Leaderboard table for ranked players -->
      <div v-if="leaderboard.length">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-[rgba(15,23,42,0.06)]">
              <th class="pl-4 pr-2 py-2 text-left text-xs uppercase tracking-wider text-slate-500">#</th>
              <th class="pl-2 pr-2 py-2 text-left text-xs uppercase tracking-wider text-slate-500">Player</th>
              <th class="px-2 py-2 text-right text-xs uppercase tracking-wider text-slate-500">Elo</th>
              <th class="px-2 py-2 text-right text-xs uppercase tracking-wider text-slate-500">W%</th>
              <th class="pl-2 pr-4 py-2 text-right text-xs uppercase tracking-wider text-slate-500">Days</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(p, i) in leaderboard" :key="p.id"
              class="border-b border-[rgba(15,23,42,0.04)] last:border-0 transition-colors hover:bg-[rgba(15,23,42,0.02)]">
              <td class="pl-4 pr-2 py-3">
                <span class="text-sm">{{ ['🥇','🥈','🥉'][i] ?? (i + 1) }}</span>
              </td>
              <td class="pl-2 pr-2 py-3">
                <div class="flex items-center gap-2 min-w-0">
                  <Avatar :name="p.display_name" :src="avatarMap[p.user_id]" :size="28" />
                  <RouterLink :to="'/player/' + p.id + (adminView ? '?admin=1' : '')"
                    class="font-semibold text-slate-100 hover:text-neon transition-colors text-sm truncate min-w-0">
                    {{ p.display_name }}
                  </RouterLink>
                </div>
              </td>
              <td class="px-2 py-3 text-right text-xs font-bold text-neon">{{ p.elo }}</td>
              <td class="px-2 py-3 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
              <td class="pl-2 pr-4 py-3 text-right text-xs text-slate-500">{{ p.days_played }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Unranked members (guests/no matches yet) not in leaderboard -->
      <div v-if="members.filter(m => m.is_active && !leaderboard.some(l => l.id === m.id)).length"
        class="border-t border-[rgba(15,23,42,0.06)]">
        <div class="px-4 py-2 text-[10px] uppercase tracking-widest text-slate-600">No matches yet</div>
        <RouterLink v-for="m in members.filter(m => m.is_active && !leaderboard.some(l => l.id === m.id))"
          :key="m.id" :to="'/player/' + m.id + (adminView ? '?admin=1' : '')"
          class="flex items-center gap-3 px-4 py-2.5 border-b border-[rgba(15,23,42,0.04)] last:border-0
                 hover:bg-[rgba(15,23,42,0.02)] transition-colors">
          <div class="relative shrink-0">
            <Avatar :name="m.display_name" :src="avatarMap[m.user_id]" :size="28" />
            <span v-if="m.user_id" class="absolute -bottom-0.5 -right-0.5 w-2 h-2 rounded-full border border-slate-900"
              :style="'background:' + onlineColor(m.online_status)" />
          </div>
          <span class="text-sm text-slate-400 flex-1 truncate">{{ m.display_name }}</span>
          <span class="text-slate-600 text-xs">›</span>
        </RouterLink>
      </div>

      <div v-if="!members.length" class="px-4 py-6 text-center text-sm text-slate-500">
        No players yet.
      </div>
    </div>

  </template>
</template>
