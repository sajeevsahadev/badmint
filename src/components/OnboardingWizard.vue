<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const emit = defineEmits(['done'])
const router = useRouter()
const { user } = useAuth()
const { loadClubs } = useClub()

// ── Step state ──────────────────────────────────────────────────────────────
const step     = ref('welcome')  // welcome | path | search | create | players | payment | done
const destPath = ref('/dashboard')

// ── Club creation ────────────────────────────────────────────────────────────
const clubInput   = ref('')
const clubErr     = ref('')
const creating    = ref(false)
const newClubId   = ref(null)
const newClubName = ref('')

// ── Club search (join path) ──────────────────────────────────────────────────
const searchQ       = ref('')
const searchResults = ref([])
const searching     = ref(false)
const requested     = ref(new Set())
const searchErr     = ref('')

// ── Player invite ────────────────────────────────────────────────────────────
// playerList items: { name, email, via: 'email'|'whatsapp'|null }
const playerList = ref([])
const pName      = ref('')
const pEmail     = ref('')
const pPhone     = ref('')
const inviting   = ref(false)
const inviteErr  = ref('')

const firstName = computed(() =>
  (user.value?.user_metadata?.full_name || '').split(' ')[0] ||
  user.value?.email?.split('@')[0] || 'Friend'
)

// ── Helpers ──────────────────────────────────────────────────────────────────
function clearPlayerForm() {
  pName.value    = ''
  pEmail.value   = ''
  pPhone.value   = ''
  inviteErr.value = ''
}

function addToList(name, email, via) {
  if (!name && !email) return
  const display = name || email.split('@')[0]
  // Don't duplicate by email
  if (email && playerList.value.find(p => p.email === email)) return
  playerList.value.push({ name: display, email: email || null, via })
}

// ── Club search ──────────────────────────────────────────────────────────────
let searchTimer = null
async function onSearch() {
  clearTimeout(searchTimer)
  if (!searchQ.value.trim()) { searchResults.value = []; return }
  searchTimer = setTimeout(async () => {
    searching.value = true
    const { data } = await supabase.rpc('get_public_clubs')
    const q = searchQ.value.toLowerCase()
    searchResults.value = (data ?? []).filter(c =>
      c.name.toLowerCase().includes(q)
    ).slice(0, 6)
    searching.value = false
  }, 300)
}

async function requestJoin(clubId) {
  const { error } = await supabase.rpc('request_join', { p_club_id: clubId })
  if (error) { searchErr.value = error.message; return }
  requested.value = new Set([...requested.value, clubId])
}

// ── Club creation ────────────────────────────────────────────────────────────
async function doCreateClub() {
  const name = clubInput.value.trim()
  if (!name) { clubErr.value = 'Please enter a club name'; return }
  clubErr.value = ''
  creating.value = true
  const { data, error } = await supabase.rpc('create_club', { p_name: name })
  creating.value = false
  if (error) { clubErr.value = error.message; return }
  newClubId.value   = data
  newClubName.value = name
  await loadClubs()
  step.value = 'players'
}

// ── Send email invite → adds to list → clears form ───────────────────────────
async function doSendEmail() {
  const email = pEmail.value.trim()
  if (!email) { inviteErr.value = 'Enter an email address to send the invite'; return }
  inviteErr.value = ''
  inviting.value = true
  try {
    const name = pName.value.trim() || email.split('@')[0]

    const { data: token, error } = await supabase.rpc('invite_member', {
      p_club_id: newClubId.value,
      p_email:   email,
    })
    if (error) throw new Error(error.message)

    const { data: { session } } = await supabase.auth.getSession()
    const resp = await fetch(
      `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/send-invite-email`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          invitee_email: email,
          invitee_name:  name,
          club_name:     newClubName.value,
          token,
        }),
      }
    )
    if (!resp.ok) {
      const err = await resp.json().catch(() => ({}))
      throw new Error(err.error || 'Failed to send email')
    }

    addToList(name, email, 'email')
    clearPlayerForm()
  } catch (e) {
    inviteErr.value = e.message
  }
  inviting.value = false
}

