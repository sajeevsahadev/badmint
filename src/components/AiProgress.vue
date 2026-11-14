<script setup>
// "My game over time" — every analysed match's KPIs as small-multiple trend charts, plus the coach's
// most recent focus. Premium (early access today). Used on the profile pages and the analysis page.
import { ref, computed, onMounted, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { TREND_KEYS, seriesFor, kpiDef } from '../lib/coachKpis'
import { scoreSeries, levelFor, badges, nextBadge, risingStreak } from '../lib/coachGame'
import KpiTrend from './KpiTrend.vue'

const props = defineProps({
  playerId: { type: String, default: null },   // null → every player linked to the signed-in user
  compact:  { type: Boolean, default: false },  // fewer charts (analysis page)
  title:    { type: String, default: 'Your progress' },
})

const loading = ref(true)
const points = ref([])
const locked = ref(false)
const showAll = ref(false)

async function load() {
  loading.value = true
  const { data, error } = await supabase.rpc('get_player_ai_progress', { p_player_id: props.playerId })
  locked.value = !!data?.locked || !!error
  points.value = data?.points ?? []
  loading.value = false
}
onMounted(load)
watch(() => props.playerId, load)

const keys = computed(() => {
  const ks = TREND_KEYS.filter(k => seriesFor(points.value, k).length)
  return props.compact && !showAll.value ? ks.slice(0, 4) : ks
})
const moreCount = computed(() => TREND_KEYS.filter(k => seriesFor(points.value, k).length).length - keys.value.length)
const latest = computed(() => points.value[points.value.length - 1] || null)

// ── Motivation layer: Form Score, level, badges (all from the measured matches above) ──
const scores  = computed(() => scoreSeries(points.value))
const score   = computed(() => scores.value[scores.value.length - 1]?.score ?? null)
const prevScore = computed(() => scores.value[scores.value.length - 2]?.score ?? null)
const level   = computed(() => levelFor(score.value))
const allBadges = computed(() => badges(points.value))
const earned  = computed(() => allBadges.value.filter(b => b.earned))
const target  = computed(() => nextBadge(points.value))
const streak  = computed(() => risingStreak(points.value))
const openBadge = ref(null)
const RING = 2 * Math.PI * 34
const fmtDate = (s) => new Date(s).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
defineExpose({ load })
</script>

<template>
  <div v-if="!locked" class="space-y-3">
    <div class="flex items-end justify-between">
      <div>
        <div class="font-display text-base font-bold text-slate-800">📈 {{ title }}</div>
        <div class="text-[11px] text-slate-500">
          {{ points.length }} analysed {{ points.length === 1 ? 'match' : 'matches' }}
          <span v-if="points.length"> · since {{ fmtDate(points[0].at) }}</span>
        </div>
      </div>
    </div>

    <div v-if="loading" class="h-28 shimmer rounded-2xl" />

    <div v-else-if="!points.length" class="rounded-2xl border border-dashed border-slate-300 bg-slate-50 p-4 text-center text-sm text-slate-500">
      No Deep Coaching reports yet. Record or upload a match and run <b>Deep Coaching</b> — your progress builds from there.
      <div class="mt-3"><RouterLink to="/coach" class="btn-primary inline-block px-4 py-2 text-xs">Open AI Match Analysis</RouterLink></div>
    </div>

    <template v-else>
      <!-- Level card: Form Score ring + level + next target -->
      <div v-if="level" class="game-card rounded-3xl p-4 text-white">
        <div class="flex items-center gap-4">
          <div class="relative h-[84px] w-[84px] shrink-0">
            <svg viewBox="0 0 84 84" class="h-full w-full -rotate-90" aria-hidden="true">
              <circle cx="42" cy="42" r="34" fill="none" stroke="rgba(255,255,255,.18)" stroke-width="8" />
              <circle cx="42" cy="42" r="34" fill="none" stroke="#fbbf24" stroke-width="8" stroke-linecap="round"
                class="ring" :stroke-dasharray="RING" :stroke-dashoffset="RING * (1 - score / 100)" />
            </svg>
            <div class="absolute inset-0 flex flex-col items-center justify-center">
              <span class="font-display text-2xl font-extrabold leading-none">{{ score }}</span>
              <span class="text-[9px] font-semibold uppercase tracking-wide text-white/70">Form</span>
            </div>
          </div>
          <div class="min-w-0 flex-1">
            <div class="text-[10px] font-bold uppercase tracking-widest text-cyan-200">Your level</div>
            <div class="font-display text-xl font-extrabold leading-tight">{{ level.icon }} {{ level.name }}</div>
            <div v-if="level.next" class="mt-0.5 text-xs text-white/80">{{ level.toNext }} more points to <b>{{ level.next.name }}</b></div>
            <div v-else class="mt-0.5 text-xs text-white/80">Top level — now keep it there.</div>
            <div v-if="prevScore !== null" class="mt-1 text-[11px] font-bold"
              :class="score > prevScore ? 'text-emerald-300' : score < prevScore ? 'text-rose-300' : 'text-white/60'">
              {{ score > prevScore ? `▲ ${score - prevScore} since last match` : score < prevScore ? `▼ ${prevScore - score} since last match` : 'Same as last match' }}
              <span v-if="streak >= 2"> · 🔥 {{ streak }} in a row</span>
            </div>
          </div>
        </div>
        <div v-if="target" class="mt-3 rounded-2xl bg-white/10 p-2.5">
          <div class="flex items-center justify-between text-[11px]">
            <span class="font-bold">🎯 Next badge: {{ target.icon }} {{ target.name }}</span>
            <span class="text-white/70">{{ Math.round(target.progress * 100) }}%</span>
          </div>
          <div class="mt-1.5 h-2 overflow-hidden rounded-full bg-white/15">
            <div class="bar h-full rounded-full bg-amber-400" :style="{ width: Math.round(target.progress * 100) + '%' }"></div>
          </div>
          <div class="mt-1 text-[11px] text-white/75">{{ target.hint }}</div>
        </div>
      </div>

      <!-- Badges -->
      <div class="rounded-2xl border border-slate-200 bg-white p-3">
        <div class="mb-2 flex items-center justify-between">
          <span class="text-[10px] font-bold uppercase tracking-wide text-slate-400">Badges</span>
          <span class="text-[11px] font-semibold text-slate-500">{{ earned.length }} of {{ allBadges.length }} earned</span>
        </div>
        <div class="flex flex-wrap gap-2">
          <button v-for="b in allBadges" :key="b.id" @click="openBadge = openBadge === b.id ? null : b.id"
            class="badge-chip" :class="b.earned ? 'badge-on' : 'badge-off'" :aria-label="`${b.name}: ${b.hint}`">
            <span class="text-lg leading-none" :class="b.earned ? '' : 'grayscale opacity-40'">{{ b.icon }}</span>
          </button>
        </div>
        <div v-if="openBadge" class="mt-2 rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600">
          <template v-for="b in allBadges" :key="'o' + b.id">
            <span v-if="b.id === openBadge"><b>{{ b.icon }} {{ b.name }}</b> — {{ b.hint }}.
              <b :class="b.earned ? 'text-emerald-600' : 'text-slate-500'">{{ b.earned ? 'Earned ✓' : Math.round(b.progress * 100) + '% there' }}</b></span>
          </template>
        </div>
        <p v-else class="mt-2 text-[10px] text-slate-400">Tap a badge to see how to earn it. Form Score = average of your back-to-base, high-elbow and lunge rates.</p>
      </div>

      <div v-if="latest?.focus?.length" class="rounded-2xl border border-amber-200 bg-amber-50 p-3">
        <div class="text-[10px] font-bold uppercase tracking-wide text-amber-700">Current coaching focus</div>
        <ol class="mt-1 space-y-0.5 text-sm text-slate-700">
          <li v-for="(f, i) in latest.focus.slice(0, 3)" :key="i"><b>{{ i + 1 }}.</b> {{ f.title }}</li>
        </ol>
        <RouterLink :to="`/coach/video/${latest.video_id}?tier=deep`" class="mt-1 inline-block text-[11px] font-semibold text-amber-700">
          Latest report →
        </RouterLink>
      </div>

      <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <KpiTrend v-for="k in keys" :key="k" :def="kpiDef(k)" :points="seriesFor(points, k)" />
      </div>
      <button v-if="compact && moreCount > 0" @click="showAll = true" class="btn-ghost w-full py-2 text-xs">
        Show {{ moreCount }} more KPIs
      </button>
      <p class="text-center text-[10px] text-slate-400">
        Counts depend on how long each match is — the % charts compare matches fairly.
      </p>

      <div class="rounded-2xl border border-slate-200 bg-white p-3">
        <div class="mb-1 text-[10px] font-bold uppercase tracking-wide text-slate-400">Matches</div>
        <RouterLink v-for="p in [...points].reverse()" :key="p.video_id" :to="`/coach/video/${p.video_id}?tier=deep`"
          class="flex items-center justify-between border-b border-slate-100 py-1.5 text-xs last:border-0">
          <span class="truncate text-slate-700">{{ p.video || 'Match' }}<span class="text-slate-400"> · {{ p.club }}</span></span>
          <span class="shrink-0 text-slate-400">{{ fmtDate(p.at) }} ›</span>
        </RouterLink>
      </div>
    </template>
  </div>
</template>

<style scoped>
.game-card { background: radial-gradient(120% 90% at 100% 0%, #7c3aed 0%, transparent 55%),
                         radial-gradient(90% 80% at 0% 100%, #0891b2 0%, transparent 60%), #0f172a; }
.ring { transition: stroke-dashoffset 1s ease; }
.bar { transition: width .9s ease; }
.badge-chip { display: inline-flex; height: 2.6rem; width: 2.6rem; align-items: center; justify-content: center;
  border-radius: 9999px; border: 2px solid; transition: transform .15s; }
.badge-chip:active { transform: scale(.92); }
.badge-on  { border-color: #fbbf24; background: #fffbeb; box-shadow: 0 0 0 3px rgba(251, 191, 36, .18); }
.badge-off { border-color: #e2e8f0; background: #f8fafc; }
@media (prefers-reduced-motion: reduce) { .ring, .bar { transition: none; } }
</style>
