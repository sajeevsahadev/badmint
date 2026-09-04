<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

const route  = useRoute()
const router = useRouter()
const { user, signInWithGoogle } = useAuth()

const data     = ref(null)
const loading  = ref(true)
const notFound = ref(false)
const existing = ref(null)   // this user's existing registration, if any
const submitting = ref(false)
const errorMsg = ref(null)
const done     = ref(false)

const t = computed(() => data.value?.tournament ?? null)
const spotsLeft = computed(() => t.value ? Math.max(0, t.value.max_teams - (data.value.confirmed_count + data.value.pending_count)) : 0)
const regOpen = computed(() => {
  if (t.value?.status !== 'registration_open') return false
  // Auto-close once the deadline passes, even if the admin left the status open.
  if (t.value.registration_end && t.value.registration_end < new Date().toISOString().slice(0, 10)) return false
  return true
})

const form = ref({ team_name: '', player_a: '', player_b: '', phone: '', notes: '' })

const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }) : 'TBC'

async function load() {
  loading.value = true; notFound.value = false
  const { data: res } = await supabase.rpc('get_public_tournament', { p_code: route.params.id })
  if (!res) { notFound.value = true; loading.value = false; return }
  data.value = res
  if (user.value) {
    form.value.player_a = user.value.user_metadata?.full_name || ''
    // The public payload already carries this user's registration (server-side,
    // RLS-safe). A rejected team may register again, so ignore that status.
    const mine = res.my_registration
    existing.value = mine && mine.status !== 'rejected' ? mine : null
  }
  loading.value = false
}
onMounted(load)

function signInToRegister() {
  // Return to THIS registration page after Google sign-in (not the home page).
  sessionStorage.setItem('bm_after_login', route.fullPath)
  sessionStorage.setItem('bm_skip_intro', '1')
  signInWithGoogle()
}

