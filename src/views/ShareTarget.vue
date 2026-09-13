<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { uploadClubImage } from '../lib/r2Upload'

// Receives a photo shared into the app (Android share sheet → manifest
// share_target → service worker stashes the file → redirect here). The user
// picks a club and we post it into that club's chat, reusing the same R2 +
// post_club_message pipeline as the chat composer.
const router = useRouter()
const { clubs, currentClub, loadClubs, selectClub } = useClub()

const file      = ref(null)
const previewUrl = ref('')
const loading   = ref(true)
const targetClub = ref('')
const sending   = ref(false)
const msg       = ref(null)

onMounted(async () => {
  try { if (!clubs.value.length) await loadClubs() } catch {}
  targetClub.value = currentClub.value?.club_id || clubs.value[0]?.club_id || ''
  try {
    const cache = await caches.open('b360-share')
    const res = await cache.match('/__shared-image')
    if (res) {
      const blob = await res.blob()
      if (blob && blob.size) {
        file.value = new File([blob], 'shared-photo', { type: blob.type || 'image/jpeg' })
        previewUrl.value = URL.createObjectURL(blob)
      }
      await cache.delete('/__shared-image')   // one-shot — don't resurface on reload
    }
  } catch { /* cache unavailable — show empty state */ }
  loading.value = false
})

async function send() {
  if (!file.value || !targetClub.value || sending.value) return
  sending.value = true; msg.value = null
  try {
    const up = await uploadClubImage(file.value, targetClub.value)
    const { error } = await supabase.rpc('post_club_message', {
      p_club_id:   targetClub.value,
      p_body:      null,
      p_reply_to:  null,
      p_image_url: up.url,
      p_image_w:   up.width,
      p_image_h:   up.height,
      p_thumb_url: up.thumbUrl,
    })
    if (error) throw new Error(error.message)
    // Switch to that club so the chat opens on the right conversation.
    const c = clubs.value.find(x => x.club_id === targetClub.value)
    if (c) selectClub(c)
    router.replace('/chat')
  } catch (e) {
    msg.value = e.message || 'Could not send the photo. Please try again.'
    sending.value = false
  }
}
</script>

<template>
  <div class="max-w-md mx-auto">
    <div class="mb-4 fade-up">
      <h2 class="font-display text-xl font-bold gradient-text">Share a photo</h2>
      <p class="text-xs text-slate-400 mt-0.5">Post the photo you shared into a club chat</p>
    </div>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-400">Loading shared photo…</div>

    <!-- No image (or a text/link share we don't handle yet) -->
    <div v-else-if="!file" class="card p-8 text-center fade-up">
      <div class="text-3xl mb-2">🖼️</div>
      <p class="text-sm font-semibold text-slate-700 mb-1">No photo to share</p>
      <p class="text-xs text-slate-400 mb-4">Share an image from your gallery or WhatsApp to post it here.</p>
      <button class="btn-ghost text-sm px-6" @click="router.replace('/dashboard')">Go to app →</button>
    </div>

    <!-- No clubs -->
    <div v-else-if="!clubs.length" class="card p-8 text-center fade-up">
      <div class="text-3xl mb-2">🏸</div>
      <p class="text-sm font-semibold text-slate-700 mb-1">Join a club first</p>
      <p class="text-xs text-slate-400 mb-4">You need to be in a club to share photos into its chat.</p>
      <button class="btn-primary text-sm px-6" @click="router.replace('/explore')">Find a club →</button>
    </div>

    <template v-else>
      <div class="card p-3 mb-4 fade-up">
        <img :src="previewUrl" alt="Shared photo"
          class="w-full rounded-xl object-contain max-h-[46vh] bg-slate-50" />
      </div>

      <div class="card p-4 mb-4 fade-up">
        <label class="label">Send to</label>
        <select v-model="targetClub" class="input">
          <option v-for="c in clubs" :key="c.club_id" :value="c.club_id">{{ c.clubs?.name || c.name }}</option>
        </select>
        <p class="text-[11px] text-slate-400 mt-2">Posts as a photo message in this club's chat.</p>
      </div>

      <p v-if="msg" class="mb-3 rounded-xl px-4 py-3 text-sm font-medium bg-rose-50 text-rose-700 border border-rose-200">{{ msg }}</p>

      <div class="flex gap-2">
        <button class="btn-ghost flex-1 py-3 text-sm" :disabled="sending" @click="router.replace('/dashboard')">Cancel</button>
        <button class="btn-primary flex-1 py-3 text-sm font-bold" :disabled="sending || !targetClub" @click="send">
          {{ sending ? 'Sending…' : '📤 Send to chat' }}
        </button>
      </div>
    </template>
  </div>
</template>
