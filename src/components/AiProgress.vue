<script setup>
// "My game over time" — every analysed match's KPIs as small-multiple trend charts, plus the coach's
// most recent focus. Premium (early access today). Used on the profile pages and the analysis page.
import { ref, computed, onMounted, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { TREND_KEYS, seriesFor, kpiDef } from '../lib/coachKpis'
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