async function submit() {
  errorMsg.value = null
  if (!form.value.team_name.trim()) { errorMsg.value = 'Enter a team name.'; return }
  if (!form.value.player_a.trim())  { errorMsg.value = 'Enter player 1 name.'; return }
  submitting.value = true
  const { error } = await supabase.rpc('register_for_tournament', {
    p_tournament_id: t.value.id,
    p_team_name:  form.value.team_name.trim(),
    p_player_a_name: form.value.player_a.trim(),
    p_player_b_name: form.value.player_b.trim() || null,
    p_notes: form.value.notes.trim() || null,
    p_contact_phone: form.value.phone.trim() || null,
  })
  submitting.value = false
  if (error) { errorMsg.value = error.message; return }
  done.value = true
  load()
}
const statusText = s => ({ pending: 'Pending admin approval', confirmed: 'Confirmed', waitlisted: 'On the waitlist', rejected: 'Not accepted' }[s] || s)
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff">
    <div class="max-w-lg mx-auto px-4 pb-6 pt-[calc(env(safe-area-inset-top,0px)+3.75rem)] sm:pt-6">
      <RouterLink :to="t ? `/t/${t.share_code}` : '/'" class="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-4">‹ Tournament</RouterLink>

      <div v-if="loading" class="space-y-3"><div class="h-24 shimmer rounded-2xl" /><div class="h-64 shimmer rounded-2xl" /></div>

      <div v-else-if="notFound" class="card p-10 text-center">
        <div class="text-4xl mb-2">🏸</div>
        <p class="font-bold text-slate-700">Tournament not found</p>
      </div>

      <template v-else>
        <!-- Summary -->
        <div class="card-neon p-4 mb-4">
          <p class="text-[11px] font-semibold text-neon uppercase tracking-wide">Register your team</p>
          <h1 class="font-display text-xl font-extrabold gradient-text leading-tight mt-0.5">{{ t.name }}</h1>
          <p class="text-xs text-slate-500 mt-0.5">{{ t.club_name }} · {{ fmtDate(t.start_date) }}</p>
          <div class="flex flex-wrap gap-x-4 gap-y-1 mt-2 text-xs text-slate-500">
            <span>{{ spotsLeft }} of {{ t.max_teams }} spots left</span>
            <span v-if="t.entry_fee">Entry fee: <strong class="text-slate-700">{{ t.currency }} {{ t.entry_fee }}</strong></span>
          </div>
        </div>

        <!-- Success -->
        <div v-if="done || (existing && existing.status !== 'rejected')" class="card p-5">
          <div class="text-center">
            <div class="text-4xl mb-2">✅</div>
            <p class="font-display font-bold text-slate-800">Registration received</p>
          </div>
          <div class="rounded-xl p-3.5 mt-3 text-sm text-amber-700 leading-relaxed"
            style="background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.25)">
            <template v-if="existing && existing.status === 'waitlisted'">
              You're on the <strong>waitlist</strong> — the tournament is currently full. The organiser will
              confirm your team if a spot opens up.
            </template>
            <template v-else>
              Your registration needs to be <strong>approved by the admin</strong>. Please make sure your
              <strong>entry-fee payment is completed</strong> — the admin will confirm your team once the payment is received.
            </template>
          </div>
          <p v-if="existing" class="text-xs text-slate-500 mt-3 text-center">
            Status: <strong :class="existing.status === 'confirmed' ? 'text-emerald-600' : 'text-amber-600'">{{ statusText(existing.status) }}</strong>
          </p>
          <RouterLink :to="`/t/${t.share_code}`" class="btn-ghost w-full py-2.5 text-sm mt-4">View tournament page</RouterLink>
        </div>

        <!-- Not signed in -->
        <div v-else-if="!user" class="card p-6 text-center">
          <div class="text-3xl mb-2">📝</div>
          <p class="font-bold text-slate-800 mb-1">Sign in to register</p>
          <p class="text-sm text-slate-500 mb-4">You'll come straight back to this registration form.</p>
          <button class="btn-primary w-full py-3 text-sm" @click="signInToRegister">Sign in with Google — Free</button>
        </div>

        <!-- Closed -->
        <div v-else-if="!regOpen" class="card p-6 text-center text-sm text-slate-500">
          Registration is not open for this tournament.
        </div>

        <!-- Form (waitlist when full) -->
        <div v-else class="card p-5 space-y-3">
          <div v-if="spotsLeft <= 0" class="rounded-xl p-3 text-xs text-amber-700 leading-relaxed"
            style="background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.25)">
            This tournament is <strong>full</strong>. You can still sign up — your team will join the
            <strong>waitlist</strong> and the organiser will confirm you if a spot opens.
          </div>
          <label class="block"><span class="label">Team name</span>
            <input v-model="form.team_name" class="input" placeholder="e.g. Smash Bros" /></label>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="block"><span class="label">Player 1</span>
              <input v-model="form.player_a" class="input" placeholder="Your name" /></label>
            <label class="block"><span class="label">Player 2</span>
              <input v-model="form.player_b" class="input" placeholder="Partner's name" /></label>
          </div>
          <label class="block"><span class="label">Contact phone</span>
            <input v-model="form.phone" class="input" placeholder="For payment confirmation" inputmode="tel" /></label>
          <label class="block"><span class="label">Notes (optional)</span>
            <input v-model="form.notes" class="input" placeholder="Anything the organiser should know" /></label>

          <div class="rounded-xl p-3 text-xs text-slate-500 leading-relaxed"
            style="background:rgba(0,180,216,.06);border:1px solid rgba(0,180,216,.18)">
            After you submit, your registration is <strong>pending admin approval</strong>. Please complete your
            entry-fee payment; the admin confirms your team once the payment is acknowledged.
          </div>

          <p v-if="errorMsg" class="text-xs text-rose-500">⚠️ {{ errorMsg }}</p>
          <button class="btn-primary w-full py-3 text-sm" :disabled="submitting" @click="submit">
            {{ submitting ? 'Submitting…' : (spotsLeft <= 0 ? 'Join the waitlist' : 'Submit registration') }}
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
