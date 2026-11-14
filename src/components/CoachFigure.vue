<script setup>
// "Coach Mira" — the Badminton 360 coach character. An animated figure (ponytail, cyan top, violet
// skirt, racket) that performs any movement from the library in lib/coachMoves.js, with the cue for
// each phase shown underneath. Tap to pause/play. One still pose under prefers-reduced-motion.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { MOVES, fk, samplePose, moveDuration } from '../lib/coachMoves'

const props = defineProps({
  move:  { type: String, required: true },     // key in MOVES
  speed: { type: Number, default: 1 },
  label: { type: Boolean, default: true },     // show the ✓ / ✗ banner
})

const def = computed(() => MOVES[props.move] || MOVES.recover_good)
const t = ref(0)
const paused = ref(false)
let raf = 0, last = 0, reduce = false

function tick(now) {
  if (!last) last = now
  if (!paused.value) t.value += (now - last) * props.speed
  last = now
  raf = requestAnimationFrame(tick)
}
onMounted(() => {
  reduce = !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches
  if (reduce) { paused.value = true; t.value = stillTime() } else raf = requestAnimationFrame(tick)
})
onBeforeUnmount(() => cancelAnimationFrame(raf))
watch(() => props.move, () => { t.value = reduce ? stillTime() : 0 })

// The most telling frame (the ✓ / ✗ moment) for a still image.
function stillTime() {
  let acc = 0
  for (const f of def.value.frames) { if (/[✓✗]/.test(f.cue)) return acc + 1; acc += f.ms }
  return moveDuration(def.value) * 0.5
}
function toggle() {
  if (reduce) return
  paused.value = !paused.value
}

const s = computed(() => samplePose(def.value, t.value))
const j = computed(() => fk(s.value.pose))
const tone = computed(() => def.value.kind === 'bad' ? 'bad' : def.value.kind === 'good' ? 'good' : 'drill')
const ink = computed(() => ({ bad: '#e11d48', good: '#059669', drill: '#7c3aed' }[tone.value]))
const pts = (...p) => p.map(q => `${q.x.toFixed(1)},${q.y.toFixed(1)}`).join(' ')
// Skirt: a small flared shape hanging from the hips, following the torso lean.
const skirt = computed(() => {
  const h = j.value.hip, f = j.value.face
  return `${(h.x - 9 * f).toFixed(1)},${(h.y - 6).toFixed(1)} ${(h.x + 9 * f).toFixed(1)},${(h.y - 6).toFixed(1)} ${(h.x + 15 * f).toFixed(1)},${(h.y + 11).toFixed(1)} ${(h.x - 14 * f).toFixed(1)},${(h.y + 11).toFixed(1)}`
})
const pony = computed(() => {
  const h = j.value.head, f = j.value.face
  return `M${h.x - 6 * f},${h.y - 3} q${-12 * f},2 ${-13 * f},16`
})
const racketAngle = computed(() => {
  const a = j.value.handR, b = j.value.tipR
  return (Math.atan2(b.y - a.y, b.x - a.x) * 180) / Math.PI
})
</script>

