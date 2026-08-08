<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import Avatar from '../components/Avatar.vue'

const router = useRouter()
const { user } = useAuth()
const { currentClub } = useClub()

const messages   = ref([])          // oldest → newest
const draft      = ref('')
const loading    = ref(true)
const sending    = ref(false)
const loadingMore = ref(false)
const hasMore    = ref(true)
const showEmoji  = ref(false)
const errMsg     = ref('')

const scroller = ref(null)
const inputEl  = ref(null)
// Follow the *visible* viewport so the input stays above the on-screen keyboard
// (like WhatsApp). Fixed 100vh containers don't shrink when the keyboard opens,
// which pushes the textarea off-screen — this pins the shell to the visible area.
const viewportStyle = ref({ top: '0px', height: '100dvh' })
// Randomised, very-light badminton doodle backdrop — regenerated every time the
// chat opens so it's never the same twice. Fixed behind the scrolling messages.
const bgStyle = ref({ backgroundColor: '#eef4ff' })
let channel = null
const senderCache = new Map()       // user_id → { sender_name, avatar_url }
let myProfile = { sender_name: 'You', avatar_url: null }

const clubId   = computed(() => currentClub.value?.club_id ?? null)
const clubName = computed(() => currentClub.value?.clubs?.name ?? 'Club')

const EMOJIS = ['😀','😂','😅','😍','😎','🤝','👍','👏','🙌','💪','🔥','🎉','🏸','⏰','✅','❌','😢','🤔','🙏','❤️']

// ── Message reactions ───────────────────────────────────────────────────
const reactions = ref({})              // message_id → [{ emoji, cnt, reacted }]
const reactionPickerFor = ref(null)    // message_id currently choosing a reaction for
const REACTIONS = ['👍','❤️','😂','😮','😢','🙏','🔥','🎉']
let pressTimer = null

const fmtTime = ts => new Date(ts).toLocaleTimeString('en-AE', { hour: '2-digit', minute: '2-digit' })
const fmtDay = ts => new Date(ts).toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' })
const isMine = m => m.user_id === user.value?.id
// Show a date separator when the day changes between consecutive messages.
function showDaySep(i) {
  if (i === 0) return true
  return new Date(messages.value[i].created_at).toDateString()
       !== new Date(messages.value[i - 1].created_at).toDateString()
}

// ── Randomised badminton doodle background ──────────────────────────────
const rnd  = (a, b) => Math.random() * (b - a) + a
const pick = arr => arr[Math.floor(Math.random() * arr.length)]

// A shuttlecock drawn in local coords (~-20..20), stroke-only doodle.
const SHUTTLE = `
  <circle cx='0' cy='16' r='4.5' fill='COL' fill-opacity='OP' stroke='none'/>
  <path d='M0 12 L-14 -18 M0 12 L-7 -20 M0 12 L0 -21 M0 12 L7 -20 M0 12 L14 -18'/>
  <path d='M-14 -18 Q0 -11 14 -18'/>
  <path d='M-9 -3 Q0 1 9 -3'/>`
// A racket drawn in local coords.
const RACKET = `
  <ellipse cx='0' cy='-8' rx='12' ry='15'/>
  <path d='M-5 6 L0 9 L5 6 M0 9 L0 24'/>
  <path d='M-7 -19 L-7 3 M0 -22 L0 6 M7 -19 L7 3'/>
  <path d='M-10 -14 L10 -14 M-11 -8 L11 -8 M-10 -2 L10 -2'/>`

