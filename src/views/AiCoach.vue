<script setup>
// Premium "AI Match Analysis" hub. Gated by early access (Phase 1). Non-holders see a
// coming-soon teaser; holders see the feature (record matches now; AI reports land in Phase 5).
import { ref, onMounted, computed } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useEntitlements } from '../composables/useEntitlements'
import { getPlaybackUrl } from '../lib/videoStorage'
import PageHeader from '../components/PageHeader.vue'
import AiHeroGraphic from '../components/AiHeroGraphic.vue'

const router = useRouter()
const { currentClub } = useClub()
const { hasEarlyAccess, loadEntitlements, loaded } = useEntitlements()

const videos  = ref([])
const playing = ref(null)
const requestStatus = ref(null)   // null | 'pending' | 'approved' | 'declined'
const requesting = ref(false)

onMounted(async () => {
  await loadEntitlements()
  if (hasEarlyAccess.value) { await loadVideos(); return }
  // Non-holder: show any existing waitlist request so the button reflects state.
  const { data } = await supabase.from('early_access_requests').select('status').maybeSingle()
  requestStatus.value = data?.status ?? null
})

async function requestAccess() {
  requesting.value = true
  try {
    const { data } = await supabase.rpc('request_early_access', { p_note: null })
    requestStatus.value = data || 'pending'
  } finally { requesting.value = false }
}

// Admin approved them while the page was open — refresh entitlements in place.
async function enterFeature() {
  await loadEntitlements(true)
  if (hasEarlyAccess.value) await loadVideos()
}

async function loadVideos() {
  if (!currentClub.value) return
  const { data } = await supabase.from('match_videos')
    .select('id, title, game_type, duration_s, status, created_at')
    .eq('club_id', currentClub.value.club_id)
    .order('created_at', { ascending: false })
    .limit(20)
  videos.value = data ?? []
}

const statusLabel = computed(() => (s) => ({
  uploaded: '⏳ Awaiting analysis', analyzing: '⚙️ Analyzing', done: '✅ Report ready', failed: '⚠️ Failed',
}[s] || s))

