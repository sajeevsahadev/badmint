<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { applySeo, setJsonLd, SEO_BASE } from '../lib/seo'

const route = useRoute()
const data   = ref(null)
const loading = ref(true)
const notFound = ref(false)
const copied = ref(false)

const t     = computed(() => data.value?.tournament ?? null)
const teams = computed(() => data.value?.teams ?? [])

const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }) : null
const dateLabel = computed(() => {
  if (!t.value) return ''
  const s = fmtDate(t.value.start_date), e = fmtDate(t.value.end_date)
  return s && e && e !== s ? `${s} – ${e}` : (s || 'Date TBC')
})
const statusLabel = computed(() => ({
  draft: 'Draft', registration_open: 'Registration open', live: 'Live now', completed: 'Completed',
}[t.value?.status] || t.value?.status))
const statusClass = computed(() => ({
  registration_open: 'bg-emerald-50 text-emerald-600 border-emerald-200',
  live: 'bg-rose-50 text-rose-600 border-rose-200',
  completed: 'bg-slate-100 text-slate-500 border-slate-200',
}[t.value?.status] || 'bg-slate-100 text-slate-500 border-slate-200'))

const shareUrl = computed(() => t.value ? `${SEO_BASE}/t/${t.value.share_code}` : SEO_BASE)
const teamName = id => teams.value.find(x => x.id === id)?.team_name

async function load() {
  loading.value = true; notFound.value = false
  const { data: res } = await supabase.rpc('get_public_tournament', { p_code: route.params.code })
  loading.value = false
  if (!res) { notFound.value = true; return }
  data.value = res
  applySeo({
    title: `${t.value.name} — ${t.value.club_name} | Badminton 360`,
    description: `${t.value.name}, a badminton doubles tournament by ${t.value.club_name}${t.value.venue ? ' at ' + t.value.venue : ''}${dateLabel.value ? ' · ' + dateLabel.value : ''}. Teams, draw, live results and winners.`,
    image: t.value.cover_photo_url || undefined,
    path: `/t/${t.value.share_code}`,
    type: 'article',
  })
  setJsonLd('ld-tournament', {
    '@context': 'https://schema.org', '@type': 'SportsEvent',
    name: t.value.name, sport: 'Badminton',
    startDate: t.value.start_date || undefined, endDate: t.value.end_date || undefined,
    eventStatus: t.value.status === 'completed' ? 'https://schema.org/EventScheduled' : 'https://schema.org/EventScheduled',
    location: t.value.venue ? { '@type': 'Place', name: t.value.venue, address: t.value.venue_address || undefined } : undefined,
    organizer: { '@type': 'Organization', name: t.value.club_name },
    url: shareUrl.value,
  })
}
onMounted(load)
watch(() => route.params.code, load)

