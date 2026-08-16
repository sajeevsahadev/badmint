<script setup>
import { ref, computed } from 'vue'

// Interactive Elo-progression line + area chart (pure SVG).
// Hover (mouse) or drag a finger (touch) across it to inspect any match's Elo.
const props = defineProps({
  series: { type: Array, default: () => [] },  // [{ i, elo, date? }] chronological
  height: { type: Number, default: 130 },
})

const W = 320
const P = 10

const view = computed(() => {
  const raw = props.series.filter(p => Number.isFinite(p.elo))
  if (raw.length < 2) return null
  const H = props.height
  const elos = raw.map(p => p.elo)
  let min = Math.min(...elos), max = Math.max(...elos)
  if (min === max) { min -= 20; max += 20 }
  const pad = (max - min) * 0.15 || 10
  min -= pad; max += pad
  const x = i => P + (i / (raw.length - 1)) * (W - 2 * P)
  const y = v => H - P - ((v - min) / (max - min)) * (H - 2 * P)
  const pts = raw.map((p, i) => ({ x: x(i), y: y(p.elo), elo: p.elo, date: p.date }))
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ')
  const area = `${line} L${pts[pts.length - 1].x.toFixed(1)},${H - P} L${pts[0].x.toFixed(1)},${H - P} Z`
  return { pts, line, area, H, up: raw[raw.length - 1].elo >= raw[0].elo }
})

const active = ref(-1)
const wrap = ref(null)

function onMove(e) {
  const v = view.value
  if (!v || !wrap.value) return
  const rect = wrap.value.getBoundingClientRect()
  const clientX = e.touches ? e.touches[0].clientX : e.clientX
  const frac = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
  // nearest point by its x-fraction across the viewBox
  let best = 0, bestD = Infinity
  v.pts.forEach((p, i) => { const d = Math.abs(p.x / W - frac); if (d < bestD) { bestD = d; best = i } })
  active.value = best
}
function onLeave() { active.value = -1 }

const activePt = computed(() => (view.value && active.value >= 0 ? view.value.pts[active.value] : null))
const fmtDate = d => d ? new Date(d + 'T00:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : ''
</script>

<template>
  <div v-if="view" ref="wrap" class="relative select-none" style="touch-action:none"
    @pointermove="onMove" @pointerdown="onMove" @pointerleave="onLeave" @pointerup="onLeave"
    @touchmove.passive="onMove" @touchend="onLeave">
    <svg :viewBox="`0 0 ${W} ${view.H}`" class="w-full block" :style="{ height: view.H + 'px' }" preserveAspectRatio="none">
      <defs>
        <linearGradient id="pc-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#00b4d8" stop-opacity="0.28" />
          <stop offset="100%" stop-color="#00b4d8" stop-opacity="0" />
        </linearGradient>
        <linearGradient id="pc-stroke" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#00b4d8" />
          <stop offset="100%" stop-color="#a855f7" />
        </linearGradient>
      </defs>
      <path :d="view.area" fill="url(#pc-fill)" />
      <path :d="view.line" fill="none" stroke="url(#pc-stroke)" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />

      <!-- guide line + marker for the active point -->
      <template v-if="activePt">
        <line :x1="activePt.x" :y1="0" :x2="activePt.x" :y2="view.H" stroke="rgba(15,23,42,0.18)" stroke-width="1" stroke-dasharray="3 3" />
        <circle :cx="activePt.x" :cy="activePt.y" r="4.5" fill="#fff" stroke="#0099b8" stroke-width="2.5" />
      </template>
      <!-- resting end marker when idle -->
      <circle v-else :cx="view.pts[view.pts.length-1].x" :cy="view.pts[view.pts.length-1].y" r="4"
        fill="#fff" :stroke="view.up ? '#10b981' : '#f43f5e'" stroke-width="2.5" />
    </svg>

    <!-- tooltip -->
    <div v-if="activePt" class="absolute pointer-events-none px-2 py-1 rounded-lg text-center shadow-lg"
      style="background:#0d1a2e; transform:translate(-50%,-115%); white-space:nowrap;"
      :style="{ left: (activePt.x / W * 100) + '%', top: (activePt.y / view.H * 100) + '%' }">
      <div class="text-[11px] font-bold text-white leading-none">{{ activePt.elo }}</div>
      <div v-if="activePt.date" class="text-[8px] text-slate-400 leading-none mt-0.5">{{ fmtDate(activePt.date) }}</div>
    </div>
  </div>
  <div v-else class="text-center text-xs text-slate-400 py-6">Not enough matches yet to chart a trend.</div>
</template>
