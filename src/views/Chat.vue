<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount, watch } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import Avatar from '../components/Avatar.vue'

const router = useRouter()
const { user } = useAuth()
const { currentClub, clubs, isManager } = useClub()

const messages   = ref([])          // oldest → newest
const draft      = ref('')
const loading    = ref(true)
const sending    = ref(false)
const loadingMore = ref(false)
const hasMore    = ref(true)
const showEmoji  = ref(false)
const errMsg     = ref('')

// ── Message actions (reply / forward / star / delete) ───────────────────
const replyTo         = ref(null)   // message being replied to
const actionMenuFor   = ref(null)   // message whose action sheet is open
const forwardMsg      = ref(null)   // message being forwarded (opens club picker)
const forwarding      = ref(false)
const deleteMsg       = ref(null)   // message pending delete confirmation
const showStarredOnly = ref(false)
const infoFor         = ref(null)   // message whose read-receipt info is open
const infoRows        = ref([])
const infoLoading     = ref(false)
const fileInput       = ref(null)   // hidden <input type=file>
const uploadingImage  = ref(false)
const lightbox        = ref(null)   // full-screen image url

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
const canDelete = m => isMine(m) || isManager()

// The list actually rendered (optionally filtered to starred).
const visibleMessages = computed(() =>
  showStarredOnly.value ? messages.value.filter(m => m.starred) : messages.value)

// Show a date separator when the day changes between consecutive messages.
function showDaySep(list, i) {
  if (i === 0) return true
  return new Date(list[i].created_at).toDateString()
       !== new Date(list[i - 1].created_at).toDateString()
}

// ── Randomised badminton doodle background ──────────────────────────────
const rnd  = (a, b) => Math.random() * (b - a) + a

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
  markRead()
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
        // Resolve the reply preview from a message we already have loaded.
        const replied = row.reply_to ? messages.value.find(m => m.id === row.reply_to) : null
        messages.value.push({
          ...row,
          sender_name: sender.sender_name, avatar_url: sender.avatar_url,
          reply_sender: replied ? replied.sender_name : null,
          reply_body: replied ? (replied.deleted ? 'Deleted message' : (replied.body || (replied.image_url ? '📷 Photo' : ''))) : null,
          deleted: false, starred: false,
        })
        if (nearBottom || isMine(row)) scrollToBottom(true)
        if (!isMine(row)) markRead()   // reading it live keeps unread at 0
      })
    .on('postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'club_messages', filter: `club_id=eq.${clubId.value}` },
      ({ new: row }) => {
        const idx = messages.value.findIndex(m => m.id === row.id)
        if (idx !== -1 && row.deleted_at && !messages.value[idx].deleted) {
          messages.value[idx] = { ...messages.value[idx], deleted: true, body: null }
          reactions.value = { ...reactions.value, [row.id]: [] }
        }
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
  const replied = replyTo.value
  replyTo.value = null
  const { data: id, error } = await supabase.rpc('post_club_message', {
    p_club_id: clubId.value, p_body: body, p_reply_to: replied?.id ?? null,
  })
  sending.value = false
  if (error) { errMsg.value = error.message; draft.value = body; return }
  // Optimistic append (realtime echo is deduped by id)
  if (id && !messages.value.some(m => m.id === id)) {
    messages.value.push({
      id, user_id: user.value.id, body, created_at: new Date().toISOString(),
      sender_name: myProfile.sender_name, avatar_url: myProfile.avatar_url,
      reply_to: replied?.id ?? null,
      reply_sender: replied ? (isMine(replied) ? myProfile.sender_name : replied.sender_name) : null,
      reply_body: replied ? (replied.deleted ? 'Deleted message' : replied.body) : null,
      is_forwarded: false, deleted: false, starred: false,
    })
    scrollToBottom(true)
  }
  fireChatPush(clubId.value, body)
  inputEl.value?.focus()
}

// Fire a chat push to a club's other members (non-blocking).
function fireChatPush(targetClubId, body) {
  supabase.auth.getSession().then(({ data: { session } }) => {
    if (!session) return
    fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/notify-chat`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ club_id: targetClubId, body }),
    }).catch(() => {})
  })
}

// ── Image messages (compress → R2 presigned upload → post) ──────────────
// Shrink to ~1600px WebP so a 4 MB phone photo becomes ~120 KB before upload.
async function compressImage(file, maxDim = 1600, quality = 0.72) {
  let bmp = null
  try { bmp = await createImageBitmap(file, { imageOrientation: 'from-image' }) } catch { /* fallback below */ }
  const src = bmp || await new Promise((res, rej) => {
    const img = new Image(); img.onload = () => res(img); img.onerror = rej
    img.src = URL.createObjectURL(file)
  })
  let w = src.width, h = src.height
  const scale = Math.min(1, maxDim / Math.max(w, h))
  w = Math.round(w * scale); h = Math.round(h * scale)
  const canvas = document.createElement('canvas')
  canvas.width = w; canvas.height = h
  canvas.getContext('2d').drawImage(src, 0, 0, w, h)
  bmp?.close?.()
  const blob = await new Promise(r => canvas.toBlob(r, 'image/webp', quality))
  if (!blob) throw new Error('Could not process image')
  return { blob, width: w, height: h }
}

async function getUploadUrl() {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Not signed in')
  const resp = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/r2-upload-url`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ club_id: clubId.value }),
  })
  if (!resp.ok) throw new Error('Could not start upload')
  return await resp.json()
}

