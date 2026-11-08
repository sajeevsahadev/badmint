<script setup>
// Marketing hero for AI Match Analysis — an animated DOUBLES rally: four tracked players, the
// shuttle travelling side to side over many strokes, and on every stroke the AI tags the shot
// with a technique check and a coach tip. Pure SVG driven by requestAnimationFrame; shows a
// single still frame under prefers-reduced-motion.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'

// Base positions (viewBox 640x360). 0,1 = near team (You / Partner) · 2,3 = far team.
const BASE = [
  { x: 230, y: 268, label: 'You',     team: 'near' },
  { x: 410, y: 268, label: 'Partner', team: 'near' },
  { x: 268, y: 128, label: 'Opp 1',   team: 'far'  },
  { x: 372, y: 128, label: 'Opp 2',   team: 'far'  },
]

// One rally. from/to = player index; arc = how high the shuttle flies.
const STROKES = [
  { from: 0, to: 3, arc: 30,  shot: 'Short serve', ok: true,  check: 'Racket head up',        tip: 'Nice — low and tight over the net.' },
  { from: 3, to: 1, arc: 110, shot: 'Lift',        ok: true,  check: 'Deep lunge',            tip: 'Good lunge — knee stays over the toes.' },
  { from: 1, to: 2, arc: 150, shot: 'Clear',       ok: true,  check: 'High elbow',            tip: 'Elbow high, contact above the head. Perfect.' },
  { from: 2, to: 0, arc: 60,  shot: 'Drop',        ok: true,  check: 'Disguised',             tip: 'Same preparation as a smash — hard to read.' },
  { from: 0, to: 3, arc: 25,  shot: 'Net shot',    ok: false, check: 'Late to the net',       tip: 'Step in earlier — meet the shuttle higher.' },
  { from: 3, to: 1, arc: 120, shot: 'Lift',        ok: false, check: 'Slow recovery 0.9 s',   tip: 'Push back to base right after the shot.' },
  { from: 1, to: 2, arc: 45,  shot: 'Jump smash · 291 km/h', ok: true, check: 'Wrist snap', tip: 'Great power. Partner — move up to the net!' },
  { from: 2, to: 0, arc: 20,  shot: 'Block',       ok: true,  check: 'Front-back rotation',   tip: 'You took the net, partner covered the back.' },
]
const DUR = 2200   // ms per stroke — long enough to read the coach tip

const t = ref(0)           // stroke progress 0..1
const idx = ref(2)         // current stroke
const shots = ref(3)
let raf = 0, start = 0

function frame(now) {
  if (!start) start = now
  const el = now - start
  const n = Math.floor(el / DUR)
  idx.value = n % STROKES.length
  shots.value = (n % 24) + 1
  t.value = (el % DUR) / DUR
  raf = requestAnimationFrame(frame)
}
onMounted(() => {
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) { t.value = 0.55; return }
  raf = requestAnimationFrame(frame)
})
onBeforeUnmount(() => cancelAnimationFrame(raf))

const stroke = computed(() => STROKES[idx.value])
const ease = (x) => x < 0.5 ? 2 * x * x : 1 - Math.pow(-2 * x + 2, 2) / 2

// Receiver glides toward where the shuttle lands; everyone else drifts back to base.
const players = computed(() => BASE.map((p, i) => {
  const s = stroke.value
  let dx = 0, dy = 0
  if (i === s.to) { dx = (p.x < 320 ? -14 : 14) * ease(t.value); dy = (p.team === 'near' ? 10 : -8) * ease(t.value) }
  return { ...p, x: p.x + dx, y: p.y + dy, hitting: i === s.from && t.value < 0.45, receiving: i === s.to }
}))