function makeChatBackground() {
  const col  = `hsl(${Math.round(rnd(0, 360))},58%,${Math.round(rnd(64, 74))}%)`
  const op   = rnd(0.30, 0.42).toFixed(2)
  const size = Math.round(rnd(150, 205))
  const paint = s => s.replaceAll('COL', col).replaceAll('OP', op)
  // Randomise which corner each motif sits in + its rotation, so no two opens match.
  const spots = [[52, 52], [168, 60], [58, 165], [165, 168]]
  const [a, b] = (() => { const s = [...spots].sort(() => Math.random() - 0.5); return [s[0], s[1]] })()
  const motifs = Math.random() < 0.5 ? [SHUTTLE, RACKET] : [RACKET, SHUTTLE]
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220' viewBox='0 0 220 220'>`
    + `<g stroke='${col}' stroke-opacity='${op}' fill='none' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>`
    + `<g transform='translate(${a[0]},${a[1]}) rotate(${Math.round(rnd(0, 360))}) scale(1.15)'>${paint(motifs[0])}</g>`
    + `<g transform='translate(${b[0]},${b[1]}) rotate(${Math.round(rnd(0, 360))}) scale(1.15)'>${paint(motifs[1])}</g>`
    + `<circle cx='${Math.round(rnd(95,125))}' cy='${Math.round(rnd(20,40))}' r='2' fill='${col}' fill-opacity='${op}' stroke='none'/>`
    + `<circle cx='${Math.round(rnd(20,40))}' cy='${Math.round(rnd(95,125))}' r='2' fill='${col}' fill-opacity='${op}' stroke='none'/>`
    + `</g></svg>`
  bgStyle.value = {
    backgroundColor: '#eef4ff',
    backgroundImage: `url("data:image/svg+xml,${encodeURIComponent(svg)}")`,
    backgroundSize: `${size}px ${size}px`,
  }
}

async function scrollToBottom(smooth = false) {
  await nextTick()
  const el = scroller.value
  if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? 'smooth' : 'auto' })
}

async function load() {
  if (!clubId.value) { loading.value = false; return }
  loading.value = true
  errMsg.value = ''
  // My own name/avatar for optimistic sends + labelling my messages
  const { data: prof } = await supabase.from('user_profiles')
    .select('nickname, full_name, avatar_url').eq('user_id', user.value.id).maybeSingle()
  myProfile = {
    sender_name: prof?.nickname || prof?.full_name || 'You',
    avatar_url: prof?.avatar_url ?? null,
  }
  const { data, error } = await supabase.rpc('get_club_messages', { p_club_id: clubId.value, p_limit: 40 })
  if (error) { errMsg.value = error.message; loading.value = false; return }
  messages.value = data ?? []
  hasMore.value = (data?.length ?? 0) === 40
  loading.value = false
  loadReactions((data ?? []).map(m => m.id))
  subscribe()
  scrollToBottom()
}

async function loadMore() {
  if (loadingMore.value || !hasMore.value || !messages.value.length) return
  loadingMore.value = true
  const before = messages.value[0].created_at
  const el = scroller.value
  const prevHeight = el?.scrollHeight ?? 0
  const { data } = await supabase.rpc('get_club_messages', {
    p_club_id: clubId.value, p_before: before, p_limit: 40,
  })
  const older = data ?? []
  hasMore.value = older.length === 40
  messages.value = [...older, ...messages.value]
  loadReactions(older.map(m => m.id))
  await nextTick()
  // Keep the viewport anchored where the user was after prepending older msgs
  if (el) el.scrollTop = el.scrollHeight - prevHeight
  loadingMore.value = false
}

function onScroll(e) {
  if (e.target.scrollTop < 60) loadMore()
}

function subscribe() {
  if (channel) supabase.removeChannel(channel)
  channel = supabase
    .channel(`club-chat-${clubId.value}`)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'club_messages', filter: `club_id=eq.${clubId.value}` },
      async ({ new: row }) => {
        if (messages.value.some(m => m.id === row.id)) return   // dedupe (incl. our optimistic send)
        let sender = isMine(row) ? myProfile : senderCache.get(row.user_id)
        if (!sender) {
          const { data } = await supabase.rpc('get_message_sender', { p_club_id: clubId.value, p_user_id: row.user_id })
          sender = data?.[0] ?? { sender_name: 'Player', avatar_url: null }
          senderCache.set(row.user_id, sender)
        }
        const nearBottom = scroller.value
          ? scroller.value.scrollHeight - scroller.value.scrollTop - scroller.value.clientHeight < 120
          : true
        messages.value.push({ ...row, sender_name: sender.sender_name, avatar_url: sender.avatar_url })
        if (nearBottom || isMine(row)) scrollToBottom(true)
      })
    .on('postgres_changes',
      { event: '*', schema: 'public', table: 'club_message_reactions', filter: `club_id=eq.${clubId.value}` },
      ({ new: n, old: o }) => {
        const id = n?.message_id || o?.message_id
        if (id) refreshReactionsFor(id)
      })
    .subscribe()
}

