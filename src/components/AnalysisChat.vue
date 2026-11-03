<script setup>
// Ask-about-your-performance chat. Grounded on THIS player's computed metrics + report via the
// `analysis-chat` Edge Function (Gemini). It never invents numbers — it answers from the analysis.
import { ref, nextTick } from 'vue'
import { supabase } from '../lib/supabase'

const props = defineProps({
  videoId: { type: String, required: true },
  tagId:   { type: String, required: true },
  name:    { type: String, default: 'this player' },
})

const messages = ref([])
const threadId = ref(null)
const input    = ref('')
const sending  = ref(false)
const err      = ref('')
const scroller = ref(null)

const suggestions = [
  'What should I work on first?',
  'Why is my recovery slow?',
  'How do I improve my net play?',
  'Is my movement risking injury?',
]

async function send(text) {
  const msg = (text ?? input.value).trim()
  if (!msg || sending.value) return
  input.value = ''
  err.value = ''
  messages.value.push({ role: 'user', content: msg })
  await scrollDown()
  sending.value = true
  try {
    const { data, error } = await supabase.functions.invoke('analysis-chat', {
      body: { video_id: props.videoId, tag_id: props.tagId, thread_id: threadId.value, message: msg },
    })
    if (error) throw error
    if (data?.error) throw new Error(data.error)
    threadId.value = data.thread_id || threadId.value
    messages.value.push({ role: 'assistant', content: data.reply || '…' })
  } catch (e) {
    err.value = e?.message || 'Could not reach the assistant.'
  } finally {
    sending.value = false
    await scrollDown()
  }
}

async function scrollDown() {
  await nextTick()
  if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight
}
</script>

<template>
  <div class="card p-4">
    <div class="mb-1 flex items-center gap-2">
      <span class="text-lg">💬</span>
      <div class="font-display text-base font-bold text-slate-800">Ask about {{ name }}'s game</div>
    </div>
    <p class="mb-3 text-xs text-slate-500">Answers come from this match's analysis.</p>

    <div ref="scroller" class="max-h-72 space-y-2 overflow-y-auto">
      <div v-if="!messages.length" class="flex flex-wrap gap-2">
        <button v-for="s in suggestions" :key="s" @click="send(s)"
          class="rounded-full border border-slate-200 px-3 py-1.5 text-xs text-slate-600 hover:border-cyan-300 hover:text-cyan-700">
          {{ s }}
        </button>
      </div>
      <div v-for="(mmsg, i) in messages" :key="i" class="flex" :class="mmsg.role === 'user' ? 'justify-end' : 'justify-start'">
        <div class="max-w-[85%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-sm"
          :class="mmsg.role === 'user' ? 'bg-cyan-600 text-white' : 'bg-slate-100 text-slate-700'">
          {{ mmsg.content }}
        </div>
      </div>
      <div v-if="sending" class="flex justify-start">
        <div class="rounded-2xl bg-slate-100 px-3 py-2 text-sm text-slate-400">Thinking…</div>
      </div>
    </div>

    <p v-if="err" class="mt-2 text-xs text-red-600">{{ err }}</p>
    <form @submit.prevent="send()" class="mt-3 flex gap-2">
      <input v-model="input" type="text" placeholder="Ask a question…"
        class="flex-1 rounded-xl border border-slate-200 px-3 py-2 text-sm focus:border-cyan-400 focus:outline-none" />
      <button type="submit" :disabled="sending || !input.trim()" class="btn-primary px-4 py-2 text-sm disabled:opacity-40">Send</button>
    </form>
  </div>
</template>
