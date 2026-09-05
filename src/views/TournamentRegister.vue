<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

const route = useRoute()
const { user } = useAuth()

const data     = ref(null)
const loading  = ref(true)
const notFound = ref(false)
const submitting = ref(false)
const errorMsg = ref(null)
const done     = ref(false)
const doneStatus = ref('pending')

const t = computed(() => data.value?.tournament ?? null)
const spotsLeft = computed(() => t.value ? Math.max(0, t.value.max_teams - (data.value.confirmed_count + data.value.pending_count)) : 0)
const regOpen = computed(() => {
  if (t.value?.status !== 'registration_open') return false
  if (t.value.registration_end && t.value.registration_end < new Date().toISOString().slice(0, 10)) return false
  return true
})

const form = ref({
  p1_name: '', p1_phone: '', p1_email: '',
  p2_name: '', p2_phone: '', p2_email: '',
  team_name: '',
})
const teamNameEdited = ref(false)
// Auto-fill team name = "Player 1 & Player 2" until the user edits it themselves.
watch(() => [form.value.p1_name, form.value.p2_name], () => {
  if (teamNameEdited.value) return
  const a = form.value.p1_name.trim(), b = form.value.p2_name.trim()
  form.value.team_name = a && b ? `${a} & ${b}` : (a || b || '')
})

const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }) : 'TBC'

async function load() {
  loading.value = true; notFound.value = false
  const { data: res } = await supabase.rpc('get_public_tournament', { p_code: route.params.slug || route.params.id })
  if (!res) { notFound.value = true; loading.value = false; return }
  data.value = res
  // Prefill player 1 from the signed-in user, if any (registration itself is anonymous).
  if (user.value) {
    form.value.p1_name = form.value.p1_name || user.value.user_metadata?.full_name || ''
    form.value.p1_email = form.value.p1_email || user.value.email || ''
  }
  loading.value = false
}
onMounted(() => { load(); mountTurnstile() })

// ── Cloudflare Turnstile (bot check) — only when a site key is configured ──
const SITE_KEY = import.meta.env.VITE_TURNSTILE_SITE_KEY || ''
const turnstileToken = ref('')
const widgetBox = ref(null)
let widgetId = null
function mountTurnstile() {
  if (!SITE_KEY) return
  const render = () => {
    if (!window.turnstile || !widgetBox.value) return
    widgetId = window.turnstile.render(widgetBox.value, {
      sitekey: SITE_KEY,
      callback: (tok) => { turnstileToken.value = tok },
      'error-callback': () => { turnstileToken.value = '' },
      'expired-callback': () => { turnstileToken.value = '' },
    })
  }
  if (window.turnstile) { render(); return }
  if (!document.getElementById('cf-turnstile-js')) {
    const s = document.createElement('script')
    s.id = 'cf-turnstile-js'
    s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'
    s.async = true; s.defer = true
    document.head.appendChild(s)
  }
  const iv = setInterval(() => { if (window.turnstile) { clearInterval(iv); render() } }, 200)
  setTimeout(() => clearInterval(iv), 8000)
}
onUnmounted(() => { try { widgetId && window.turnstile?.remove(widgetId) } catch { /* ignore */ } })

const emailOk = e => /^\S+@\S+\.\S+$/.test(e.trim())

