<script setup>
// One KPI over time — a single-series line (no legend: the title names it). Hover/tap a point for the
// match, date and value. A visually-hidden table carries the same data for screen readers.
import { ref, computed } from 'vue'
import { fmtKpi, kpiDelta } from '../lib/coachKpis'

const props = defineProps({
  def:    { type: Object, required: true },        // KPI definition from coachKpis
  points: { type: Array, default: () => [] },      // [{ at, value, video }] oldest first
})

const W = 300, H = 110, PL = 30, PR = 10, PT = 12, PB = 22
const hover = ref(null)

const domain = computed(() => {
  const vals = props.points.map(p => p.value)
  let lo = Math.min(...vals), hi = Math.max(...vals)
  if (props.def.unit === '%') { lo = Math.min(lo, 0); hi = Math.max(hi, 100) }
  else { lo = Math.min(lo, 0) }
  if (hi === lo) hi = lo + 1
  return [lo, hi]
})
const x = (i) => props.points.length === 1 ? (PL + W - PR) / 2 : PL + (i / (props.points.length - 1)) * (W - PL - PR)
const y = (v) => PT + (1 - (v - domain.value[0]) / (domain.value[1] - domain.value[0])) * (H - PT - PB)
const path = computed(() => props.points.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.value).toFixed(1)}`).join(' '))
const ticks = computed(() => [domain.value[0], (domain.value[0] + domain.value[1]) / 2, domain.value[1]])
const last = computed(() => props.points[props.points.length - 1])
const prev = computed(() => props.points[props.points.length - 2])
const delta = computed(() => last.value && prev.value ? kpiDelta(props.def.key, last.value.value, prev.value.value) : null)
const fmtDate = (s) => new Date(s).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })

// Colour tells the story at a glance: green = better than where you started, red = worse.
const overall = computed(() => props.points.length > 1 ? kpiDelta(props.def.key, last.value.value, props.points[0].value) : null)
const ink = computed(() => overall.value?.better === true ? '#059669' : overall.value?.better === false ? '#e11d48' : '#0099b8')
const area = computed(() => props.points.length < 2 ? '' :
  `${path.value} L${x(props.points.length - 1).toFixed(1)},${H - PB} L${x(0).toFixed(1)},${H - PB} Z`)
// Personal best (only where a direction is "better").
const bestIdx = computed(() => {
  if (!props.def.better || props.points.length < 2) return -1
  const vals = props.points.map(p => p.value)
  const b = props.def.better === 'up' ? Math.max(...vals) : Math.min(...vals)
  return vals.lastIndexOf(b)
})
const gid = computed(() => `kg-${props.def.key}`)
const tick = (v) => props.def.unit === '%' ? `${Math.round(v)}%` : (Math.abs(v) >= 10 ? Math.round(v) : Math.round(v * 10) / 10)
</script>

<template>
  <div class="rounded-2xl border border-slate-200 bg-white p-3">
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <div class="truncate text-xs font-bold text-slate-700">{{ def.label }}</div>
        <div class="text-[10px] text-slate-400">{{ def.better === 'down' ? 'Lower is better' : def.better === 'up' ? 'Higher is better' : 'For context' }}</div>
      </div>
      <div class="shrink-0 text-right">
        <div class="font-display text-lg font-bold leading-none text-slate-800">{{ last ? fmtKpi(def.key, last.value) : '—' }}</div>
        <div v-if="delta" class="mt-0.5 text-[10px] font-semibold"
          :class="delta.better === true ? 'text-emerald-600' : delta.better === false ? 'text-rose-600' : 'text-slate-400'">
          {{ delta.word }}{{ delta.better === true ? ' better' : delta.better === false ? ' worse' : '' }}
        </div>
      </div>
    </div>

    <div v-if="points.length < 2" class="mt-2 rounded-lg bg-slate-50 py-4 text-center text-[11px] text-slate-400">
      Your trend appears after your second analysed match.
    </div>
    <div v-else class="relative mt-1">
      <svg :viewBox="`0 0 ${W} ${H}`" class="w-full" role="img"
        :aria-label="`${def.label}: ${points.map(p => fmtKpi(def.key, p.value)).join(', ')}`"
        @mouseleave="hover = null">
        <g v-for="t in ticks" :key="t">
          <line :x1="PL" :x2="W - PR" :y1="y(t)" :y2="y(t)" stroke="#e2e8f0" stroke-width="1" />
          <text :x="PL - 4" :y="y(t) + 3" text-anchor="end" font-size="9" fill="#94a3b8">{{ tick(t) }}</text>
        </g>
        <text :x="PL" :y="H - 6" font-size="9" fill="#94a3b8">{{ fmtDate(points[0].at) }}</text>
        <text :x="W - PR" :y="H - 6" font-size="9" fill="#94a3b8" text-anchor="end">{{ fmtDate(last.at) }}</text>
        <defs>
          <linearGradient :id="gid" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" :stop-color="ink" stop-opacity="0.28" /><stop offset="100%" :stop-color="ink" stop-opacity="0" />
          </linearGradient>
        </defs>
        <path :d="area" :fill="`url(#${gid})`" />
        <path :d="path" fill="none" :stroke="ink" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"
          pathLength="1" class="draw" />
        <line v-if="hover !== null" :x1="x(hover)" :x2="x(hover)" :y1="PT" :y2="H - PB" stroke="#cbd5e1" stroke-width="1" />
        <g v-for="(p, i) in points" :key="i">
          <circle :cx="x(i)" :cy="y(p.value)" :r="hover === i || i === points.length - 1 ? 5.5 : 4"
            :fill="ink" stroke="#fff" stroke-width="2" />
          <text v-if="i === bestIdx" :x="x(i)" :y="y(p.value) - 8" text-anchor="middle" font-size="11">⭐</text>
          <!-- generous hit target -->
          <rect :x="x(i) - 14" :y="0" width="28" :height="H" fill="transparent"
            @mouseenter="hover = i" @click="hover = hover === i ? null : i" />
        </g>
      </svg>
      <div v-if="hover !== null"
        class="pointer-events-none absolute top-0 z-10 -translate-x-1/2 whitespace-nowrap rounded-lg bg-slate-800 px-2 py-1 text-[10px] text-white shadow"
        :style="{ left: `${(x(hover) / W) * 100}%` }">
        <b>{{ fmtKpi(def.key, points[hover].value) }}</b> · {{ fmtDate(points[hover].at) }}
        <span v-if="points[hover].strokes"> · {{ points[hover].strokes }} strokes</span>
        <span v-if="hover === bestIdx"> · ⭐ your best</span>
      </div>
      <p class="text-center text-[10px] text-slate-400">
        <template v-if="bestIdx === points.length - 1">⭐ Your best so far — this match</template>
        <template v-else-if="bestIdx >= 0">⭐ Best: {{ fmtKpi(def.key, points[bestIdx].value) }} on {{ fmtDate(points[bestIdx].at) }} · tap a dot</template>
        <template v-else>Tap a dot for the match</template>
      </p>
      <table class="sr-only">
        <caption>{{ def.label }} by match</caption>
        <tr><th>Date</th><th>Match</th><th>Value</th></tr>
        <tr v-for="(p, i) in points" :key="'r' + i"><td>{{ fmtDate(p.at) }}</td><td>{{ p.video }}</td><td>{{ fmtKpi(def.key, p.value) }}</td></tr>
      </table>
    </div>
  </div>
</template>

<style scoped>
.draw { stroke-dasharray: 1; stroke-dashoffset: 1; animation: kdraw 1.1s ease forwards; }
@keyframes kdraw { to { stroke-dashoffset: 0; } }
@media (prefers-reduced-motion: reduce) { .draw { animation: none; stroke-dashoffset: 0; } }
</style>