<template>
  <div class="coach-fig" :class="`coach-fig-${tone}`">
    <div v-if="label" class="fig-tag" :style="{ background: ink }">
      {{ tone === 'bad' ? '✗ Common mistake' : tone === 'good' ? '✓ The right way' : '🏸 Drill' }}
    </div>
    <svg viewBox="6 4 228 186" class="block w-full" role="img" :aria-label="`${def.title}: ${s.cue}`" @click="toggle">
      <!-- floor + base marker -->
      <line x1="14" y1="166" x2="226" y2="166" stroke="#cbd5e1" stroke-width="2" stroke-linecap="round" />
      <g v-if="def.base">
        <ellipse cx="120" cy="167" rx="20" ry="4.5" fill="none" stroke="#0099b8" stroke-width="1.6" stroke-dasharray="4 3" />
        <text x="120" y="182" text-anchor="middle" font-size="9" font-weight="700" fill="#0099b8">BASE</text>
      </g>
      <ellipse :cx="j.hip.x" cy="167" :rx="16" ry="3.5" fill="#0f172a" opacity="0.12" />

      <!-- back leg / back arm (drawn first, lighter) -->
      <polyline :points="pts(j.hip, j.kneeB, j.footB)" fill="none" stroke="#f0b99a" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round" />
      <polyline :points="pts(j.neck, j.elbowL, j.handL)" fill="none" stroke="#f0b99a" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" />
      <!-- shoes -->
      <ellipse :cx="j.footB.x + 3 * j.face" :cy="j.footB.y - 1" rx="6.5" ry="3.2" fill="#f8fafc" stroke="#334155" stroke-width="1" />

      <!-- torso (top) -->
      <line :x1="j.hip.x" :y1="j.hip.y - 4" :x2="j.neck.x" :y2="j.neck.y + 3" stroke="#00b4d8" stroke-width="15" stroke-linecap="round" />
      <!-- skirt -->
      <polygon :points="skirt" fill="#8b5cf6" stroke="#7c3aed" stroke-width="1" stroke-linejoin="round" />

      <!-- front leg -->
      <polyline :points="pts(j.hip, j.kneeF, j.footF)" fill="none" stroke="#f6c9ad" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" />
      <ellipse :cx="j.footF.x + 3 * j.face" :cy="j.footF.y - 1" rx="7" ry="3.4" fill="#ffffff" stroke="#334155" stroke-width="1" />

      <!-- head + ponytail -->
      <path :d="pony" fill="none" stroke="#3b2417" stroke-width="5" stroke-linecap="round" />
      <circle :cx="j.head.x" :cy="j.head.y" r="9.5" fill="#f6c9ad" />
      <path :d="`M${j.head.x - 9.5},${j.head.y - 1} a9.5,9.5 0 0 1 19,0 q-9.5,-7 -19,0`" fill="#3b2417" />
      <rect :x="j.head.x - 9.5" :y="j.head.y - 4.5" width="19" height="3" rx="1.5" fill="#00b4d8" />

      <!-- racket arm + racket -->
      <polyline :points="pts(j.neck, j.elbowR, j.handR)" fill="none" stroke="#f6c9ad" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round" />
      <line :x1="j.handR.x" :y1="j.handR.y" :x2="(j.handR.x + j.tipR.x) / 2" :y2="(j.handR.y + j.tipR.y) / 2" stroke="#334155" stroke-width="2" stroke-linecap="round" />
      <ellipse :cx="j.tipR.x" :cy="j.tipR.y" rx="10" ry="6.5" fill="#ffffff" fill-opacity="0.6" :stroke="ink" stroke-width="2"
        :transform="`rotate(${racketAngle} ${j.tipR.x} ${j.tipR.y})`" />
      <!-- elbow marker so "high / low elbow" is obvious -->
      <circle :cx="j.elbowR.x" :cy="j.elbowR.y" r="3.2" :fill="ink" stroke="#fff" stroke-width="1.2" />

      <g v-if="paused && !reduce">
        <circle cx="120" cy="80" r="20" fill="#0f172a" opacity="0.55" />
        <path d="M113,69 L133,80 L113,91 Z" fill="#fff" />
      </g>
    </svg>
    <div class="fig-cue" :style="{ color: ink }">{{ s.cue }}</div>
  </div>
</template>

<style scoped>
.coach-fig { position: relative; border-radius: 1rem; overflow: hidden; border: 1.5px solid; background: #fff; cursor: pointer; }
.coach-fig-good  { border-color: #a7f3d0; background: linear-gradient(180deg, #ecfdf5, #ffffff 70%); }
.coach-fig-bad   { border-color: #fecdd3; background: linear-gradient(180deg, #fff1f2, #ffffff 70%); }
.coach-fig-drill { border-color: #ddd6fe; background: linear-gradient(180deg, #f5f3ff, #ffffff 70%); }
.fig-tag { display: inline-block; margin: 8px 0 0 8px; border-radius: 9999px; padding: 2px 9px;
  color: #fff; font-size: 10px; font-weight: 800; letter-spacing: .02em; }
.fig-cue { min-height: 2.5rem; padding: 0 .6rem .55rem; text-align: center; font-size: 12px; font-weight: 700; line-height: 1.25; }
</style>
