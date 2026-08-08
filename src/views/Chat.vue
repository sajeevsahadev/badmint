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
let channel = null
const senderCache = new Map()       // user_id → { sender_name, avatar_url }
let myProfile = { sender_name: 'You', avatar_url: null }

const clubId   = computed(() => currentClub.value?.club_id ?? null)
const clubName = computed(() => currentClub.value?.clubs?.name ?? 'Club')

const EMOJIS = ['😀','😂','😅','😍','😎','🤝','👍','👏','🙌','💪','🔥','🎉','🏸','⏰','✅','❌','😢','🤔','🙏','❤️']

const fmtTime = ts => new Date(ts).toLocaleTimeString('en-AE', { hour: '2-digit', minute: '2-digit' })
const fmtDay = ts => new Date(ts).toLocaleDateString('en-AE', { day: 'numeric', month: 'short', year: 'numeric' })
const isMine = m => m.user_id === user.value?.id
// Show a date separator when the day changes between consecutive messages.
function showDaySep(i) {
  if (i === 0) return true
  return new Date(messages.value[i].created_at).toDateString()
       !== new Date(messages.value[i - 1].created_at).toDateString()
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
    .subscribe()
}

async function send() {
  const body = draft.value.trim()
  if (!body || sending.value || !clubId.value) return
  sending.value = true
  draft.value = ''
  showEmoji.value = false
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

function addEmoji(e) { draft.value += e; inputEl.value?.focus() }

onMounted(load)
watch(clubId, load)
onBeforeUnmount(() => { if (channel) supabase.removeChannel(channel) })
</script>

<template>
  <div class="fixed inset-0 flex flex-col" style="background:#eef4ff;">
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
    <div v-else ref="scroller" class="flex-1 overflow-y-auto px-3 py-3 space-y-1.5" @scroll="onScroll">
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
        <div class="flex items-end gap-2" :class="isMine(m) ? 'flex-row-reverse' : ''">
          <Avatar v-if="!isMine(m)" :name="m.sender_name" :src="m.avatar_url" :size="26" class="shrink-0 mb-1" />
          <div class="max-w-[78%] rounded-2xl px-3 py-2"
            :class="isMine(m)
              ? 'text-white rounded-br-md'
              : 'bg-white text-slate-800 rounded-bl-md border border-slate-100'"
            :style="isMine(m) ? 'background:linear-gradient(135deg,#00b4d8,#0088b3);' : ''">
            <p v-if="!isMine(m)" class="text-[11px] font-bold mb-0.5" style="color:#0099b8;">{{ m.sender_name }}</p>
            <p class="text-sm leading-snug break-words whitespace-pre-wrap">{{ m.body }}</p>
            <p class="text-[9px] mt-0.5 text-right" :class="isMine(m) ? 'text-white/70' : 'text-slate-400'">
              {{ fmtTime(m.created_at) }}
            </p>
          </div>
        </div>
      </template>
    </div>

    <!-- Emoji quick bar -->
    <div v-if="clubId && showEmoji" class="shrink-0 flex gap-1 overflow-x-auto px-3 py-2 bg-white border-t border-slate-100">
      <button v-for="e in EMOJIS" :key="e" class="text-2xl shrink-0 hover:scale-110 transition" @click="addEmoji(e)">{{ e }}</button>
    </div>

    <!-- Input -->
    <div v-if="clubId" class="shrink-0 flex items-end gap-2 px-3 py-2.5 safe-area-pb"
      style="background:#ffffff; border-top:1px solid rgba(15,23,42,.08);">
      <button class="w-10 h-10 rounded-full flex items-center justify-center text-xl shrink-0 hover:bg-slate-100 transition"
        aria-label="Emojis" @click="showEmoji = !showEmoji">😊</button>
      <textarea ref="inputEl" v-model="draft" rows="1" maxlength="2000"
        placeholder="Message…"
        class="input flex-1 resize-none max-h-28 py-2.5"
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