async function send() {
  const body = draft.value.trim()
  if (!body || sending.value || !clubId.value) return
  sending.value = true
  draft.value = ''
  showEmoji.value = false
  resetInputHeight()
  const { data: id, error } = await supabase.rpc('post_club_message', { p_club_id: clubId.value, p_body: body })
  sending.value = false
  if (error) { errMsg.value = error.message; draft.value = body; return }
  // Optimistic append (realtime echo is deduped by id)
  if (id && !messages.value.some(m => m.id === id)) {
    messages.value.push({
      id, user_id: user.value.id, body, created_at: new Date().toISOString(),
      sender_name: myProfile.sender_name, avatar_url: myProfile.avatar_url,
    })
    scrollToBottom(true)
  }
  // Fire push to other members (non-blocking)
  supabase.auth.getSession().then(({ data: { session } }) => {
    if (!session) return
    fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/notify-chat`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ club_id: clubId.value, body }),
    }).catch(() => {})
  })
  inputEl.value?.focus()
}

function addEmoji(e) { draft.value += e; inputEl.value?.focus(); nextTick(autoGrowNow) }

// Load aggregated reactions for a batch of message ids.
async function loadReactions(ids) {
  if (!ids?.length) return
  const { data } = await supabase.rpc('get_message_reactions', { p_message_ids: ids })
  const map = { ...reactions.value }
  for (const id of ids) map[id] = []
  for (const r of (data ?? [])) {
    (map[r.message_id] ||= []).push({ emoji: r.emoji, cnt: r.cnt, reacted: r.reacted })
  }
  reactions.value = map
}
async function refreshReactionsFor(id) {
  const { data } = await supabase.rpc('get_message_reactions', { p_message_ids: [id] })
  reactions.value = { ...reactions.value, [id]: (data ?? []).map(r => ({ emoji: r.emoji, cnt: r.cnt, reacted: r.reacted })) }
}
async function react(messageId, emoji) {
  reactionPickerFor.value = null
  await supabase.rpc('toggle_message_reaction', { p_message_id: messageId, p_emoji: emoji }).then(undefined, () => {})
  refreshReactionsFor(messageId)   // immediate for the reactor; realtime covers everyone else
}
function openReactionPicker(m) { reactionPickerFor.value = m.id }
function closeReactionPicker() { reactionPickerFor.value = null }

// Long-press (touch + mouse) opens the reaction picker, like WhatsApp.
function onPressStart(m) { clearTimeout(pressTimer); pressTimer = setTimeout(() => openReactionPicker(m), 400) }
function cancelPress() { clearTimeout(pressTimer) }

// When the textarea gains focus the keyboard animates in (~250ms); snap the
// latest messages back into view once it settles so nothing is hidden.
function onInputFocus() {
  scrollToBottom()
  setTimeout(() => scrollToBottom(true), 300)
}

// WhatsApp-style grouping: consecutive messages from the same sender within a
// few minutes (same day) collapse — one avatar/name for the group.
function isGrouped(i) {
  if (i === 0) return false
  const cur = messages.value[i], prev = messages.value[i - 1]
  return cur.user_id === prev.user_id
    && new Date(cur.created_at).toDateString() === new Date(prev.created_at).toDateString()
    && (new Date(cur.created_at) - new Date(prev.created_at)) < 5 * 60 * 1000
}

// Auto-grow the input like WhatsApp (up to ~5 lines), then it scrolls.
function autoGrowNow() {
  const el = inputEl.value
  if (!el) return
  el.style.height = 'auto'
  el.style.height = Math.min(el.scrollHeight, 120) + 'px'
}
function autoGrow() { autoGrowNow() }
function resetInputHeight() { if (inputEl.value) inputEl.value.style.height = 'auto' }

// ── Keyboard-aware sizing (VisualViewport) ──────────────────────────────
let vvRaf = 0
function syncViewport() {
  const vv = window.visualViewport
  if (!vv) return
  cancelAnimationFrame(vvRaf)
  vvRaf = requestAnimationFrame(() => {
    const wasNearBottom = scroller.value
      ? scroller.value.scrollHeight - scroller.value.scrollTop - scroller.value.clientHeight < 160
      : true
    viewportStyle.value = { top: `${vv.offsetTop}px`, height: `${vv.height}px` }
    // Keep the latest messages (and what you're typing) in view when the
    // keyboard opens and the shell shrinks.
    if (wasNearBottom) scrollToBottom()
  })
}

onMounted(() => {
  makeChatBackground()
  load()
  syncViewport()
  window.visualViewport?.addEventListener('resize', syncViewport)
  window.visualViewport?.addEventListener('scroll', syncViewport)
})
watch(clubId, load)
onBeforeUnmount(() => {
  if (channel) supabase.removeChannel(channel)
  window.visualViewport?.removeEventListener('resize', syncViewport)
  window.visualViewport?.removeEventListener('scroll', syncViewport)
  cancelAnimationFrame(vvRaf)
})
</script>

<template>
  <div class="fixed left-0 right-0 flex flex-col overflow-hidden" :style="{ ...viewportStyle, ...bgStyle }">
    <!-- Header -->
    <header class="shrink-0 flex items-center gap-3 px-3 py-2.5"
      style="background:#ffffff; border-bottom:1px solid rgba(15,23,42,.08); box-shadow:0 1px 6px rgba(0,0,0,.05);">
      <button class="w-9 h-9 rounded-xl flex items-center justify-center text-slate-500 hover:bg-slate-100 transition text-lg"
        aria-label="Back" @click="router.back()">‹</button>
      <div class="icon-tile icon-tile-cyan w-9 h-9 text-lg">💬</div>
      <div class="flex-1 min-w-0">
        <p class="font-display font-bold text-slate-800 text-sm leading-tight truncate">{{ clubName }} Chat</p>
        <p class="text-[11px] text-slate-400 leading-tight">Club members only</p>
      </div>
    </header>

    <!-- No club -->
    <div v-if="!clubId" class="flex-1 grid place-items-center px-6 text-center">
      <div>
        <div class="text-4xl mb-3">💬</div>
        <p class="text-sm text-slate-500">Select or join a club to use chat.</p>
      </div>
    </div>

    <!-- Messages -->
    <div v-else ref="scroller" class="flex-1 overflow-y-auto px-3 py-3" @scroll="onScroll">
      <div v-if="loadingMore" class="text-center text-[11px] text-slate-400 py-1">Loading earlier messages…</div>

      <div v-if="loading" class="space-y-2">
        <div v-for="i in 6" :key="i" class="h-10 shimmer rounded-xl" :class="i % 2 ? 'w-1/2' : 'w-2/3 ml-auto'" />
      </div>

      <div v-else-if="!messages.length" class="h-full grid place-items-center text-center">
        <div>
          <div class="text-4xl mb-2">👋</div>
          <p class="text-sm font-semibold text-slate-600">No messages yet</p>
          <p class="text-xs text-slate-400">Say hello to your club!</p>
        </div>
      </div>

      <template v-for="(m, i) in messages" :key="m.id">
        <!-- Day separator -->
        <div v-if="showDaySep(i)" class="flex justify-center my-2">
          <span class="text-[10px] font-semibold text-slate-500 bg-white/80 rounded-full px-3 py-1 border border-slate-200">
            {{ fmtDay(m.created_at) }}
          </span>
        </div>

        <!-- Message row -->
        <div class="flex items-end gap-2"
          :class="[isMine(m) ? 'flex-row-reverse' : '', isGrouped(i) ? 'mt-0.5' : 'mt-2']">
          <!-- Avatar once per group (others' messages); spacer keeps grouped bubbles aligned -->
          <Avatar v-if="!isMine(m) && !isGrouped(i)" :name="m.sender_name" :src="m.avatar_url" :size="26" class="shrink-0 mb-1" />
          <div v-else-if="!isMine(m)" class="w-[26px] shrink-0" aria-hidden="true"></div>

          <div class="flex flex-col max-w-[78%]" :class="isMine(m) ? 'items-end' : 'items-start'">
            <!-- Bubble: long-press to react -->
            <div class="rounded-2xl px-3 py-2 select-none cursor-pointer"
              :class="isMine(m)
                ? 'text-white rounded-br-md'
                : 'bg-white text-slate-800 rounded-bl-md border border-slate-100'"
              :style="isMine(m)
                ? 'background:linear-gradient(135deg,#00b4d8,#0088b3);-webkit-touch-callout:none;'
                : '-webkit-touch-callout:none;'"
              @touchstart.passive="onPressStart(m)" @touchend="cancelPress" @touchmove="cancelPress"
              @mousedown="onPressStart(m)" @mouseup="cancelPress" @mouseleave="cancelPress"
              @contextmenu.prevent="openReactionPicker(m)">
              <p v-if="!isMine(m) && !isGrouped(i)" class="text-[11px] font-bold mb-0.5" style="color:#0099b8;">{{ m.sender_name }}</p>
              <p class="text-sm leading-snug break-words whitespace-pre-wrap">{{ m.body }}</p>
              <p class="text-[9px] mt-0.5 text-right" :class="isMine(m) ? 'text-white/70' : 'text-slate-400'">
                {{ fmtTime(m.created_at) }}
              </p>
            </div>

            <!-- Reaction chips -->
            <div v-if="reactions[m.id]?.length" class="flex flex-wrap gap-1 mt-1">
              <button v-for="r in reactions[m.id]" :key="r.emoji" @click="react(m.id, r.emoji)"
                class="flex items-center gap-0.5 rounded-full px-1.5 py-0.5 border transition active:scale-95"
                :class="r.reacted ? 'bg-cyan-50 border-cyan-300' : 'bg-white border-slate-200'">
                <span class="text-sm leading-none">{{ r.emoji }}</span>
                <span v-if="r.cnt > 1" class="text-[11px] font-semibold" :class="r.reacted ? 'text-cyan-700' : 'text-slate-500'">{{ r.cnt }}</span>
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- Reaction picker (opens on long-press; sits above the input) -->
    <div v-if="reactionPickerFor" class="fixed inset-0 z-30" @click="closeReactionPicker"></div>
    <div v-if="clubId && reactionPickerFor"
      class="relative z-40 shrink-0 flex items-center gap-1 px-3 py-2 bg-white border-t border-slate-200"
      style="box-shadow:0 -2px 10px rgba(0,0,0,.06);">
      <span class="text-[11px] font-semibold text-slate-400 mr-1">React</span>
      <button v-for="e in REACTIONS" :key="e" class="text-2xl shrink-0 hover:scale-110 active:scale-95 transition"
        @click="react(reactionPickerFor, e)">{{ e }}</button>
      <button class="ml-auto w-7 h-7 rounded-full text-slate-400 hover:bg-slate-100 flex items-center justify-center shrink-0"
        aria-label="Close" @click="closeReactionPicker">✕</button>
    </div>

    <!-- Emoji quick bar -->
    <div v-if="clubId && showEmoji" class="shrink-0 flex gap-1 overflow-x-auto px-3 py-2 bg-white border-t border-slate-100">
      <button v-for="e in EMOJIS" :key="e" class="text-2xl shrink-0 hover:scale-110 transition" @click="addEmoji(e)">{{ e }}</button>
    </div>

    <!-- Input -->
    <div v-if="clubId" class="shrink-0 flex items-end gap-2 px-3 pt-2.5"
      style="background:#ffffff; border-top:1px solid rgba(15,23,42,.08); padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 16px);">
      <button class="w-10 h-10 rounded-full flex items-center justify-center text-xl shrink-0 hover:bg-slate-100 transition"
        aria-label="Emojis" @click="showEmoji = !showEmoji">😊</button>
      <textarea ref="inputEl" v-model="draft" rows="1" maxlength="2000"
        placeholder="Message…"
        class="input flex-1 min-w-0 resize-none max-h-28 py-2.5"
        @input="autoGrow"
        @focus="onInputFocus"
        @keydown.enter.exact.prevent="send" />
      <button class="w-10 h-10 rounded-full flex items-center justify-center shrink-0 text-white transition active:scale-95 disabled:opacity-40"
        style="background:linear-gradient(135deg,#00b4d8,#0088b3);"
        :disabled="!draft.trim() || sending" aria-label="Send" @click="send">
        <span class="text-lg leading-none">➤</span>
      </button>
    </div>

    <p v-if="errMsg" class="shrink-0 text-center text-xs text-rose-500 py-1 bg-white">{{ errMsg }}</p>
  </div>
</template>
