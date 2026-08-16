<script setup>
import { computed } from 'vue'

// Elo-progression line + area chart (pure SVG, theme-matched).
const props = defineProps({
  series: { type: Array, default: () => [] },  // [{ i, elo }] chronological
  height: { type: Number, default: 120 },
})

const W = 320
const P = 10  // padding

const view = computed(() => {
  const pts = props.series.filter(p => Number.isFinite(p.elo))
  if (pts.length < 2) return null
  const H = props.height
  const elos = pts.map(p => p.elo)
  let min = Math.min(...elos), max = Math.max(...elos)
  if (min === max) { min -= 20; max += 20 }
  const pad = (max - min) * 0.15 || 10
  min -= pad; max += pad
  const x = i => P + (i / (pts.length - 1)) * (W - 2 * P)
  const y = v => H - P - ((v - min) / (max - min)) * (H - 2 * P)
  const coords = pts.map((p, i) => [x(i), y(p.elo)])
  const line = coords.map(([cx, cy], i) => `${i ? 'L' : 'M'}${cx.toFixed(1)},${cy.toFixed(1)}`).join(' ')
  const area = `${line} L${x(pts.length - 1).toFixed(1)},${H - P} L${x(0).toFixed(1)},${H - P} Z`
  return {
    line, area, H,
    first: pts[0].elo, last: pts[pts.length - 1].elo,
    lastX: coords[coords.length - 1][0], lastY: coords[coords.length - 1][1],
    up: pts[pts.length - 1].elo >= pts[0].elo,
  }
})
</script>

<template>
  <div v-if="view">
    <svg :viewBox="`0 0 ${W} ${view.H}`" class="w-full" :style="{ height: view.H + 'px' }" preserveAspectRatio="none">
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
      <circle :cx="view.lastX" :cy="view.lastY" r="4" fill="#fff" :stroke="view.up ? '#10b981' : '#f43f5e'" stroke-width="2.5" />
    </svg>
  </div>
  <div v-else class="text-center text-xs text-slate-400 py-6">Not enough matches yet to chart a trend.</div>
</template>
