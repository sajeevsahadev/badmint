<script setup>
// One coaching focus area, made visual: (1) the common mistake next to the correct move, performed by
// the coach figure; (2) the player's OWN ~5-second clips of that mistake, cut from their match video
// around strokes the engine measured; (3) whether it was corrected since the last analysed match.
import { ref, computed, watch, nextTick } from 'vue'
import { matchIssue, examplesFor, clipWindow, repeatStatus } from '../lib/coachMoves'
import CoachFigure from './CoachFigure.vue'

const props = defineProps({
  focus:    { type: Object, required: true },     // { title, why, how }
  index:    { type: Number, default: 0 },
  shots:    { type: Array, default: () => [] },   // analysis_shots for this run
  tagId:    { type: String, default: null },
  playUrl:  { type: String, default: '' },
  name:     { type: String, default: 'you' },
  photo:    { type: String, default: '' },
  kpis:     { type: Object, default: null },
  prevKpis: { type: Object, default: null },
  prevAt:   { type: String, default: '' },
})

const emit = defineEmits(['flag'])
const issue  = computed(() => matchIssue(props.focus))
const ex     = computed(() => examplesFor(props.shots, props.tagId, issue.value))
const status = computed(() => repeatStatus(issue.value, props.kpis, props.prevKpis))
const fmtDate = (s) => s ? new Date(s).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) : 'last match'
const fmtT = (s) => { const m = Math.floor(s / 60), x = Math.floor(s % 60); return `${m}:${String(x).padStart(2, '0')}` }

// ── My clips ──
const open = ref(false)
const mode = ref('mistakes')            // mistakes | rights
const idx  = ref(0)
const slow = ref(false)
const vid  = ref(null)
const prog = ref(0)
const clipErr = ref(false)
const list = computed(() => ex.value[mode.value] || [])
const cur  = computed(() => list.value[Math.min(idx.value, list.value.length - 1)] || null)
const win  = computed(() => cur.value ? clipWindow(issue.value, cur.value.t_s) : { start: 0, end: 0 })
const strokeAt = computed(() => {
  const span = win.value.end - win.value.start
  return span > 0 ? ((Number(cur.value?.t_s) - win.value.start) / span) * 100 : 50
})

function cue() {
  const v = vid.value
  if (!v || !cur.value) return
  try { v.playbackRate = slow.value ? 0.5 : 1; v.currentTime = win.value.start; v.play()?.catch(() => {}) } catch { /* ignore */ }
}
function onTime() {
  const v = vid.value
  if (!v) return
  const span = win.value.end - win.value.start
  prog.value = span > 0 ? Math.min(100, Math.max(0, ((v.currentTime - win.value.start) / span) * 100)) : 0
  if (v.currentTime >= win.value.end || v.currentTime < win.value.start - 0.5) v.currentTime = win.value.start
}
async function show(m) {
  mode.value = m; idx.value = 0; open.value = true; clipErr.value = false
  await nextTick(); cue()
}
// "Not a real shot": the parent removes it from this report and saves it as feedback.
function flag() {
  const s = cur.value
  if (!s?.id) return
  emit('flag', s)
  if (list.value.length <= 1) open.value = false
  else nextTick(cue)
}
function step(d) { idx.value = (idx.value + d + list.value.length) % list.value.length }
watch([idx, slow], cue)
watch(() => [props.tagId, props.focus], () => { open.value = false; idx.value = 0 })
</script>