// ── WhatsApp share → adds to list → clears form ──────────────────────────────
async function doWhatsApp() {
  const email       = pEmail.value.trim()
  const phoneDigits = pPhone.value.replace(/\D/g, '')
  const name        = pName.value.trim() || (email ? email.split('@')[0] : `Player ${playerList.value.length + 1}`)
  let token         = null

  // If email provided, generate an invite token for a personalised link
  if (email) {
    const { data: t } = await supabase.rpc('invite_member', {
      p_club_id: newClubId.value,
      p_email:   email,
    })
    token = t
  }

  const club = newClubName.value || 'our club'
  let msg
  if (token) {
    const url = `https://badminton360.app/join?token=${token}`
    msg = `Hey ${name}! 🏸 Join ${club} on Badminton 360 — rankings, expense splits & tournaments.\nYour invite: ${url}`
  } else {
    msg = `Hey${name ? ' ' + name : ''}! 🏸 We're on Badminton 360 for ${club}.\nSign in at https://badminton360.app and search for "${club}" to join!`
  }
  // Deep-link straight to the contact's chat when a phone number was given
  const waUrl = phoneDigits
    ? `https://wa.me/${phoneDigits}?text=${encodeURIComponent(msg)}`
    : `https://wa.me/?text=${encodeURIComponent(msg)}`
  window.open(waUrl, '_blank')

  addToList(name, email, 'whatsapp')
  clearPlayerForm()
}

// ── Name-only add (no invite) ─────────────────────────────────────────────────
function doAddByName() {
  const name = pName.value.trim()
  if (!name) { inviteErr.value = 'Enter a name to add'; return }
  addToList(name, null, null)
  clearPlayerForm()
}

// ── Payment choice & finish ──────────────────────────────────────────────────
function paymentChoice(path) {
  destPath.value = path
  step.value = 'done'
}