function pickImage() { fileInput.value?.click() }
async function onPickImage(e) {
  const file = e.target.files?.[0]
  e.target.value = ''            // allow re-picking the same file
  if (!file || !clubId.value) return
  if (!file.type.startsWith('image/')) { errMsg.value = 'Only images can be sent.'; return }
  if (file.size > 25 * 1024 * 1024) { errMsg.value = 'Image is too large (max 25 MB).'; return }
  uploadingImage.value = true
  errMsg.value = ''
  const replied = replyTo.value
  try {
    const { blob, width, height } = await compressImage(file)
    const { uploadUrl, publicUrl } = await getUploadUrl()
    const put = await fetch(uploadUrl, { method: 'PUT', headers: { 'Content-Type': 'image/webp' }, body: blob })
    if (!put.ok) throw new Error('Upload failed — please retry')
    replyTo.value = null
    const { data: id, error } = await supabase.rpc('post_club_message', {
      p_club_id: clubId.value, p_body: null, p_reply_to: replied?.id ?? null,
      p_image_url: publicUrl, p_image_w: width, p_image_h: height,
    })
    if (error) throw new Error(error.message)
    if (id && !messages.value.some(m => m.id === id)) {
      messages.value.push({
        id, user_id: user.value.id, body: null, created_at: new Date().toISOString(),
        sender_name: myProfile.sender_name, avatar_url: myProfile.avatar_url,
        reply_to: replied?.id ?? null,
        reply_sender: replied ? (isMine(replied) ? myProfile.sender_name : replied.sender_name) : null,
        reply_body: replied ? (replied.deleted ? 'Deleted message' : (replied.body || '📷 Photo')) : null,
        is_forwarded: false, deleted: false, starred: false,
        image_url: publicUrl, image_w: width, image_h: height,
      })
      scrollToBottom(true)
    }
    fireChatPush(clubId.value, '📷 Photo')
  } catch (err) {
    errMsg.value = err.message || 'Could not send image'
  }
  uploadingImage.value = false
}

// ── Action sheet (long-press) ───────────────────────────────────────────
function openActionMenu(m) { if (!m.deleted) actionMenuFor.value = m }
function closeActionMenu() { actionMenuFor.value = null }