<template>
  <div class="rounded-2xl border bg-white p-3" :class="index === 0 ? 'border-amber-300' : 'border-slate-200'">
    <div class="flex items-start gap-2">
      <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold"
        :class="index === 0 ? 'bg-amber-500 text-white' : 'bg-slate-200 text-slate-700'">{{ index + 1 }}</span>
      <div class="min-w-0 flex-1">
        <div class="font-display text-[15px] font-bold leading-snug text-slate-800">{{ focus.title }}</div>
        <div v-if="status" class="mt-1 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold"
          :class="status.state === 'improving' || status.state === 'ok' ? 'bg-emerald-100 text-emerald-700' : 'bg-rose-100 text-rose-700'">
          <template v-if="status.state === 'improving'">▲ Improving — up {{ status.diff }} pts since {{ fmtDate(prevAt) }}</template>
          <template v-else-if="status.state === 'ok'">✓ Holding well since {{ fmtDate(prevAt) }}</template>
          <template v-else-if="status.state === 'worse'">⚠ Slipped {{ Math.abs(status.diff) }} pts since {{ fmtDate(prevAt) }}</template>
          <template v-else>↻ Same as {{ fmtDate(prevAt) }} — not corrected yet</template>
        </div>
      </div>
      <span v-if="index === 0" class="shrink-0 text-[10px] font-bold uppercase text-amber-700">Fix first</span>
    </div>

    <p class="mt-2 text-sm text-slate-700"><b>Do this:</b> {{ focus.how }}</p>
    <p v-if="status && (status.state === 'repeated' || status.state === 'worse')"
      class="mt-2 rounded-xl bg-rose-50 px-3 py-2 text-xs font-semibold text-rose-700">
      This was {{ Math.round(status.prev) }}% last time and is {{ Math.round(status.cur) }}% now. Watching won't fix it — do the drill below this week.
    </p>

    <!-- The mistake next to the correct move -->
    <div v-if="issue" class="mt-3 grid grid-cols-2 gap-2">
      <CoachFigure :move="issue.bad" />
      <CoachFigure :move="issue.good" />
    </div>
    <p v-if="issue" class="mt-1 text-center text-[10px] text-slate-400">Coach Mira shows both — tap a picture to pause.</p>

    <!-- The player's own clips -->
    <div v-if="issue && playUrl && (ex.mistakes.length || ex.rights.length)" class="mt-3">
      <div v-if="!open" class="grid gap-2" :class="ex.mistakes.length && ex.rights.length ? 'grid-cols-2' : 'grid-cols-1'">
        <button v-if="ex.mistakes.length" @click="show('mistakes')" class="press rounded-xl bg-rose-600 px-3 py-2.5 text-xs font-bold text-white">
          ▶ Watch my mistake <span class="font-normal opacity-80">· {{ ex.mistakes.length }} found</span>
        </button>
        <button v-if="ex.rights.length" @click="show('rights')" class="press rounded-xl bg-emerald-600 px-3 py-2.5 text-xs font-bold text-white">
          ▶ One I got right <span class="font-normal opacity-80">· {{ ex.rights.length }}</span>
        </button>
      </div>

      <div v-else class="overflow-hidden rounded-xl border" :class="mode === 'mistakes' ? 'border-rose-200' : 'border-emerald-200'">
        <div class="relative bg-black">
          <video ref="vid" :src="playUrl" muted playsinline preload="metadata" class="w-full"
            @loadedmetadata="cue" @timeupdate="onTime" @error="clipErr = true" @click="vid.paused ? vid.play() : vid.pause()"></video>
          <div class="absolute left-2 top-2 flex items-center gap-1.5 rounded-full bg-black/65 py-0.5 pl-0.5 pr-2 text-[10px] font-bold text-white">
            <img v-if="photo" :src="photo" alt="" class="h-5 w-5 rounded-full object-cover object-top" />
            <span v-else class="pl-1.5"></span>Watch {{ name }}
          </div>
          <div class="absolute right-2 top-2 rounded-full px-2 py-0.5 text-[10px] font-bold text-white"
            :class="mode === 'mistakes' ? 'bg-rose-600' : 'bg-emerald-600'">
            {{ mode === 'mistakes' ? '✗ Mistake' : '✓ Done right' }} · {{ fmtT(cur?.t_s || 0) }}
          </div>
        </div>
        <!-- clip timeline: the dot marks the stroke -->
        <div class="relative h-1.5 bg-slate-200">
          <div class="h-full" :class="mode === 'mistakes' ? 'bg-rose-500' : 'bg-emerald-500'" :style="{ width: prog + '%' }"></div>
          <span class="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white bg-slate-900"
            :style="{ left: strokeAt + '%' }" title="The stroke"></span>
        </div>
        <div class="space-y-2 p-2.5">
          <p v-if="clipErr" class="text-center text-xs text-rose-600">The clip couldn't load here — play the main video at {{ fmtT(cur?.t_s || 0) }} instead.</p>
          <p v-if="!clipErr" class="text-center text-xs text-slate-600">
            <template v-if="mode === 'mistakes'">At the dot: <b>{{ issue.seen }}</b>.</template>
            <template v-else>At the dot you did it properly — copy this one.</template>
          </p>
          <div class="flex items-center gap-1.5">
            <button @click="step(-1)" :disabled="list.length < 2" class="btn-ghost px-3 py-1.5 text-xs disabled:opacity-40" aria-label="Previous clip">‹</button>
            <div class="flex-1 text-center text-[11px] font-semibold text-slate-500">Clip {{ Math.min(idx, list.length - 1) + 1 }} of {{ list.length }}</div>
            <button @click="step(1)" :disabled="list.length < 2" class="btn-ghost px-3 py-1.5 text-xs disabled:opacity-40" aria-label="Next clip">›</button>
            <button @click="slow = !slow" class="rounded-lg px-2.5 py-1.5 text-xs font-bold"
              :class="slow ? 'bg-slate-800 text-white' : 'btn-ghost'">½× slow</button>
          </div>
          <div class="flex gap-1.5">
            <button v-if="mode === 'mistakes' && ex.rights.length" @click="show('rights')" class="btn-ghost flex-1 py-1.5 text-[11px]">✓ Show one I got right</button>
            <button v-if="mode === 'rights' && ex.mistakes.length" @click="show('mistakes')" class="btn-ghost flex-1 py-1.5 text-[11px]">✗ Back to my mistakes</button>
            <button @click="open = false" class="btn-ghost flex-1 py-1.5 text-[11px]">Close</button>
          </div>
          <button v-if="cur?.id" @click="flag"
            class="w-full rounded-lg border border-slate-200 py-2 text-[11px] font-semibold text-slate-600 hover:border-rose-300 hover:text-rose-700">
            Not a real shot? (picking up or passing the shuttle) — remove it
          </button>
        </div>
      </div>
    </div>
    <p v-else-if="issue && issue.kpi && !ex.mistakes.length && shots.length" class="mt-3 rounded-xl bg-emerald-50 px-3 py-2 text-center text-xs text-emerald-700">
      No clear example of this mistake was measured in this video.
    </p>

    <details class="mt-2">
      <summary class="cursor-pointer text-[11px] font-semibold text-slate-400">The numbers behind this</summary>
      <p class="mt-1 text-xs text-slate-500">{{ focus.why }}</p>
      <p v-if="issue && !issue.kpi" class="mt-1 text-[11px] text-slate-400">We can't yet measure this one stroke by stroke, so there are no clips for it.</p>
    </details>
  </div>
</template>
