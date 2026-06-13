<script setup>
import { ref, watch, onMounted, onUnmounted } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()
const players  = ref([])
const newName  = ref('')
const newEmail = ref('')
const busy     = ref(false)
const msg      = ref(null)
const invite   = ref(null)   // { link, email } after successful add-with-email
let _msgTimer = null
onUnmounted(() => { clearTimeout(_msgTimer) })

async function load() {
  if (!currentClub.value) return
  const { data } = await supabase.rpc('get_club_players', {
    p_club_id: currentClub.value.club_id
  })
  players.value = data ?? []
}
onMounted(load)
watch(currentClub, load)

async function add() {
  if (!newName.value.trim()) return
  busy.value = true; msg.value = null; invite.value = null

  const { error } = await supabase.from('players').insert({
    club_id:      currentClub.value.club_id,
    display_name: newName.value.trim()
  })
  if (error) { msg.value = error.message; busy.value = false; return }

  // If manager provided email, generate invite link
  if (newEmail.value.trim()) {
    const { data: token, error: invErr } = await supabase.rpc('invite_member', {
      p_club_id: currentClub.value.club_id,
      p_email:   newEmail.value.trim()
    })
    if (!invErr && token) {
      invite.value = {
        email: newEmail.value.trim(),
        link:  `${window.location.origin}/join?token=${token}`,
        name:  newName.value.trim(),
        club:  currentClub.value.clubs?.name ?? 'the club'
      }
    }
  }

  newName.value = ''; newEmail.value = ''
  busy.value = false
  load()
}

async function remove(id, name) {
  // Block deletion if player has match history
  const { count } = await supabase
    .from('match_participants')
    .select('*', { count: 'exact', head: true })
    .eq('player_id', id)
  if (count > 0) {
    msg.value = `Cannot remove ${name} — they have ${count} recorded match${count !== 1 ? 'es' : ''}. Deactivate them instead using the toggle button.`
    return
  }
  if (!confirm(`Remove "${name}" from the roster? This cannot be undone.`)) return
  await supabase.from('players').delete().eq('id', id)
  msg.value = null
  load()
}

async function toggleActive(p) {
  const { data, error } = await supabase.rpc('toggle_player_active', { p_player_id: p.id })
  if (!error) p.is_active = data
}

function copyLink() {
  navigator.clipboard.writeText(invite.value.link)
  msg.value = '✅ Link copied!'
  clearTimeout(_msgTimer)
  _msgTimer = setTimeout(() => { msg.value = null }, 2500)
}

function whatsappLink() {
  const text = `Hi ${invite.value.name}! 🏸 You've been invited to join "${invite.value.club}" on Badminton 360 — the free rankings app for badminton teams.\n\nClick here to join and set up your profile:\n${invite.value.link}\n\nThe link expires in 7 days.`
  return `https://wa.me/?text=${encodeURIComponent(text)}`
}

function mailtoLink() {
  const subj = encodeURIComponent(`You're invited to join ${invite.value.club} on Badminton 360 🏸`)
  const body = encodeURIComponent(
    `Hi ${invite.value.name}!\n\nYou've been invited to join "${invite.value.club}" on Badminton 360 — the free Elo rankings app for badminton teams.\n\nClick the link below to join and set up your profile:\n${invite.value.link}\n\nThe link expires in 7 days. See you on the court! 🏸`
  )
  return `mailto:${invite.value.email}?subject=${subj}&body=${body}`
}

const eloColor = elo => elo >= 1100 ? 'text-neon' : elo <= 900 ? 'text-rose-400' : 'text-slate-300'
const eloLabel = elo => elo >= 1100 ? '🔥 Strong' : elo >= 1000 ? 'Average' : 'Developing'
</script>