function finish() {
  emit('done')
  router.push(destPath.value)
}
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-[200] flex items-end sm:items-center justify-center"
      style="background:rgba(5,13,26,.88); backdrop-filter:blur(8px);"
    >
      <div
        class="w-full sm:max-w-md bg-white rounded-t-3xl sm:rounded-3xl flex flex-col overflow-hidden"
        style="max-height:92dvh; box-shadow:0 24px 80px rgba(0,0,0,.45);"
      >

        <!-- ═══ WELCOME ════════════════════════════════════════════════════════ -->
        <div v-if="step === 'welcome'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#00b4d8,#9333ea,#f59e0b)" />
          <div class="flex-1 px-8 pt-10 pb-4 text-center">
            <div class="text-6xl mb-5">🏸</div>
            <h1 class="text-[1.65rem] font-extrabold text-slate-800 leading-tight mb-3">
              Welcome, {{ firstName }}!
            </h1>
            <p class="text-slate-500 text-[0.93rem] leading-relaxed mb-3">
              Badminton 360 helps your group track Elo rankings, split court costs, and run
              tournaments — all for free, forever.
            </p>
            <p class="text-slate-500 text-[0.93rem] leading-relaxed">
              Let's get your club set up in just a few steps.
            </p>
          </div>
          <div class="px-6 pb-8 pt-4 flex flex-col gap-3">
            <button
              @click="step = 'path'"
              class="w-full py-4 rounded-2xl text-[0.93rem] font-bold text-white hover:opacity-90 active:scale-[.99] transition-all"
              style="background:linear-gradient(135deg,#00b4d8,#0077a8);"
            >
              Get Started →
            </button>
            <button @click="finish()" class="text-xs text-slate-400 hover:text-slate-600 transition py-1">
              Skip setup — I'll do it later
            </button>
          </div>
        </div>

        <!-- ═══ PATH CHOICE ═══════════════════════════════════════════════════ -->
        <div v-if="step === 'path'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#9333ea,#00b4d8)" />
          <div class="px-6 pt-6 pb-4">
            <button @click="step = 'welcome'" class="text-sm text-slate-400 hover:text-slate-600 transition flex items-center gap-1 mb-5">← Back</button>
            <h2 class="text-xl font-extrabold text-slate-800 mb-1">What would you like to do?</h2>
            <p class="text-sm text-slate-500">Choose how you'd like to get started.</p>
          </div>
          <div class="px-6 pb-8 flex flex-col gap-3">
            <button
              @click="step = 'search'"
              class="w-full text-left p-5 rounded-2xl border-2 transition hover:border-cyan-400 hover:shadow-md active:scale-[.99]"
              style="border-color:rgba(0,180,216,.3); background:rgba(0,229,255,.04);"
            >
              <div class="text-3xl mb-3">🔍</div>
              <div class="font-bold text-slate-800 text-sm">Find &amp; Join an Existing Club</div>
              <div class="text-xs text-slate-500 mt-1">Search for your club and send a join request to the manager</div>
            </button>
            <button
              @click="step = 'create'"
              class="w-full text-left p-5 rounded-2xl border-2 transition hover:border-violet-400 hover:shadow-md active:scale-[.99]"
              style="border-color:rgba(147,51,234,.3); background:rgba(168,85,247,.04);"
            >
              <div class="text-3xl mb-3">🏟️</div>
              <div class="font-bold text-slate-800 text-sm">Create a New Club</div>
              <div class="text-xs text-slate-500 mt-1">Set up your group from scratch — takes about 2 minutes</div>
            </button>
          </div>
        </div>

        <!-- ═══ SEARCH / JOIN ════════════════════════════════════════════════ -->
        <div v-if="step === 'search'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#00b4d8,#0077a8)" />
          <div class="px-6 pt-6 pb-4 shrink-0">
            <button @click="step = 'path'" class="text-sm text-slate-400 hover:text-slate-600 transition flex items-center gap-1 mb-5">← Back</button>
            <h2 class="text-xl font-extrabold text-slate-800 mb-1">Find Your Club</h2>
            <p class="text-sm text-slate-500">Search by club name. The manager will approve your request.</p>
          </div>
          <div class="px-6 flex flex-col gap-3 overflow-y-auto flex-1 pb-4">
            <div class="relative">
              <input
                v-model="searchQ"
                @input="onSearch"
                type="text"
                placeholder="Type your club name…"
                class="w-full pl-10 pr-4 py-3 rounded-xl text-sm border text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-cyan-300"
                style="border-color:rgba(0,0,0,.13);"
              />
              <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base pointer-events-none">🔍</span>
            </div>
            <div v-if="searching" class="text-center py-8 text-sm text-slate-400 animate-pulse">Searching…</div>
            <div v-if="!searching" class="flex flex-col gap-2">
              <div
                v-for="club in searchResults"
                :key="club.id"
                class="flex items-center justify-between gap-3 p-4 rounded-xl border"
                style="border-color:rgba(0,0,0,.08); background:#fafafa;"
              >
                <div class="min-w-0">
                  <div class="font-semibold text-slate-800 text-sm truncate">{{ club.name }}</div>
                  <div class="text-xs text-slate-400 mt-0.5">{{ club.member_count }} member{{ club.member_count !== 1 ? 's' : '' }}</div>
                </div>
                <button
                  @click="requestJoin(club.id)"
                  :disabled="requested.has(club.id)"
                  class="shrink-0 px-4 py-2 rounded-xl text-xs font-bold transition-all"
                  :style="requested.has(club.id)
                    ? 'background:#dcfce7;color:#166534;'
                    : 'background:linear-gradient(135deg,#00b4d8,#0077a8);color:#fff;'"
                >
                  {{ requested.has(club.id) ? '✓ Requested' : 'Request to Join' }}
                </button>
              </div>
              <p v-if="searchErr" class="text-center py-2 text-xs text-rose-500">⚠ {{ searchErr }}</p>
              <p v-if="searchQ.trim() && !searchResults.length" class="text-center py-6 text-sm text-slate-400">
                No clubs found for "{{ searchQ }}"
              </p>
            </div>
          </div>
          <div class="px-6 pb-6 shrink-0 border-t pt-4" style="border-color:rgba(0,0,0,.07);">
            <button
              @click="destPath = '/explore'; finish()"
              class="w-full py-3 rounded-xl text-sm font-semibold border transition hover:bg-slate-50"
              style="border-color:rgba(0,0,0,.12); color:#475569;"
            >
              Browse all clubs in Explore →
            </button>
            <button @click="finish()" class="w-full text-xs text-slate-400 hover:text-slate-600 transition py-2 mt-1">
              Done for now
            </button>
          </div>
        </div>

        <!-- ═══ CREATE CLUB ══════════════════════════════════════════════════ -->
        <div v-if="step === 'create'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#9333ea,#7c3aed)" />
          <div class="px-6 pt-6 pb-4">
            <button @click="step = 'path'" class="text-sm text-slate-400 hover:text-slate-600 transition flex items-center gap-1 mb-5">← Back</button>
            <div class="text-[10px] uppercase tracking-widest text-slate-400 font-semibold mb-4">Step 1 of 3</div>
            <h2 class="text-xl font-extrabold text-slate-800 mb-1">Name Your Club</h2>
            <p class="text-sm text-slate-500">Pick something your crew will recognise. You can change it later.</p>
          </div>
          <div class="px-6 flex-1 flex flex-col gap-4">
            <input
              v-model="clubInput"
              @keyup.enter="doCreateClub"
              type="text"
              placeholder="e.g. Dev's Saturday Crew"
              class="w-full px-4 py-3.5 rounded-xl text-sm border text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-violet-300"
              style="border-color:rgba(147,51,234,.3);"
              :disabled="creating"
              autofocus
            />
            <p v-if="clubErr" class="text-xs text-rose-500 -mt-2">{{ clubErr }}</p>
            <div class="text-xs text-slate-500 bg-slate-50 rounded-xl p-4 space-y-1.5">
              <div>✅ You're automatically added as <strong class="text-slate-700">Club Owner</strong></div>
              <div>✅ Invite your crew by email or WhatsApp in the next step</div>
              <div>✅ Elo rankings start for everyone at 1000 — totally fair</div>
            </div>
          </div>
          <div class="px-6 pb-8 pt-4">
            <button
              @click="doCreateClub"
              :disabled="creating"
              class="w-full py-4 rounded-2xl text-[0.93rem] font-bold text-white hover:opacity-90 active:scale-[.99] transition-all disabled:opacity-60"
              style="background:linear-gradient(135deg,#9333ea,#7c3aed);"
            >
              {{ creating ? 'Creating…' : '🏟️ Create Club →' }}
            </button>
          </div>
        </div>

        <!-- ═══ ADD PLAYERS ══════════════════════════════════════════════════ -->
        <div v-if="step === 'players'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#f59e0b,#d97706)" />

          <!-- Header -->
          <div class="px-6 pt-6 pb-3 shrink-0">
            <div class="flex items-center justify-between mb-4">
              <div class="text-[10px] uppercase tracking-widest text-slate-400 font-semibold">Step 2 of 3</div>
              <div class="w-28 h-1.5 rounded-full overflow-hidden" style="background:#f1f5f9;">
                <div class="h-full rounded-full" style="width:66%;background:linear-gradient(90deg,#f59e0b,#d97706);" />
              </div>
            </div>
            <h2 class="text-xl font-extrabold text-slate-800 mb-1">Invite Your Crew</h2>
            <p class="text-sm text-slate-500">
              {{ playerList.length ? `${playerList.length} player${playerList.length !== 1 ? 's' : ''} added · Keep going or tap Done` : 'Fill in details and tap Send — player is added instantly.' }}
            </p>
          </div>

          <!-- Player chips (invited list) -->
          <div v-if="playerList.length" class="px-6 pb-3 shrink-0">
            <div class="flex flex-wrap gap-1.5">
              <div
                v-for="p in playerList"
                :key="p.email ?? p.name"
                class="flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium"
                style="background:#f0fdf4; color:#166534; border:1px solid #bbf7d0;"
              >
                <span>{{ p.via === 'email' ? '📧' : p.via === 'whatsapp' ? '💬' : '👤' }}</span>
                <span>{{ p.name }}</span>
              </div>
            </div>
          </div>

          <!-- Divider if players added -->
          <div v-if="playerList.length" class="mx-6 mb-3 border-t shrink-0" style="border-color:rgba(0,0,0,.06);" />

          <!-- Form -->
          <div class="px-6 flex flex-col gap-3 overflow-y-auto flex-1">

            <div>
              <label class="text-[10px] font-bold uppercase tracking-widest text-slate-400 mb-1.5 block">
                Name <span class="normal-case font-normal">(optional)</span>
              </label>
              <input
                v-model="pName"
                type="text"
                placeholder="e.g. Anil Kumar"
                class="w-full px-4 py-3 rounded-xl text-sm border text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-300"
                style="border-color:rgba(0,0,0,.12);"
              />
            </div>

            <div>
              <label class="text-[10px] font-bold uppercase tracking-widest text-slate-400 mb-1.5 block">
                Email Address
              </label>
              <input
                v-model="pEmail"
                type="email"
                placeholder="anil@gmail.com"
                class="w-full px-4 py-3 rounded-xl text-sm border text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-300"
                style="border-color:rgba(0,0,0,.12);"
              />
            </div>

            <div>
              <label class="text-[10px] font-bold uppercase tracking-widest text-slate-400 mb-1.5 block">
                Phone / WhatsApp <span class="normal-case font-normal text-slate-400">(optional)</span>
              </label>
              <input
                v-model="pPhone"
                type="tel"
                placeholder="+971 50 000 0000"
                class="w-full px-4 py-3 rounded-xl text-sm border text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-300"
                style="border-color:rgba(0,0,0,.12);"
              />
            </div>

            <!-- Primary invite actions — each sends + saves + clears form -->
            <div class="flex gap-2 pt-1">
              <button
                @click="doSendEmail"
                :disabled="inviting"
                class="flex-1 py-3.5 rounded-xl text-sm font-bold text-white transition-all hover:opacity-90 active:scale-[.99] disabled:opacity-60"
                style="background:linear-gradient(135deg,#00b4d8,#0077a8);"
              >
                {{ inviting ? 'Sending…' : '📧 Send Email & Add' }}
              </button>
              <button
                @click="doWhatsApp"
                :disabled="inviting"
                class="flex-1 py-3.5 rounded-xl text-sm font-bold transition-all hover:opacity-90 active:scale-[.99] disabled:opacity-60"
                style="background:#dcfce7; color:#166534; border:2px solid #bbf7d0;"
              >
                💬 WhatsApp & Add
              </button>
            </div>

            <!-- Tertiary: add name only -->
            <button
              @click="doAddByName"
              class="w-full py-2.5 rounded-xl text-sm font-medium border border-dashed transition hover:bg-slate-50"
              style="border-color:rgba(0,0,0,.15); color:#64748b;"
            >
              + Add by name only (no invite)
            </button>

            <p v-if="inviteErr" class="text-xs text-rose-500">⚠ {{ inviteErr }}</p>
          </div>

          <!-- Done button (pinned) -->
          <div class="px-6 pb-6 pt-4 shrink-0 border-t" style="border-color:rgba(0,0,0,.07);">
            <button
              @click="step = 'payment'"
              class="w-full py-3.5 rounded-2xl text-sm font-bold text-white transition hover:opacity-90 active:scale-[.99]"
              style="background:linear-gradient(135deg,#f59e0b,#d97706);"
            >
              {{ playerList.length ? `Done — ${playerList.length} player${playerList.length !== 1 ? 's' : ''} added →` : 'Skip — I\'ll add players later →' }}
            </button>
          </div>
        </div>

        <!-- ═══ PAYMENT SETUP ════════════════════════════════════════════════ -->
        <div v-if="step === 'payment'" class="flex flex-col overflow-y-auto">
          <div class="h-1.5 shrink-0" style="background:linear-gradient(90deg,#00b4d8,#9333ea,#f59e0b)" />
          <div class="px-6 pt-6 pb-4 shrink-0">
            <div class="flex items-center justify-between mb-4">
              <div class="text-[10px] uppercase tracking-widest text-slate-400 font-semibold">Step 3 of 3</div>
              <div class="w-28 h-1.5 rounded-full overflow-hidden" style="background:#f1f5f9;">
                <div class="h-full rounded-full" style="width:100%;background:linear-gradient(90deg,#00b4d8,#9333ea,#f59e0b);" />
              </div>
            </div>
            <h2 class="text-xl font-extrabold text-slate-800 mb-1">How does your group manage costs?</h2>
            <p class="text-sm text-slate-500">We'll set up PaySplits to match your style.</p>
          </div>
          <div class="px-6 flex flex-col gap-3 overflow-y-auto flex-1 pb-4">
            <button
              @click="paymentChoice('/splits?tab=wallet')"
              class="w-full text-left p-4 rounded-2xl border-2 transition hover:border-amber-400 hover:shadow-sm active:scale-[.99]"
              style="border-color:rgba(245,158,11,.25); background:rgba(251,191,36,.04);"
            >
              <div class="flex items-start gap-3">
                <span class="text-2xl shrink-0 mt-0.5">💰</span>
                <div>
                  <div class="font-bold text-slate-800 text-sm">Club Wallet — Pre-collect Money</div>
                  <div class="text-xs text-slate-500 mt-1 leading-relaxed">Players contribute upfront. Auto-deduct per session. No more chasing payments.</div>
                </div>
              </div>
            </button>
            <button
              @click="paymentChoice('/splits?tab=activities')"
              class="w-full text-left p-4 rounded-2xl border-2 transition hover:border-cyan-400 hover:shadow-sm active:scale-[.99]"
              style="border-color:rgba(0,180,216,.25); background:rgba(0,229,255,.03);"
            >
              <div class="flex items-start gap-3">
                <span class="text-2xl shrink-0 mt-0.5">⚖️</span>
                <div>
                  <div class="font-bold text-slate-800 text-sm">Split After Each Session</div>
                  <div class="text-xs text-slate-500 mt-1 leading-relaxed">Record expenses and split equally. Track who owes what at a glance.</div>
                </div>
              </div>
            </button>
            <button
              @click="paymentChoice('/splits?tab=balance')"
              class="w-full text-left p-4 rounded-2xl border-2 transition hover:border-violet-400 hover:shadow-sm active:scale-[.99]"
              style="border-color:rgba(147,51,234,.25); background:rgba(168,85,247,.03);"
            >
              <div class="flex items-start gap-3">
                <span class="text-2xl shrink-0 mt-0.5">🔄</span>
                <div>
                  <div class="font-bold text-slate-800 text-sm">Migrating From Another App?</div>
                  <div class="text-xs text-slate-500 mt-1 leading-relaxed">Set opening balances to carry over amounts from your previous system.</div>
                </div>
              </div>
            </button>
          </div>
          <div class="px-6 pb-6 shrink-0">
            <button @click="paymentChoice('/dashboard')" class="w-full text-sm text-slate-400 hover:text-slate-600 transition py-2">
              Set up later → Go to Dashboard
            </button>
          </div>
        </div>

        <!-- ═══ DONE ══════════════════════════════════════════════════════════ -->
        <div v-if="step === 'done'" class="flex flex-col items-center text-center overflow-y-auto">
          <div class="h-1.5 w-full shrink-0" style="background:linear-gradient(90deg,#22c55e,#16a34a)" />
          <div class="flex-1 px-8 pt-10 pb-4 w-full">
            <div class="text-6xl mb-4">🎉</div>
            <h2 class="text-2xl font-extrabold text-slate-800 mb-2 leading-tight">
              {{ newClubName ? newClubName + ' is all set!' : "You're all set!" }}
            </h2>
            <p class="text-slate-500 text-sm leading-relaxed mb-8">Your club is ready. Record your first match and let the rankings begin!</p>
            <div class="text-left space-y-2.5 mb-6">
              <div class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium" style="background:#f0fdf4; color:#166534;">
                <span>✅</span><span>Club created — you're the <strong>owner</strong></span>
              </div>
              <div v-if="playerList.length" class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium" style="background:#f0fdf4; color:#166534;">
                <span>✅</span>
                <span>{{ playerList.filter(p => p.via === 'email').length }} email invite{{ playerList.filter(p => p.via === 'email').length !== 1 ? 's' : '' }} sent · {{ playerList.length }} player{{ playerList.length !== 1 ? 's' : '' }} added</span>
              </div>
              <div class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium" style="background:#f0fdf4; color:#166534;">
                <span>✅</span><span>Elo rankings start at 1000 — fair for everyone</span>
              </div>
            </div>
          </div>
          <div class="px-6 pb-10 w-full">
            <button
              @click="finish()"
              class="w-full py-4 rounded-2xl text-[0.93rem] font-bold text-white hover:opacity-90 active:scale-[.99] transition-all"
              style="background:linear-gradient(135deg,#22c55e,#16a34a);"
            >
              Let's Play! 🏸
            </button>
          </div>
        </div>

      </div>
    </div>
  </Teleport>
</template>