async function submit() {
  errorMsg.value = null
  const f = form.value
  if (!f.p1_name.trim() || !f.p2_name.trim()) { errorMsg.value = 'Both player names are required.'; return }
  const hasEmail = emailOk(f.p1_email) || emailOk(f.p2_email)
  const hasPhone = f.p1_phone.trim() || f.p2_phone.trim()
  if (!hasEmail && !hasPhone) { errorMsg.value = 'Add at least one email or phone number so the organiser can reach you.'; return }
  if (SITE_KEY && !turnstileToken.value) { errorMsg.value = 'Please complete the "I\'m human" check.'; return }

  submitting.value = true
  try {
    const resp = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/register-team`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
        Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({
        code: route.params.slug || route.params.id,
        team_name: f.team_name.trim() || null,
        a_name: f.p1_name.trim(), a_phone: f.p1_phone.trim() || null, a_email: f.p1_email.trim() || null,
        b_name: f.p2_name.trim(), b_phone: f.p2_phone.trim() || null, b_email: f.p2_email.trim() || null,
        turnstile_token: turnstileToken.value || null,
      }),
    })
    const out = await resp.json()
    if (!resp.ok) { errorMsg.value = out.error || 'Could not submit. Please try again.'; return }
    doneStatus.value = out.status || 'pending'
    done.value = true
  } catch {
    errorMsg.value = 'Network error — please try again.'
  } finally {
    submitting.value = false
    try { widgetId && window.turnstile?.reset(widgetId) } catch { /* ignore */ }
    turnstileToken.value = ''
  }
}
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff">
    <div class="max-w-lg mx-auto px-4 pb-10 pt-[calc(env(safe-area-inset-top,0px)+3.75rem)] sm:pt-6">
      <RouterLink :to="t ? `/tournaments/${t.slug || t.share_code}` : '/'" class="inline-flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-4">‹ Tournament</RouterLink>

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
        <div v-if="done" class="card p-6 text-center">
          <div class="text-4xl mb-2">✅</div>
          <p class="font-display font-bold text-slate-800">Registration received</p>
          <div class="rounded-xl p-3.5 mt-3 text-sm text-amber-700 leading-relaxed text-left"
            style="background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.25)">
            <template v-if="doneStatus === 'waitlisted'">
              The tournament is full, so your team is on the <strong>waitlist</strong>.
            </template>
            Your request is <strong>awaiting confirmation from the tournament admin</strong>. You'll get a
            confirmation email once it's confirmed.
          </div>
          <RouterLink :to="`/tournaments/${t.slug || t.share_code}`" class="btn-ghost w-full py-2.5 text-sm mt-4">View tournament page</RouterLink>
        </div>

        <!-- Closed -->
        <div v-else-if="!regOpen" class="card p-6 text-center text-sm text-slate-500">
          Registration is not open for this tournament.
        </div>

        <!-- Google-Form-style entry -->
        <div v-else class="card p-5 space-y-4">
          <div v-if="spotsLeft <= 0" class="rounded-xl p-3 text-xs text-amber-700 leading-relaxed"
            style="background:rgba(251,191,36,.1);border:1px solid rgba(251,191,36,.25)">
            This tournament is <strong>full</strong>. You can still sign up — your team will join the <strong>waitlist</strong>.
          </div>

          <!-- Player 1 -->
          <div class="rounded-2xl border border-slate-200 p-3.5">
            <p class="text-xs font-bold text-slate-600 mb-2">Player 1</p>
            <label class="block mb-2"><span class="label">Name *</span>
              <input v-model="form.p1_name" class="input" placeholder="Full name" /></label>
            <div class="grid grid-cols-2 gap-2">
              <label class="block"><span class="label">Phone</span>
                <input v-model="form.p1_phone" class="input" inputmode="tel" placeholder="Optional" /></label>
              <label class="block"><span class="label">Email</span>
                <input v-model="form.p1_email" type="email" class="input" inputmode="email" placeholder="Optional" /></label>
            </div>
          </div>

          <!-- Player 2 -->
          <div class="rounded-2xl border border-slate-200 p-3.5">
            <p class="text-xs font-bold text-slate-600 mb-2">Player 2</p>
            <label class="block mb-2"><span class="label">Name *</span>
              <input v-model="form.p2_name" class="input" placeholder="Partner's full name" /></label>
            <div class="grid grid-cols-2 gap-2">
              <label class="block"><span class="label">Phone</span>
                <input v-model="form.p2_phone" class="input" inputmode="tel" placeholder="Optional" /></label>
              <label class="block"><span class="label">Email</span>
                <input v-model="form.p2_email" type="email" class="input" inputmode="email" placeholder="Optional" /></label>
            </div>
          </div>

          <p class="text-[11px] text-slate-400 -mt-1">At least one email or phone number is required so the organiser can send your confirmation.</p>

          <!-- Team name (auto, editable) -->
          <label class="block"><span class="label">Team name</span>
            <input v-model="form.team_name" class="input" placeholder="Auto-filled from player names"
              @input="teamNameEdited = true" />
            <span class="text-[11px] text-slate-400">Auto-generated from the player names — edit if you like.</span>
          </label>

          <!-- Bot check -->
          <div v-if="SITE_KEY" ref="widgetBox" class="flex justify-center"></div>

          <p v-if="errorMsg" class="text-xs text-rose-500">⚠️ {{ errorMsg }}</p>
          <button class="btn-primary w-full py-3 text-sm" :disabled="submitting" @click="submit">
            {{ submitting ? 'Submitting…' : (spotsLeft <= 0 ? 'Join the waitlist' : 'Submit registration') }}
          </button>
          <p class="text-[11px] text-slate-400 text-center">No account needed — this is a public registration form.</p>
        </div>
      </template>
    </div>
  </div>
</template>