<template>
  <PageHeader icon="👥" title="Players" subtitle="Your club's roster — tap a name to view their profile">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-slate-800">Add players</strong> before recording any match. Add their name and optionally their email to send an invite.</p>
        <p><strong class="text-slate-800">Invite link</strong> — when you add an email, a personal invite link is generated. Share via WhatsApp or email. The player fills in their own profile when they join.</p>
        <p><strong class="text-slate-800">Guest players</strong> (no Google login yet) are supported — add their name and record matches. They can claim their account later via an invite link.</p>
        <p><strong class="text-slate-800">Tap any player name</strong> to view their public profile and match history.</p>
      </div>
    </template>
  </PageHeader>

  <!-- Add form (managers only) -->
  <div v-if="isManager()" class="card mb-4 p-4 fade-up">
    <div class="label">Add a Player</div>
    <div class="space-y-2 mb-2">
      <input v-model="newName" class="input" placeholder="Player's name (e.g. Ahmed Khan)"
        @keyup.enter="add" maxlength="40" />
      <input v-model="newEmail" class="input" type="email"
        placeholder="Email address (optional — to send invite)" />
    </div>
    <button class="btn-primary w-full" :disabled="busy || !newName.trim()" @click="add">
      {{ busy ? 'Adding…' : newEmail.trim() ? '➕ Add & Generate Invite' : '➕ Add Player' }}
    </button>
    <p class="mt-2 text-xs text-slate-500">
      They don't need to have logged in yet. Add their name and start recording matches.
    </p>
    <p v-if="msg" class="mt-2 text-xs" :class="msg.startsWith('✅') ? 'text-emerald-400' : 'text-rose-400'">{{ msg }}</p>
  </div>

  <!-- Invite share panel -->
  <div v-if="invite" class="card-violet p-4 mb-4 fade-up">
    <div class="label mb-1">Share Invite with {{ invite.name }}</div>
    <div class="text-xs text-slate-300 font-mono break-all mb-3 px-3 py-2 rounded-xl bg-white/[0.04] border border-white/[0.08] select-all">
      {{ invite.link }}
    </div>
    <div class="grid grid-cols-3 gap-2">
      <button class="btn-primary text-xs py-2" @click="copyLink">📋 Copy</button>
      <a :href="whatsappLink()" target="_blank" rel="noopener"
        class="btn-success text-xs py-2 text-center no-underline">
        💬 WhatsApp
      </a>
      <a :href="mailtoLink()"
        class="btn-ghost text-xs py-2 text-center no-underline">
        ✉️ Email
      </a>
    </div>
    <p class="text-xs text-slate-500 mt-2 text-center">
      Link expires in 7 days · Player fills in full name, nickname & photo on arrival
    </p>
  </div>

  <!-- Roster list -->
  <div v-if="players.length" class="card overflow-hidden fade-up">
    <div class="px-4 py-2.5 border-b border-white/[0.06] flex items-center justify-between">
      <span class="text-xs text-slate-500 font-medium">
        {{ players.length }} player{{ players.length !== 1 ? 's' : '' }} · sorted by Elo
      </span>
    </div>

    <div v-for="(p, i) in players" :key="p.id"
      class="flex items-center justify-between px-4 py-3 border-b border-white/[0.04] last:border-0 transition-colors duration-150"
      :class="p.is_active ? 'hover:bg-white/[0.02]' : 'opacity-50'">

      <RouterLink :to="'/player/' + p.id" class="flex items-center gap-3 flex-1 min-w-0">
        <!-- Rank circle / inactive indicator -->
        <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-black shrink-0"
          :style="!p.is_active
            ? 'background:rgba(255,255,255,0.05); color:#64748b'
            : i < 3
              ? 'background:linear-gradient(135deg,#00e5ff,#0099cc); color:#0a0a0a'
              : 'background:rgba(255,255,255,0.08); color:#94a3b8'">
          {{ p.is_active ? (i + 1) : '—' }}
        </div>
        <div class="min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="font-semibold text-sm truncate hover:text-neon transition-colors"
              :class="p.is_active ? 'text-slate-100' : 'text-slate-500'">
              {{ p.display_name }}
            </span>
            <!-- Online status dot (only for linked accounts) -->
            <template v-if="p.user_id && p.is_active">
              <span v-if="p.online_status === 'online'"
                class="w-2 h-2 rounded-full shrink-0 animate-pulse"
                style="background:#10b981; box-shadow:0 0 6px #10b981" title="Online now" />
              <span v-else-if="p.online_status === 'recent'"
                class="w-2 h-2 rounded-full shrink-0"
                style="background:#f59e0b" title="Active recently" />
              <span v-else
                class="w-4 h-4 rounded-full shrink-0 flex items-center justify-center text-[8px] font-black"
                style="background:rgba(100,116,139,.2); color:#64748b; border:1px solid rgba(100,116,139,.3)"
                title="Not seen in over 1 month">✕</span>
            </template>
            <span v-if="!p.is_active"
              class="text-[9px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded-full shrink-0"
              style="background:rgba(100,116,139,.2); color:#64748b; border:1px solid rgba(100,116,139,.25)">
              Inactive
            </span>
          </div>
          <div class="text-xs mt-0.5" :class="p.is_active ? eloColor(Math.round(p.elo)) : 'text-slate-600'">
            Elo {{ Math.round(p.elo) }}{{ p.is_active ? ' · ' + eloLabel(Math.round(p.elo)) : '' }}
          </div>
        </div>
      </RouterLink>

      <!-- Manager actions -->
      <div v-if="isManager()" class="flex items-center gap-1 shrink-0 ml-2">
        <!-- Active / Inactive toggle -->
        <button class="text-xs font-semibold px-2 py-1 rounded-lg transition border"
          :class="p.is_active
            ? 'text-slate-500 border-white/10 hover:text-amber-400 hover:border-amber-500/30'
            : 'text-emerald-400 border-emerald-500/30 hover:bg-emerald-500/10'"
          :title="p.is_active ? 'Deactivate player' : 'Reactivate player'"
          @click.prevent="toggleActive(p)">
          {{ p.is_active ? 'Deactivate' : 'Reactivate' }}
        </button>
        <!-- Remove (only if no match history) -->
        <button class="text-xs text-slate-600 hover:text-rose-400 transition px-1.5 py-1"
          @click.prevent="remove(p.id, p.display_name)">✕</button>
      </div>
    </div>
  </div>

  <div v-else class="card p-8 text-center text-slate-400 fade-up">
    <div class="text-3xl mb-3">👤</div>
    <p class="font-semibold mb-1">No players yet</p>
    <p class="text-sm">{{ isManager() ? 'Add your first player above.' : 'Ask your manager to add players.' }}</p>
  </div>
</template>
