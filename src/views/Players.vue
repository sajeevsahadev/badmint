<script setup>
import { ref, watch, onMounted } from 'vue'
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

async function load() {
  if (!currentClub.value) return
  const { data } = await supabase.from('players')
    .select('id, display_name, elo, created_at, user_id')
    .eq('club_id', currentClub.value.club_id)
    .order('elo', { ascending: false })
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
  if (!confirm(`Remove "${name}" from the roster?\n\nMatch history and stats will be preserved.`)) return
  await supabase.from('players').delete().eq('id', id)
  load()
}

function copyLink() {
  navigator.clipboard.writeText(invite.value.link)
  msg.value = '✅ Link copied!'
  setTimeout(() => { msg.value = null }, 2500)
}

function whatsappLink() {
  const text = `Hi ${invite.value.name}! 🏸 You've been invited to join "${invite.value.club}" on Badmint — the free rankings app for UAE badminton teams.\n\nClick here to join and set up your profile:\n${invite.value.link}\n\nThe link expires in 7 days.`
  return `https://wa.me/?text=${encodeURIComponent(text)}`
}

function mailtoLink() {
  const subj = encodeURIComponent(`You're invited to join ${invite.value.club} on Badmint 🏸`)
  const body = encodeURIComponent(
    `Hi ${invite.value.name}!\n\nYou've been invited to join "${invite.value.club}" on Badmint — the free Elo rankings app for UAE badminton teams.\n\nClick the link below to join and set up your profile:\n${invite.value.link}\n\nThe link expires in 7 days. See you on the court! 🏸`
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
        <p><strong class="text-white">Add players</strong> before recording any match. Add their name and optionally their email to send an invite.</p>
        <p><strong class="text-white">Invite link</strong> — when you add an email, a personal invite link is generated. Share via WhatsApp or email. The player fills in their own profile when they join.</p>
        <p><strong class="text-white">Guest players</strong> (no Google login yet) are supported — add their name and record matches. They can claim their account later via an invite link.</p>
        <p><strong class="text-white">Tap any player name</strong> to view their public profile and match history.</p>
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
    <p class="mt-2 text-[11px] text-slate-500">
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
    <p class="text-[10px] text-slate-500 mt-2 text-center">
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
      class="flex items-center justify-between px-4 py-3 border-b border-white/[0.04] last:border-0
             hover:bg-white/[0.02] transition-colors duration-150">
      <RouterLink :to="'/player/' + p.id" class="flex items-center gap-3 flex-1 min-w-0">
        <!-- Rank circle -->
        <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-black shrink-0 text-slate-950"
          :style="i < 3
            ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)'
            : 'background:rgba(255,255,255,0.08); color:#94a3b8'">
          {{ i + 1 }}
        </div>
        <div class="min-w-0">
          <div class="font-semibold text-sm text-slate-100 truncate hover:text-neon transition-colors">
            {{ p.display_name }}
          </div>
          <div class="text-[11px] mt-0.5" :class="eloColor(Math.round(p.elo))">
            Elo {{ Math.round(p.elo) }} · {{ eloLabel(Math.round(p.elo)) }}
          </div>
        </div>
      </RouterLink>

      <button v-if="isManager()"
        class="text-[11px] text-slate-600 hover:text-rose-400 transition px-2 py-1 shrink-0 ml-2"
        @click="remove(p.id, p.display_name)">Remove</button>
    </div>
  </div>

  <div v-else class="card p-8 text-center text-slate-400 fade-up">
    <div class="text-3xl mb-3">👤</div>
    <p class="font-semibold mb-1">No players yet</p>
    <p class="text-sm">{{ isManager() ? 'Add your first player above.' : 'Ask your manager to add players.' }}</p>
  </div>
</template>