function fmt(s) { const m = Math.floor((s || 0) / 60), x = (s || 0) % 60; return `${m}:${String(x).padStart(2, '0')}` }
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <PageHeader icon="🎥" title="Coach Vision"
      subtitle="Your AI match coach — turn match footage into per-player coaching, stroke by stroke.">
    </PageHeader>

    <!-- Loading -->
    <div v-if="!loaded" class="card p-8 text-center text-slate-400">Loading…</div>

    <!-- EARLY ACCESS: the feature hub -->
    <div v-if="loaded && hasEarlyAccess">
      <AiHeroGraphic class="mb-4 fade-up" />
      <div class="card card-neon mb-4 p-4 flex items-center gap-3 fade-up d1">
        <span class="badge-pending">✨ Early Access</span>
        <span class="text-sm text-slate-600">You're on the early-access list — thanks for testing!</span>
      </div>

      <div class="mb-4 grid grid-cols-2 gap-3 fade-up d2">
        <button @click="router.push('/record')" class="btn-primary sheen press py-3 text-sm">
          🎥 Record a match
        </button>
        <button @click="router.push('/record?upload=1')" class="btn-violet sheen press py-3 text-sm">
          ⬆️ Upload a video
        </button>
      </div>

      <div class="card p-4 mb-4 lift fade-up d3">
        <div class="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500">Your match videos</div>
        <div v-if="!videos.length" class="py-3 text-sm text-slate-400">
          No videos yet. Record or upload a match and it will appear here, ready for analysis.
        </div>
        <button v-for="v in videos" :key="v.id" @click="router.push(`/coach/video/${v.id}`)"
          class="flex w-full items-center justify-between gap-2 border-b border-slate-100 py-2.5 text-left last:border-0 hover:bg-slate-50">
          <div class="min-w-0">
            <div class="truncate text-sm font-semibold text-slate-800">{{ v.title }}</div>
            <div class="text-xs text-slate-400">{{ v.game_type }} · {{ fmt(v.duration_s) }} ·
              <span class="font-medium text-slate-500">{{ statusLabel(v.status) }}</span>
            </div>
          </div>
          <span class="shrink-0 text-slate-300">›</span>
        </button>
      </div>

      <!-- The two tiers (both included during early access; future subscriptions plug in here) -->
      <div class="mb-1 text-xs font-bold uppercase tracking-wide text-slate-500 fade-up d4">What you get for each match</div>
      <div class="grid gap-3 sm:grid-cols-2 fade-up d4">
        <div class="card p-4 lift">
          <div class="flex items-center gap-2">
            <span class="text-lg">📊</span>
            <div class="font-display font-bold text-slate-800">Quick Report</div>
            <span class="ml-auto rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-bold text-emerald-700">INCLUDED</span>
          </div>
          <ul class="mt-2 space-y-1 text-xs text-slate-600 list-disc pl-4">
            <li>Movement, landing &amp; lunge-load per player</li>
            <li>Coach · Physio · Your-numbers view</li>
            <li>Ask the AI coach about your game</li>
          </ul>
        </div>
        <div class="card card-violet p-4 lift">
          <div class="flex items-center gap-2">
            <span class="text-lg">🎙️</span>
            <div class="font-display font-bold text-slate-800">Deep Coaching</div>
            <span class="ml-auto rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-bold text-violet-700">PREMIUM</span>
          </div>
          <ul class="mt-2 space-y-1 text-xs text-slate-600 list-disc pl-4">
            <li>Stroke-by-stroke commentary, like a coach beside you</li>
            <li>Tap a moment to jump the video there</li>
            <li>Spoken commentary (AI voice)</li>
          </ul>
        </div>
      </div>
      <p class="mt-2 text-[11px] text-slate-400">Both tiers are included free while you're in early access. Your videos stay private to your club.</p>
    </div>

    <!-- NOT EARLY ACCESS: coming-soon teaser -->
    <div v-if="loaded && !hasEarlyAccess">
      <AiHeroGraphic class="mb-4 fade-up" />
      <div class="card card-neon p-6 text-center fade-up d1">
        <div class="text-4xl mb-2 float-soft">✨</div>
        <div class="gradient-text text-2xl font-display font-bold">Turn match footage into coaching</div>
        <p class="mt-2 text-sm text-slate-600">
          Record a match and get a per-player breakdown of footwork, shots and positioning — plus a
          training plan to improve. A premium feature, rolling out now to early-access members.
        </p>

        <button v-if="requestStatus === null" :disabled="requesting" @click="requestAccess"
          class="btn-primary sheen press w-full py-3 text-base mt-4 disabled:opacity-50">
          {{ requesting ? 'Requesting…' : '✨ Request early access' }}
        </button>
        <div v-else-if="requestStatus === 'pending'"
          class="mt-4 inline-flex items-center gap-2 rounded-full bg-amber-50 border border-amber-200 px-4 py-2 text-sm font-semibold text-amber-700">
          ⏳ On the waitlist — we'll be in touch
        </div>
        <button v-else-if="requestStatus === 'approved'" @click="enterFeature"
          class="btn-success press w-full py-3 text-base mt-4">
          ✅ You're approved — enter
        </button>
        <div v-else
          class="mt-4 inline-flex items-center gap-2 rounded-full bg-slate-100 border border-slate-200 px-4 py-2 text-sm font-semibold text-slate-500">
          Request received
        </div>
        <p class="mt-3 text-xs text-slate-400">We're opening access gradually — thanks for your patience.</p>
      </div>

      <div class="grid grid-cols-3 gap-3 mt-4">
        <div class="card p-3 text-center lift fade-up d2">
          <div class="text-2xl">🏃</div><div class="text-xs font-semibold text-slate-700 mt-1">Footwork</div>
        </div>
        <div class="card p-3 text-center lift fade-up d3">
          <div class="text-2xl">🏸</div><div class="text-xs font-semibold text-slate-700 mt-1">Shot analysis</div>
        </div>
        <div class="card p-3 text-center lift fade-up d4">
          <div class="text-2xl">📈</div><div class="text-xs font-semibold text-slate-700 mt-1">Progress</div>
        </div>
      </div>
    </div>
  </div>
</template>