async function copyLink() {
  try { await navigator.clipboard.writeText(shareUrl.value); copied.value = true; setTimeout(() => copied.value = false, 1800) } catch { /* ignore */ }
}
const waShare = computed(() =>
  `https://wa.me/?text=${encodeURIComponent(`🏸 ${t.value?.name} — ${t.value?.club_name}\n${dateLabel.value}\nFollow the tournament: ${shareUrl.value}`)}`)
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff">
    <div v-if="loading" class="max-w-3xl mx-auto px-4 py-10 space-y-3">
      <div class="h-40 shimmer rounded-2xl" /><div class="h-24 shimmer rounded-2xl" /><div class="h-40 shimmer rounded-2xl" />
    </div>

    <div v-else-if="notFound" class="max-w-md mx-auto px-4 py-20 text-center">
      <div class="text-4xl mb-3">🏸</div>
      <p class="font-bold text-slate-700 mb-1">Tournament not found</p>
      <p class="text-sm text-slate-400 mb-5">This link may be wrong or the tournament was removed.</p>
      <RouterLink to="/" class="btn-primary inline-flex px-5 py-2.5">Badminton 360 →</RouterLink>
    </div>

    <template v-else>
      <!-- Hero -->
      <header class="relative overflow-hidden text-white"
        style="background:linear-gradient(135deg,#0b1220 0%,#0f2a4a 55%,#0a5b74 100%)">
        <div class="absolute inset-0 opacity-20" aria-hidden="true"
          style="background-image:radial-gradient(circle at 20% 30%,#22d3ee55,transparent 40%),radial-gradient(circle at 80% 20%,#a855f755,transparent 40%)"></div>
        <div class="relative max-w-3xl mx-auto px-5 sm:px-8 pt-8 pb-9 safe-area-pt">
          <div class="flex items-center gap-2 mb-3 text-white/70 text-xs">
            <span class="inline-flex items-center rounded-full border px-2.5 py-0.5 font-semibold" :class="statusClass">{{ statusLabel }}</span>
            <span>🏆 Doubles Tournament</span>
          </div>
          <h1 class="font-display text-3xl sm:text-4xl font-extrabold leading-tight">{{ t.name }}</h1>
          <p class="text-white/80 mt-2 font-medium">{{ t.club_name }}</p>
          <div class="flex flex-wrap gap-x-5 gap-y-1 mt-3 text-sm text-white/70">
            <span>📅 {{ dateLabel }}</span>
            <span v-if="t.venue">📍 {{ t.venue }}</span>
            <a v-if="t.maps_url" :href="t.maps_url" target="_blank" rel="noopener" class="text-cyan-300 hover:underline">Open in Maps ↗</a>
          </div>
        </div>
      </header>

      <main class="max-w-3xl mx-auto px-4 sm:px-8 py-6 space-y-4">
        <!-- Share -->
        <div class="card p-4 flex flex-wrap items-center gap-2">
          <span class="text-xs font-semibold text-slate-500 mr-auto">Share this tournament</span>
          <a :href="waShare" target="_blank" rel="noopener" class="btn-ghost text-xs px-3 py-1.5">🟢 WhatsApp</a>
          <button class="btn-ghost text-xs px-3 py-1.5" @click="copyLink">{{ copied ? '✓ Copied' : '🔗 Copy link' }}</button>
        </div>

        <!-- Register CTA -->
        <RouterLink v-if="t.status === 'registration_open'" :to="`/tournament/${t.id}/register`"
          class="card-neon p-5 flex items-center gap-4 no-underline hover:shadow-lg transition-all active:scale-[0.99]">
          <div class="text-3xl shrink-0">📝</div>
          <div class="flex-1 min-w-0">
            <p class="font-display font-bold gradient-text">Register your team</p>
            <p class="text-xs text-slate-500 mt-0.5">
              {{ data.confirmed_count }}/{{ t.max_teams }} teams confirmed{{ t.entry_fee ? ` · Entry ${t.entry_fee}` : '' }}
            </p>
          </div>
          <span class="btn-primary text-sm px-4 py-2 shrink-0">Register →</span>
        </RouterLink>

        <!-- Key info -->
        <div class="grid sm:grid-cols-2 gap-3">
          <div v-if="t.entry_fee" class="card p-4">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Entry fee</p>
            <p class="text-lg font-extrabold text-slate-800">{{ t.entry_fee }}</p>
          </div>
          <div v-if="t.prize_info" class="card p-4">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Prizes</p>
            <p class="text-sm font-semibold text-slate-700">{{ t.prize_info }}</p>
          </div>
          <div v-if="t.venue_address" class="card p-4 sm:col-span-2">
            <p class="text-[11px] uppercase tracking-wide text-slate-400">Venue</p>
            <p class="text-sm font-semibold text-slate-700">{{ t.venue }}</p>
            <p class="text-xs text-slate-500">{{ t.venue_address }}</p>
            <a v-if="t.maps_url" :href="t.maps_url" target="_blank" rel="noopener" class="text-xs text-neon font-semibold mt-1 inline-block">Get directions ↗</a>
          </div>
        </div>

        <div v-if="t.description" class="card p-4">
          <p class="text-sm text-slate-600 whitespace-pre-wrap leading-relaxed">{{ t.description }}</p>
        </div>

        <!-- Podium (once results are in) -->
        <div v-if="t.winner_registration_id" class="card overflow-hidden">
          <div class="px-4 py-3 border-b border-slate-100 text-xs font-bold text-slate-600">🏆 Results</div>
          <div class="divide-y divide-slate-50">
            <div class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥇</span><span class="font-bold text-slate-800">{{ teamName(t.winner_registration_id) || 'Champion' }}</span></div>
            <div v-if="t.runner_up_registration_id" class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥈</span><span class="font-semibold text-slate-700">{{ teamName(t.runner_up_registration_id) }}</span></div>
            <div v-if="t.third_registration_id" class="flex items-center gap-3 px-4 py-3"><span class="text-lg">🥉</span><span class="font-semibold text-slate-700">{{ teamName(t.third_registration_id) }}</span></div>
          </div>
        </div>

        <!-- Teams -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="label">Confirmed teams</p>
            <span class="text-xs text-slate-400">{{ teams.length }}/{{ t.max_teams }}</span>
          </div>
          <div v-if="!teams.length" class="card p-6 text-center text-sm text-slate-400">
            No teams confirmed yet — check back soon.
          </div>
          <div v-else class="grid sm:grid-cols-2 gap-2">
            <div v-for="(tm, i) in teams" :key="tm.id" class="card p-3 flex items-center gap-3">
              <div class="w-8 h-8 rounded-lg flex items-center justify-center text-xs font-black text-slate-950 shrink-0"
                style="background:linear-gradient(135deg,#00e5ff,#a855f7)">{{ tm.seed && tm.seed > 1 ? tm.seed : (i + 1) }}</div>
              <div class="min-w-0">
                <p class="text-sm font-bold text-slate-800 truncate">{{ tm.team_name }}</p>
                <p class="text-xs text-slate-500 truncate">{{ [tm.player_a_name, tm.player_b_name].filter(Boolean).join(' & ') }}</p>
              </div>
            </div>
          </div>
        </div>

        <div class="text-center py-6">
          <RouterLink to="/" class="text-xs text-slate-400 hover:text-neon transition">Powered by <span class="font-semibold gradient-text">Badminton 360</span> →</RouterLink>
        </div>
      </main>
    </template>
  </div>
</template>
