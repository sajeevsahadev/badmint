<script setup>
import { ref, onMounted, onUnmounted } from 'vue'

// Fullscreen fireworks + confetti celebrating the winners of a recorded match.
// Self-contained canvas animation (no libraries). Auto-dismisses; tap to skip.
const props = defineProps({
  names: { type: Array,  default: () => [] },  // winner display names
  score: { type: String, default: '' },        // e.g. "21 – 15"
  duration: { type: Number, default: 3000 },
})
const emit = defineEmits(['done'])

const canvas = ref(null)
let raf = null, running = true, startAt = 0
const COLORS = ['#22d3ee', '#a855f7', '#fbbf24', '#34d399', '#f472b6', '#60a5fa']

function done() {
  if (!running) return
  running = false
  cancelAnimationFrame(raf)
  emit('done')
}

onMounted(() => {
  const cv = canvas.value
  const ctx = cv.getContext('2d')
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  const resize = () => { cv.width = innerWidth * dpr; cv.height = innerHeight * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0) }
  resize(); window.addEventListener('resize', resize)

  const W = () => innerWidth, H = () => innerHeight
  const particles = []
  const rnd = (a, b) => a + Math.random() * (b - a)

  function burst(x, y) {
    const color = COLORS[(Math.random() * COLORS.length) | 0]
    const n = 34 + (Math.random() * 24 | 0)
    for (let i = 0; i < n; i++) {
      const ang = (Math.PI * 2 * i) / n + rnd(-0.1, 0.1)
      const spd = rnd(2.2, 6.2)
      particles.push({
        x, y, vx: Math.cos(ang) * spd, vy: Math.sin(ang) * spd,
        life: 1, decay: rnd(0.012, 0.024), color, size: rnd(1.6, 3.2),
      })
    }
  }

  let lastBurst = 0
  function frame(t) {
    if (!startAt) startAt = t
    const elapsed = t - startAt
    // fading trails
    ctx.globalCompositeOperation = 'source-over'
    ctx.fillStyle = 'rgba(6,10,20,0.22)'
    ctx.fillRect(0, 0, W(), H())
    ctx.globalCompositeOperation = 'lighter'

    // spawn bursts (stop spawning a bit before the end so they can fade out)
    if (elapsed < props.duration - 700 && t - lastBurst > 260) {
      lastBurst = t
      burst(rnd(W() * 0.15, W() * 0.85), rnd(H() * 0.15, H() * 0.5))
    }

    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i]
      p.vy += 0.055           // gravity
      p.vx *= 0.99; p.vy *= 0.99
      p.x += p.vx; p.y += p.vy
      p.life -= p.decay
      if (p.life <= 0) { particles.splice(i, 1); continue }
      ctx.globalAlpha = Math.max(p.life, 0)
      ctx.fillStyle = p.color
      ctx.beginPath(); ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2); ctx.fill()
    }
    ctx.globalAlpha = 1

    if (elapsed >= props.duration && particles.length === 0) return done()
    raf = requestAnimationFrame(frame)
  }
  // a couple of instant bursts so it kicks off with a bang
  burst(W() * 0.35, H() * 0.35); burst(W() * 0.65, H() * 0.4)
  raf = requestAnimationFrame(frame)

  const timer = setTimeout(done, props.duration + 900)
  onUnmounted(() => { clearTimeout(timer); window.removeEventListener('resize', resize) })
})
onUnmounted(() => cancelAnimationFrame(raf))
</script>

<template>
  <div class="fixed inset-0 z-[500] flex items-center justify-center overflow-hidden"
    style="background:rgba(6,10,20,0.55)" @click="done">
    <canvas ref="canvas" class="absolute inset-0 w-full h-full"></canvas>
    <div class="relative text-center px-6 pointer-events-none celebrate-pop">
      <div class="text-6xl mb-2" style="filter:drop-shadow(0 0 24px rgba(251,191,36,.7))">🏆</div>
      <div class="text-[11px] font-bold uppercase tracking-[0.3em] text-amber-300 mb-1">Winners</div>
      <div class="font-display text-3xl sm:text-4xl font-extrabold text-white leading-tight"
        style="text-shadow:0 2px 24px rgba(0,0,0,.6)">
        {{ names.join(' & ') }}
      </div>
      <div v-if="score" class="mt-2 inline-block text-sm font-bold text-white/90 bg-white/10 rounded-full px-4 py-1">
        {{ score }}
      </div>
      <div class="text-[11px] text-white/50 mt-6">tap to continue</div>
    </div>
  </div>
</template>

<style scoped>
.celebrate-pop { animation: celebrate-pop .5s cubic-bezier(.2,1.2,.3,1) both; }
@keyframes celebrate-pop {
  0%   { transform: scale(.6); opacity: 0; }
  60%  { transform: scale(1.08); opacity: 1; }
  100% { transform: scale(1); opacity: 1; }
}
</style>