const hand = (p) => ({ x: p.x + (p.x < 320 ? 16 : -16), y: p.y - 46 })
const shuttle = computed(() => {
  const s = stroke.value
  const a = hand(players.value[s.from]), b = hand(players.value[s.to])
  const c = { x: (a.x + b.x) / 2, y: Math.min(a.y, b.y) - s.arc }
  const u = ease(t.value), v = 1 - u
  return {
    x: v * v * a.x + 2 * v * u * c.x + u * u * b.x,
    y: v * v * a.y + 2 * v * u * c.y + u * u * b.y,
    path: `M${a.x},${a.y} Q${c.x},${c.y} ${b.x},${b.y}`,
  }
})

// Technique tag floats above the hitter for the first part of each stroke.
const tag = computed(() => {
  const p = players.value[stroke.value.from]
  const w = Math.max(stroke.value.shot.length, stroke.value.check.length + 2) * 6.4 + 20
  const x = Math.min(Math.max(p.x - w / 2, 12), 628 - w)
  const y = p.team === 'near' ? p.y - 118 : p.y - 100
  return { x, y, w, show: t.value < 0.8 }
})
const rally = computed(() => ((shots.value - 1) * DUR / 1000 + t.value * DUR / 1000).toFixed(1))
</script>

<template>
  <div class="ai-hero">
    <svg viewBox="0 0 640 360" class="w-full h-auto block" role="img"
      aria-label="AI analysing a doubles rally: each shot is tagged with a technique check and a coach tip"
      xmlns="http://www.w3.org/2000/svg" font-family="Outfit, sans-serif">
      <defs>
        <linearGradient id="aiCourt" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#1f8a63" /><stop offset="100%" stop-color="#145c42" />
        </linearGradient>
        <linearGradient id="aiBg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#0b2a4a" /><stop offset="55%" stop-color="#0e2947" /><stop offset="100%" stop-color="#141d3a" />
        </linearGradient>
        <radialGradient id="aiGlow" cx="50%" cy="40%" r="60%">
          <stop offset="0%" stop-color="#22d3ee" stop-opacity="0.3" /><stop offset="100%" stop-color="#22d3ee" stop-opacity="0" />
        </radialGradient>
      </defs>

      <rect width="640" height="360" fill="url(#aiBg)" rx="14" />
      <ellipse cx="320" cy="180" rx="280" ry="150" fill="url(#aiGlow)" />

      <!-- Court (doubles lines) -->
      <polygon points="170,82 470,82 570,296 70,296" fill="url(#aiCourt)" />
      <g stroke="#fff" stroke-opacity="0.65" stroke-width="1.4" fill="none">
        <polygon points="170,82 470,82 570,296 70,296" />
        <line x1="135" y1="160" x2="505" y2="160" stroke-opacity="0.35" />
        <line x1="112" y1="222" x2="528" y2="222" stroke-opacity="0.35" />
        <line x1="320" y1="82" x2="320" y2="160" stroke-opacity="0.35" />
        <line x1="320" y1="222" x2="320" y2="296" stroke-opacity="0.35" />
      </g>
      <!-- Net -->
      <line x1="122" y1="190" x2="518" y2="190" stroke="#e2e8f0" stroke-width="3" />
      <line x1="122" y1="176" x2="518" y2="176" stroke="#e2e8f0" stroke-width="1" stroke-opacity="0.6" />

      <!-- Shuttle trail -->
      <path :d="shuttle.path" fill="none" stroke="#e2f8ff" stroke-width="1.6" stroke-dasharray="4 6" stroke-opacity="0.55" />

      <!-- Players -->
      <g v-for="(p, i) in players" :key="i">
        <ellipse :cx="p.x" :cy="p.y + 2" rx="22" ry="6" :fill="p.team === 'near' ? '#22d3ee' : '#fbbf24'" opacity="0.2" />
        <!-- body -->
        <g stroke="#f8fafc" stroke-width="3.2" stroke-linecap="round" fill="none">
          <line :x1="p.x" :y1="p.y - 34" :x2="p.x" :y2="p.y - 14" />
          <line :x1="p.x" :y1="p.y - 14" :x2="p.x - 8" :y2="p.y" />
          <line :x1="p.x" :y1="p.y - 14" :x2="p.x + 8" :y2="p.y" />
          <line :x1="p.x" :y1="p.y - 30" :x2="hand(p).x" :y2="p.hitting ? hand(p).y : p.y - 22" />
        </g>
        <circle :cx="p.x" :cy="p.y - 41" r="6" fill="#f8fafc" />
        <!-- racket -->
        <ellipse :cx="hand(p).x + (p.x < 320 ? 4 : -4)" :cy="(p.hitting ? hand(p).y : p.y - 22) - 9" rx="5" ry="7"
          fill="none" stroke="#a5f3fc" stroke-width="1.6" />
        <!-- tracking box -->
        <rect :x="p.x - 24" :y="p.y - 54" width="48" height="60" rx="5" fill="none"
          :stroke="p.team === 'near' ? '#22d3ee' : '#fbbf24'"
          :stroke-width="p.hitting ? 3 : 1.8" :stroke-opacity="p.hitting || p.receiving ? 1 : 0.55" />
        <rect :x="p.x - 24" :y="p.y - 68" :width="p.label.length * 6.2 + 12" height="13" rx="3"
          :fill="p.team === 'near' ? '#0e7490' : '#b45309'" />
        <text :x="p.x - 18" :y="p.y - 58" fill="#fff" font-size="9" font-weight="700">{{ p.label }}</text>
      </g>

      <!-- Shuttle -->
      <circle :cx="shuttle.x" :cy="shuttle.y" r="9" fill="#fff" fill-opacity="0.22" />
      <circle :cx="shuttle.x" :cy="shuttle.y" r="4" fill="#fff" />

      <!-- AI technique tag on the hitter -->
      <g v-if="tag.show">
        <rect :x="tag.x" :y="tag.y" :width="tag.w" height="34" rx="7" fill="#020617" fill-opacity="0.82"
          :stroke="stroke.ok ? '#34d399' : '#fbbf24'" stroke-width="1.4" />
        <text :x="tag.x + 9" :y="tag.y + 14" fill="#fff" font-size="10.5" font-weight="800">{{ stroke.shot }}</text>
        <text :x="tag.x + 9" :y="tag.y + 27" :fill="stroke.ok ? '#6ee7b7' : '#fcd34d'" font-size="9.5" font-weight="600">
          {{ stroke.ok ? '✓' : '!' }} {{ stroke.check }}
        </text>
      </g>

      <!-- Stats strip -->
      <g>
        <text x="28" y="34" fill="#67e8f9" font-size="9" letter-spacing="1">RALLY</text>
        <text x="28" y="50" fill="#fff" font-size="14" font-weight="800">{{ rally }}s</text>
        <text x="104" y="34" fill="#67e8f9" font-size="9" letter-spacing="1">SHOTS</text>
        <text x="104" y="50" fill="#fff" font-size="14" font-weight="800">{{ shots }}</text>
      </g>
      <g>
        <rect x="486" y="22" width="132" height="26" rx="13" fill="#000" opacity="0.45" />
        <circle class="pulse" cx="502" cy="35" r="4" fill="#34d399" />
        <text x="513" y="39" fill="#fff" font-size="11.5" font-weight="600">AI coach · live</text>
      </g>

      <!-- Coach says -->
      <g>
        <rect x="20" y="308" width="600" height="38" rx="10" fill="#000" fill-opacity="0.55" />
        <text x="34" y="331" font-size="18">🧑‍🏫</text>
        <text x="62" y="323" fill="#94a3b8" font-size="8.5" letter-spacing="1">COACH</text>
        <text x="62" y="338" fill="#fff" font-size="12" font-weight="600">{{ stroke.tip }}</text>
      </g>
    </svg>
  </div>
</template>

<style scoped>
.ai-hero { border-radius: 14px; overflow: hidden; box-shadow: 0 16px 40px rgba(2, 32, 71, 0.18); }
.pulse { animation: aiPulse 1.3s ease-in-out infinite; }
@keyframes aiPulse { 0%,100% { opacity: 1; } 50% { opacity: 0.35; } }
</style>
