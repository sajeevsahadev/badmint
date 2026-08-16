<script setup>
import { onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'

// Resolves a short share link (/p/:code) to the full player profile.
const route = useRoute()
const router = useRouter()

onMounted(async () => {
  const { data: playerId } = await supabase.rpc('resolve_share_code', { p_code: route.params.code })
  if (playerId) router.replace(`/player/${playerId}`)
  else router.replace('/')
})
</script>

<template>
  <div class="min-h-screen grid place-items-center">
    <div class="text-center text-slate-400">
      <div class="text-3xl mb-2 animate-pulse">🏸</div>
      <p class="text-sm">Opening profile…</p>
    </div>
  </div>
</template>