// Message info (read receipts) — author only
const fmtDateTime = ts => new Date(ts).toLocaleString('en-AE', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
const readRows      = computed(() => infoRows.value.filter(r => r.status === 'read'))
const deliveredRows = computed(() => infoRows.value.filter(r => r.status === 'delivered'))
const sentRows      = computed(() => infoRows.value.filter(r => r.status === 'sent'))
async function openInfo(m) {
  actionMenuFor.value = null
  infoFor.value = m
  infoLoading.value = true
  infoRows.value = []
  const { data, error } = await supabase.rpc('get_message_info', { p_message_id: m.id })
  infoLoading.value = false
  if (error) { errMsg.value = error.message; infoFor.value = null; return }
  infoRows.value = data ?? []
}
function closeInfo() { infoFor.value = null }

// Reply
function startReply(m) { replyTo.value = m; actionMenuFor.value = null; nextTick(() => inputEl.value?.focus()) }
function cancelReply() { replyTo.value = null }

// Star / unstar
async function toggleStar(m) {
  actionMenuFor.value = null
  const { data } = await supabase.rpc('toggle_message_star', { p_message_id: m.id })
  const idx = messages.value.findIndex(x => x.id === m.id)
  if (idx !== -1) messages.value[idx] = { ...messages.value[idx], starred: !!data }
}

// Forward → opens the club picker
const forwardTargets = computed(() => (clubs.value ?? []).filter(c => c.club_id !== clubId.value))
function startForward(m) { forwardMsg.value = m; actionMenuFor.value = null }
function cancelForward() { forwardMsg.value = null }
async function doForward(targetClubId) {
  if (forwarding.value || !forwardMsg.value) return
  forwarding.value = true
  const src = forwardMsg.value
  const { error } = await supabase.rpc('post_club_message', {
    p_club_id: targetClubId, p_body: src.body, p_reply_to: null, p_is_forwarded: true,
    p_image_url: src.image_url ?? null, p_image_w: src.image_w ?? null, p_image_h: src.image_h ?? null,
  })
  forwarding.value = false
  const target = (clubs.value ?? []).find(c => c.club_id === targetClubId)
  forwardMsg.value = null
  if (error) { errMsg.value = error.message; return }
  fireChatPush(targetClubId, src.body || '📷 Photo')
  errMsg.value = ''
  // Brief confirmation
  const name = target?.clubs?.name ?? 'club'
  errMsg.value = `↪ Forwarded to ${name}`
  setTimeout(() => { if (errMsg.value.startsWith('↪')) errMsg.value = '' }, 2500)
}

// Delete (soft)
function askDelete(m) { deleteMsg.value = m; actionMenuFor.value = null }
function cancelDelete() { deleteMsg.value = null }
async function doDelete() {
  const m = deleteMsg.value
  deleteMsg.value = null
  if (!m) return
  const { error } = await supabase.rpc('delete_club_message', { p_message_id: m.id })
  if (error) { errMsg.value = error.message; return }
  const idx = messages.value.findIndex(x => x.id === m.id)
  if (idx !== -1) messages.value[idx] = { ...messages.value[idx], deleted: true, body: null }
  reactions.value = { ...reactions.value, [m.id]: [] }
}

// Mark this club's chat as read for the current user (clears the unread badge).
function markRead() {
  if (clubId.value) supabase.rpc('mark_chat_read', { p_club_id: clubId.value }).then(undefined, () => {})
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
  const { data: result } = await supabase.rpc('toggle_message_reaction', { p_message_id: messageId, p_emoji: emoji })
    .then(r => r, () => ({ data: null }))
  refreshReactionsFor(messageId)   // immediate for the reactor; realtime covers everyone else
  // Push the message author when a reaction is ADDED/swapped (result = emoji), not removed (null)
  if (result) {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) return
      fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/notify-reaction`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message_id: messageId, emoji: result }),
      }).catch(() => {})
    })
  }
}
function openReactionPicker(m) { actionMenuFor.value = null; reactionPickerFor.value = m.id }
function closeReactionPicker() { reactionPickerFor.value = null }

// Long-press (touch + mouse) opens the message action sheet, like WhatsApp.
function onPressStart(m) { clearTimeout(pressTimer); pressTimer = setTimeout(() => openActionMenu(m), 400) }
function cancelPress() { clearTimeout(pressTimer) }

// Touch devices (phones/tablets): Enter should insert a newline, and the send
// button posts — like WhatsApp. Desktop: Enter sends, Shift+Enter = newline.
const isTouch = typeof window !== 'undefined'
  && (window.matchMedia?.('(pointer: coarse)').matches || 'ontouchstart' in window)
function onEnterKey(e) {
  if (isTouch || e.shiftKey || e.isComposing) return   // allow the default newline
  e.preventDefault()
  send()
}

// When the textarea gains focus the keyboard animates in (~250ms); snap the
// latest messages back into view once it settles so nothing is hidden.
function onInputFocus() {
  scrollToBottom()
  setTimeout(() => scrollToBottom(true), 300)
}

// WhatsApp-style grouping: consecutive messages from the same sender within a
// few minutes (same day) collapse — one avatar/name for the group.
function isGrouped(list, i) {
  if (i === 0) return false
  const cur = list[i], prev = list[i - 1]
  return cur.user_id === prev.user_id
    && !cur.reply_to                       // replies always show their own header
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
  markRead()
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
        <p class="text-[11px] text-slate-400 leading-tight">{{ showStarredOnly ? 'Showing starred' : 'Club members only' }}</p>
      </div>
      <button v-if="clubId" class="w-9 h-9 rounded-xl flex items-center justify-center text-lg shrink-0 transition"
        :class="showStarredOnly ? 'bg-amber-100 text-amber-600' : 'text-slate-400 hover:bg-slate-100'"
        :aria-label="showStarredOnly ? 'Show all messages' : 'Show starred only'"
        @click="showStarredOnly = !showStarredOnly">{{ showStarredOnly ? '★' : '☆' }}</button>
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

      <div v-else-if="showStarredOnly && !visibleMessages.length" class="h-full grid place-items-center text-center">
        <div>
          <div class="text-4xl mb-2">⭐</div>
          <p class="text-sm font-semibold text-slate-600">No starred messages</p>
          <p class="text-xs text-slate-400">Long-press a message and tap Star.</p>
        </div>
      </div>

      <template v-for="(m, i) in visibleMessages" :key="m.id">
        <!-- Day separator -->
        <div v-if="showDaySep(visibleMessages, i)" class="flex justify-center my-2">
          <span class="text-[10px] font-semibold text-slate-500 bg-white/80 rounded-full px-3 py-1 border border-slate-200">
            {{ fmtDay(m.created_at) }}
          </span>
        </div>

        <!-- Message row -->
        <div class="flex items-end gap-2"
          :class="[isMine(m) ? 'flex-row-reverse' : '', isGrouped(visibleMessages, i) ? 'mt-0.5' : 'mt-2']">
          <!-- Avatar once per group (others' messages); spacer keeps grouped bubbles aligned -->
          <Avatar v-if="!isMine(m) && !isGrouped(visibleMessages, i)" :name="m.sender_name" :src="m.avatar_url" :size="26" class="shrink-0 mb-1" />
          <div v-else-if="!isMine(m)" class="w-[26px] shrink-0" aria-hidden="true"></div>

          <div class="flex flex-col max-w-[78%]" :class="isMine(m) ? 'items-end' : 'items-start'">
            <!-- Deleted placeholder -->
            <div v-if="m.deleted" class="rounded-2xl px-3 py-2 bg-white/70 border border-slate-100 text-slate-400 italic text-sm flex items-center gap-1.5">
              🚫 This message was deleted
            </div>

            <!-- Bubble: long-press for actions -->
            <div v-else class="rounded-2xl px-3 py-2 select-none cursor-pointer"
              :class="isMine(m)
                ? 'text-white rounded-br-md'
                : 'bg-white text-slate-800 rounded-bl-md border border-slate-100'"
              :style="isMine(m)
                ? 'background:linear-gradient(135deg,#00b4d8,#0088b3);-webkit-touch-callout:none;'
                : '-webkit-touch-callout:none;'"
              @touchstart.passive="onPressStart(m)" @touchend="cancelPress" @touchmove="cancelPress"
              @mousedown="onPressStart(m)" @mouseup="cancelPress" @mouseleave="cancelPress"
              @contextmenu.prevent="openActionMenu(m)">
              <p v-if="!isMine(m) && !isGrouped(visibleMessages, i)" class="text-[11px] font-bold mb-0.5" style="color:#0099b8;">{{ m.sender_name }}</p>
              <p v-if="m.is_forwarded" class="text-[10px] italic mb-0.5 flex items-center gap-1"
                 :class="isMine(m) ? 'text-white/70' : 'text-slate-400'">↪ Forwarded</p>
              <!-- Reply quote -->
              <div v-if="m.reply_to && m.reply_sender" class="rounded-lg px-2 py-1 mb-1 border-l-2 text-[11px] leading-snug"
                :class="isMine(m) ? 'bg-white/15 border-white/60' : 'bg-slate-50 border-cyan-400'">
                <span class="font-bold block" :class="isMine(m) ? 'text-white/90' : 'text-cyan-700'">{{ m.reply_sender }}</span>
                <span class="line-clamp-2 opacity-80">{{ m.reply_body }}</span>
              </div>
              <img v-if="m.image_url" :src="m.image_url" :width="m.image_w" :height="m.image_h"
                class="rounded-xl max-w-[240px] max-h-[320px] w-auto h-auto block cursor-pointer mb-1"
                loading="lazy" alt="photo" @click.stop="lightbox = m.image_url" />
              <p v-if="m.body" class="text-sm leading-snug break-words whitespace-pre-wrap">{{ m.body }}</p>
              <p class="text-[9px] mt-0.5 flex items-center gap-1 justify-end" :class="isMine(m) ? 'text-white/70' : 'text-slate-400'">
                <span v-if="m.starred" class="text-amber-400">★</span>
                {{ fmtTime(m.created_at) }}
              </p>
            </div>

            <!-- Reaction chips -->
            <div v-if="!m.deleted && reactions[m.id]?.length" class="flex flex-wrap gap-1 mt-1">
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

    <!-- Uploading a photo -->
    <div v-if="clubId && uploadingImage" class="shrink-0 flex items-center gap-2 px-3 py-2 bg-white border-t border-slate-100 text-xs text-slate-500">
      <span class="w-3.5 h-3.5 rounded-full border-2 border-slate-300 border-t-cyan-500 animate-spin"></span>
      Compressing &amp; sending photo…
    </div>

    <!-- Reply preview (above input) -->
    <div v-if="clubId && replyTo" class="shrink-0 flex items-center gap-2 px-3 py-2 bg-white border-t border-slate-200">
      <div class="w-1 self-stretch rounded-full bg-cyan-400 shrink-0"></div>
      <div class="flex-1 min-w-0">
        <p class="text-[11px] font-bold text-cyan-700 leading-tight">Replying to {{ isMine(replyTo) ? 'yourself' : replyTo.sender_name }}</p>
        <p class="text-xs text-slate-500 truncate">{{ replyTo.body }}</p>
      </div>
      <button class="w-7 h-7 rounded-full text-slate-400 hover:bg-slate-100 flex items-center justify-center shrink-0"
        aria-label="Cancel reply" @click="cancelReply">✕</button>
    </div>

    <!-- Input -->
    <div v-if="clubId" class="shrink-0 flex items-end gap-2 px-3 pt-2.5"
      style="background:#ffffff; border-top:1px solid rgba(15,23,42,.08); padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 16px);">
      <button class="w-10 h-10 rounded-full flex items-center justify-center text-xl shrink-0 hover:bg-slate-100 transition"
        aria-label="Emojis" @click="showEmoji = !showEmoji">😊</button>
      <input ref="fileInput" type="file" accept="image/*" class="hidden" @change="onPickImage" />
      <button class="w-10 h-10 rounded-full flex items-center justify-center shrink-0 hover:bg-slate-100 transition disabled:opacity-40"
        aria-label="Add photo" :disabled="uploadingImage" @click="pickImage">
        <svg viewBox="0 0 24 24" class="w-[22px] h-[22px] text-slate-500" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="4" width="18" height="16" rx="3.5"/>
          <circle cx="8.5" cy="9.5" r="1.6"/>
          <path d="M20.5 15.5 16 11l-8.5 8.5"/>
        </svg>
      </button>
      <textarea ref="inputEl" v-model="draft" rows="1" maxlength="2000"
        placeholder="Message…"
        class="input flex-1 min-w-0 resize-none max-h-28 py-2.5"
        @input="autoGrow"
        @focus="onInputFocus"
        @keydown.enter="onEnterKey" />
      <button class="w-10 h-10 rounded-full flex items-center justify-center shrink-0 text-white transition active:scale-95 disabled:opacity-40"
        style="background:linear-gradient(135deg,#00b4d8,#0088b3);"
        :disabled="!draft.trim() || sending" aria-label="Send" @click="send">
        <span class="text-lg leading-none">➤</span>
      </button>
    </div>

    <p v-if="errMsg" class="shrink-0 text-center text-xs py-1 bg-white"
       :class="errMsg.startsWith('↪') ? 'text-emerald-600' : 'text-rose-500'">{{ errMsg }}</p>

    <!-- Action sheet (long-press): Reply / React / Forward / Star / Delete -->
    <div v-if="actionMenuFor" class="fixed inset-0 z-40 flex items-end" style="background:rgba(15,23,42,.35);" @click="closeActionMenu">
      <div class="w-full bg-white rounded-t-3xl p-2 pb-4 safe-area-pb" @click.stop>
        <div class="w-10 h-1 rounded-full bg-slate-300 mx-auto my-2.5"></div>

        <button v-if="isMine(actionMenuFor)" class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-slate-50 active:scale-[.99] transition text-left" @click="openInfo(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-sky-50 text-sky-600 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
              <path d="M20 11.4a7.6 7.6 0 0 1-11 6.8L4.5 19.5l1.3-4.2A7.6 7.6 0 1 1 20 11.4Z"/>
              <path d="M12 11.2v3.4"/><path d="M12 8.2h.01"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-slate-700">Message info</span>
        </button>

        <button class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-slate-50 active:scale-[.99] transition text-left" @click="startReply(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-indigo-50 text-indigo-600 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
              <path d="M10 8 5 12.5 10 17"/><path d="M5 12.5h8a6 6 0 0 1 6 6"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-slate-700">Reply</span>
        </button>

        <button class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-slate-50 active:scale-[.99] transition text-left" @click="openReactionPicker(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-violet-50 text-violet-600 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="11.3" cy="12.7" r="7"/>
              <path d="M9 11.7h.01"/><path d="M13.6 11.7h.01"/>
              <path d="M8.9 15c.7.8 1.5 1.1 2.4 1.1s1.7-.3 2.4-1.1"/>
              <path d="M18.7 4.6l.7 1.7 1.7.7-1.7.7-.7 1.7-.7-1.7-1.7-.7 1.7-.7Z" fill="currentColor" stroke="none"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-slate-700">React</span>
        </button>

        <button class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-slate-50 active:scale-[.99] transition text-left" @click="startForward(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
              <path d="M14 8l5 4.5-5 4.5"/><path d="M19 12.5H11a6 6 0 0 0-6 6"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-slate-700">Forward</span>
        </button>

        <button class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-slate-50 active:scale-[.99] transition text-left" @click="toggleStar(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-amber-50 text-amber-500 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"
              :fill="actionMenuFor.starred ? 'currentColor' : 'none'">
              <path d="M12 4.8l2.1 4.3 4.7.7-3.4 3.3.8 4.7L12 15.9 7.8 17.8l.8-4.7-3.4-3.3 4.7-.7Z"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-slate-700">{{ actionMenuFor.starred ? 'Unstar' : 'Star' }}</span>
        </button>

        <button v-if="canDelete(actionMenuFor)" class="w-full flex items-center gap-3.5 px-3 py-2.5 rounded-2xl hover:bg-rose-50 active:scale-[.99] transition text-left" @click="askDelete(actionMenuFor)">
          <span class="w-9 h-9 rounded-2xl bg-rose-50 text-rose-500 flex items-center justify-center shrink-0">
            <svg viewBox="0 0 24 24" class="w-[19px] h-[19px]" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
              <path d="M5 7h14"/><path d="M10 7V5.6A1.6 1.6 0 0 1 11.6 4h.8A1.6 1.6 0 0 1 14 5.6V7"/>
              <path d="M7 7l.7 11.1A2 2 0 0 0 9.7 20h4.6a2 2 0 0 0 2-1.9L17 7"/>
            </svg>
          </span>
          <span class="text-[15px] font-medium text-rose-600">Delete</span>
        </button>
      </div>
    </div>

    <!-- Forward: pick a club -->
    <div v-if="forwardMsg" class="fixed inset-0 z-40 flex items-end" style="background:rgba(15,23,42,.35);" @click="cancelForward">
      <div class="w-full bg-white rounded-t-2xl p-4 pb-6 safe-area-pb max-h-[70vh] overflow-y-auto" @click.stop>
        <div class="w-10 h-1 rounded-full bg-slate-300 mx-auto mb-3"></div>
        <p class="text-sm font-bold text-slate-700 mb-1">Forward to…</p>
        <p class="text-xs text-slate-400 mb-3 truncate">“{{ forwardMsg.body }}”</p>
        <div v-if="!forwardTargets.length" class="text-sm text-slate-400 py-4 text-center">You're only in this one club.</div>
        <button v-for="c in forwardTargets" :key="c.club_id" :disabled="forwarding"
          class="w-full flex items-center gap-3 px-3 py-3 rounded-xl hover:bg-slate-50 active:scale-[.99] transition text-left disabled:opacity-50"
          @click="doForward(c.club_id)">
          <div class="w-9 h-9 rounded-xl bg-cyan-100 flex items-center justify-center text-lg shrink-0">🏸</div>
          <span class="text-sm font-medium text-slate-700 truncate">{{ c.clubs?.name }}</span>
          <span class="ml-auto text-cyan-600 text-lg">↪</span>
        </button>
      </div>
    </div>

    <!-- Message info (read receipts) -->
    <div v-if="infoFor" class="fixed inset-0 z-40 flex items-end" style="background:rgba(15,23,42,.35);" @click="closeInfo">
      <div class="w-full bg-white rounded-t-2xl pb-6 safe-area-pb max-h-[80vh] flex flex-col" @click.stop>
        <div class="w-10 h-1 rounded-full bg-slate-300 mx-auto my-2 shrink-0"></div>
        <div class="px-4 pb-2 shrink-0">
          <p class="text-sm font-bold text-slate-700 mb-2">Message info</p>
          <div class="rounded-xl px-3 py-2 text-white text-sm" style="background:linear-gradient(135deg,#00b4d8,#0088b3);">
            <p class="break-words whitespace-pre-wrap line-clamp-3">{{ infoFor.body }}</p>
            <p class="text-[9px] text-white/70 text-right mt-0.5">{{ fmtTime(infoFor.created_at) }}</p>
          </div>
        </div>

        <div class="overflow-y-auto px-4 pt-2">
          <div v-if="infoLoading" class="space-y-2 py-2">
            <div v-for="i in 3" :key="i" class="h-10 shimmer rounded-xl" />
          </div>

          <template v-else>
            <!-- Read by -->
            <div class="mb-3">
              <p class="text-[11px] font-bold text-cyan-600 flex items-center gap-1 mb-1.5">✓✓ Read by · {{ readRows.length }}</p>
              <p v-if="!readRows.length" class="text-xs text-slate-400 pl-1 pb-1">No one has read it yet.</p>
              <div v-for="r in readRows" :key="r.user_id" class="flex items-center gap-2.5 py-1.5">
                <Avatar :name="r.name" :src="r.avatar_url" :size="30" class="shrink-0" />
                <span class="text-sm text-slate-700 flex-1 min-w-0 truncate">{{ r.name }}</span>
                <span class="text-[11px] text-slate-400 shrink-0">{{ fmtDateTime(r.read_at) }}</span>
              </div>
            </div>

            <!-- Delivered to -->
            <div v-if="deliveredRows.length" class="mb-3">
              <p class="text-[11px] font-bold text-slate-500 flex items-center gap-1 mb-1.5">✓✓ Delivered to · {{ deliveredRows.length }}</p>
              <div v-for="r in deliveredRows" :key="r.user_id" class="flex items-center gap-2.5 py-1.5">
                <Avatar :name="r.name" :src="r.avatar_url" :size="30" class="shrink-0" />
                <span class="text-sm text-slate-700 flex-1 min-w-0 truncate">{{ r.name }}</span>
              </div>
            </div>

            <!-- Sent (not yet delivered) -->
            <div v-if="sentRows.length" class="mb-2">
              <p class="text-[11px] font-bold text-slate-400 flex items-center gap-1 mb-1.5">✓ Sent · {{ sentRows.length }}</p>
              <div v-for="r in sentRows" :key="r.user_id" class="flex items-center gap-2.5 py-1.5">
                <Avatar :name="r.name" :src="r.avatar_url" :size="30" class="shrink-0" />
                <span class="text-sm text-slate-500 flex-1 min-w-0 truncate">{{ r.name }}</span>
              </div>
            </div>

            <p v-if="!infoRows.length" class="text-sm text-slate-400 text-center py-4">You're the only member.</p>
          </template>
        </div>
      </div>
    </div>

    <!-- Full-screen image viewer -->
    <div v-if="lightbox" class="fixed inset-0 z-[60] flex items-center justify-center p-4" style="background:rgba(0,0,0,.92);" @click="lightbox = null">
      <img :src="lightbox" class="max-w-full max-h-full rounded-lg" alt="photo" @click.stop />
      <button class="absolute top-4 right-4 w-10 h-10 rounded-full bg-white/15 text-white text-xl flex items-center justify-center" aria-label="Close" @click="lightbox = null">✕</button>
    </div>

    <!-- Delete confirmation -->
    <div v-if="deleteMsg" class="fixed inset-0 z-40 grid place-items-center px-8" style="background:rgba(15,23,42,.45);" @click="cancelDelete">
      <div class="w-full max-w-xs bg-white rounded-2xl p-5 text-center" @click.stop>
        <div class="text-3xl mb-2">🗑️</div>
        <p class="text-sm font-bold text-slate-800 mb-1">Delete message?</p>
        <p class="text-xs text-slate-500 mb-4">This removes it for everyone in the chat.</p>
        <div class="flex gap-2">
          <button class="flex-1 py-2.5 rounded-xl text-sm font-semibold text-slate-600 bg-slate-100 hover:bg-slate-200" @click="cancelDelete">Cancel</button>
          <button class="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-rose-500 hover:bg-rose-600" @click="doDelete">Delete</button>
        </div>
      </div>
    </div>
  </div>
</template>
