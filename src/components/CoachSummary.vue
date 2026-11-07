<script setup>
// AI Match Analysis — Head Coach Report (premium). The headline of Deep Coaching: per player, the
// measured KPIs ("last time → this time"), the coach's verdict (strengths, top-3 focus, drills, next-match
// goal) with an AI voice note, and the player's progress over every analysed match.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { HEADLINE_KEYS, LOCKED_KPIS, kpiDef, fmtKpi, kpiDelta, hasValue } from '../lib/coachKpis'
import AiProgress from './AiProgress.vue'

const props = defineProps({
  videoId:  { type: String, required: true },
  runId:    { type: String, default: null },       // version shown in the commentary below (admin picker)
  subjects: { type: Array, default: () => [] },    // [{ id: tag_id, name, photo }]
})

const loading = ref(true)
const players = ref([])
const activeTag = ref(null)
const audio = ref({ state: 'idle', err: '' })      // idle | loading | playing
const shownRun = ref(null)
let player = null

const p = computed(() => players.value.find(x => x.tag_id === activeTag.value) || players.value[0] || null)
const coach = computed(() => p.value?.coach || null)
const prev = computed(() => p.value?.previous?.kpis || null)
const photoOf = (tag) => props.subjects.find(s => s.id === tag)?.photo || null
const first = (n) => String(n || 'Player').trim().split(/\s+/)[0]
const tiles = computed(() => HEADLINE_KEYS.map(k => ({ def: kpiDef(k), cur: p.value?.kpis?.[k], prev: prev.value?.[k] }))
  .filter(t => hasValue(t.cur)).map(t => ({ ...t, d: kpiDelta(t.def.key, t.cur, t.prev) })))
const fmtDate = (s) => s ? new Date(s).toLocaleDateString(undefined, { day: 'numeric', month: 'short' }) : ''

async function load() {
  loading.value = true
  const { data } = await supabase.rpc('get_deep_summary', { p_video_id: props.videoId, p_run_id: props.runId })
  players.value = data?.locked ? [] : (data?.players ?? [])
  shownRun.value = data?.run_id || null
  if (!players.value.find(x => x.tag_id === activeTag.value)) activeTag.value = players.value[0]?.tag_id || null
  loading.value = false
}
onMounted(load)
watch(() => props.runId, () => { stopAudio(); load() })
watch(activeTag, stopAudio)
onBeforeUnmount(stopAudio)
defineExpose({ load })

function stopAudio() {
  if (player) { player.pause(); player = null }
  try { window.speechSynthesis?.cancel() } catch { /* ignore */ }
  audio.value = { state: 'idle', err: '' }
}
async function hearCoach() {
  if (audio.value.state !== 'idle') { stopAudio(); return }
  const script = coach.value?.script
  if (!script) return
  audio.value = { state: 'loading', err: '' }
  try {
    const { data } = await supabase.functions.invoke('commentary-audio',
      { body: { video_id: props.videoId, run_id: shownRun.value, summary_id: p.value.id } })
    if (audio.value.state !== 'loading') return
    if (data?.url) {
      player = new Audio(data.url)
      player.onended = () => { audio.value = { state: 'idle', err: '' } }
      await player.play()
      audio.value = { state: 'playing', err: '' }
      return
    }
  } catch { /* fall back */ }
  try {   // device voice fallback
    const u = new SpeechSynthesisUtterance(script)
    u.rate = 1.0
    u.onend = () => { audio.value = { state: 'idle', err: '' } }
    window.speechSynthesis.speak(u)
    audio.value = { state: 'playing', err: 'Using your device voice' }
  } catch { audio.value = { state: 'idle', err: 'Voice unavailable' } }
}
</script>

<template>
  <div v-if="loading" class="h-40 shimmer rounded-3xl" />

  <div v-else-if="players.length" class="space-y-3">
    <!-- ── HERO: the coach's verdict ───────────────────────────────────────── -->
    <div class="coach-hero relative overflow-hidden rounded-3xl p-5 text-white shadow-lg">
      <div class="relative z-10">
        <div class="flex items-center gap-2">
          <span class="rounded-full bg-white/15 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest">Head Coach Report</span>
          <span class="rounded-full bg-amber-400 px-2 py-0.5 text-[10px] font-bold uppercase text-slate-900">Premium</span>
        </div>

        <!-- player switcher -->
        <div v-if="players.length > 1" class="mt-3 flex flex-wrap gap-1.5">
          <button v-for="x in players" :key="x.tag_id" @click="activeTag = x.tag_id"
            class="flex items-center gap-1.5 rounded-full py-1 pl-1 pr-3 text-xs font-semibold transition"
            :class="p && p.tag_id === x.tag_id ? 'bg-white text-slate-900' : 'bg-white/10 text-white hover:bg-white/20'">
            <img v-if="photoOf(x.tag_id)" :src="photoOf(x.tag_id)" alt="" class="h-6 w-6 rounded-full object-cover object-top" />
            <span v-else class="flex h-6 w-6 items-center justify-center rounded-full bg-white/20 text-[10px]">{{ first(x.name)[0] }}</span>
            {{ first(x.name) }}
          </button>
        </div>

        <div class="mt-4 flex items-start gap-3">
          <img v-if="photoOf(p.tag_id)" :src="photoOf(p.tag_id)" alt=""
            class="h-16 w-16 shrink-0 rounded-2xl border-2 border-white/40 object-cover object-top shadow" />
          <div class="min-w-0">
            <div class="text-xs font-semibold text-cyan-200">{{ p.name }}</div>
            <h2 class="font-display text-xl font-bold leading-tight">
              {{ coach?.headline || 'Your coaching report' }}
            </h2>
          </div>
        </div>

        <p v-if="coach?.summary" class="mt-3 text-sm leading-relaxed text-white/85">{{ coach.summary }}</p>

        <button v-if="coach?.script" @click="hearCoach"
          class="press mt-4 flex w-full items-center justify-center gap-2 rounded-2xl bg-white py-3 text-sm font-bold text-slate-900 shadow">
          <span v-if="audio.state === 'loading'" class="coach-spin h-4 w-4 rounded-full border-2 border-slate-300 border-t-slate-900"></span>
          <span v-else>{{ audio.state === 'playing' ? '⏸' : '🔊' }}</span>
          {{ audio.state === 'loading' ? 'Your coach is preparing…' : audio.state === 'playing' ? 'Stop' : `Hear your coach, ${first(p.name)}` }}
        </button>
        <p v-if="audio.err" class="mt-1 text-center text-[10px] text-white/60">{{ audio.err }}</p>

        <div v-if="coach?.progress" class="mt-3 rounded-xl bg-white/10 px-3 py-2 text-xs text-white/90">
          📈 {{ coach.progress }}
        </div>
      </div>
    </div>

    <div v-if="!coach && !p.kpis.strokes" class="card p-4 text-center text-sm text-slate-500">
      No clear strokes from {{ first(p.name) }} were captured in this video, so there's nothing to coach yet.
      A longer clip with the whole court in view works best.
    </div>
    <div v-if="!coach && p.kpis.strokes" class="card p-4 text-center text-sm text-slate-500">
      The numbers are ready; the coach's written verdict didn't come through for this version. Re-analyse to try again.
    </div>

    <!-- ── SCOREBOARD: last time → this time ───────────────────────────────── -->
    <div v-if="p.kpis.strokes" class="card p-4">
      <div class="mb-3 flex items-end justify-between">
        <div class="font-display text-base font-bold text-slate-800">Match scorecard</div>
        <div class="text-[10px] text-slate-400">
          {{ p.kpis.strokes }} strokes<span v-if="p.previous"> · vs {{ fmtDate(p.previous.at) }}</span>
        </div>
      </div>
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
        <div v-for="t in tiles" :key="t.def.key" class="rounded-2xl border border-slate-200 bg-slate-50/60 p-3">
          <div class="text-[11px] font-semibold leading-tight text-slate-500">{{ t.def.label }}</div>
          <div class="mt-1 font-display text-2xl font-bold text-slate-800">{{ fmtKpi(t.def.key, t.cur) }}</div>
          <div v-if="t.d" class="text-[11px] font-semibold"
            :class="t.d.better === true ? 'text-emerald-600' : t.d.better === false ? 'text-rose-600' : 'text-slate-400'">
            {{ t.d.word }} {{ t.d.better === true ? 'better' : t.d.better === false ? 'worse' : '' }}
            <span class="font-normal text-slate-400">· was {{ fmtKpi(t.def.key, t.prev) }}</span>
          </div>
          <div v-if="!t.d && !hasValue(t.prev)" class="text-[11px] text-slate-400">First match tracked</div>
        </div>
      </div>
      <div class="mt-3 rounded-xl border border-dashed border-slate-300 px-3 py-2 text-[11px] text-slate-500">
        🔒 <b>{{ LOCKED_KPIS.map(k => k.label).join(' · ') }}</b> — coming with shuttle tracking. We only show what we can measure.
      </div>
    </div>

    <template v-if="coach">
      <!-- ── STRENGTHS ─────────────────────────────────────────────────────── -->
      <div v-if="coach.strengths?.length" class="card p-4">
        <div class="mb-2 font-display text-base font-bold text-slate-800">💪 What's working</div>
        <div class="space-y-2">
          <div v-for="(s, i) in coach.strengths" :key="i" class="flex gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-3">
            <span class="mt-0.5 text-emerald-600">✔</span>
            <div><div class="text-sm font-bold text-slate-800">{{ s.title }}</div>
              <div class="text-xs text-slate-600">{{ s.detail }}</div></div>
          </div>
        </div>
      </div>

      <!-- ── FOCUS ─────────────────────────────────────────────────────────── -->
      <div v-if="coach.focus?.length" class="card p-4">
        <div class="mb-1 font-display text-base font-bold text-slate-800">🎯 Your top {{ coach.focus.length }} focus areas</div>
        <p class="mb-3 text-[11px] text-slate-500">In order of what will change your game most.</p>
        <div class="space-y-2">
          <div v-for="(f, i) in coach.focus" :key="i" class="rounded-2xl border p-3"
            :class="i === 0 ? 'border-amber-300 bg-amber-50' : 'border-slate-200 bg-white'">
            <div class="flex items-center gap-2">
              <span class="flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                :class="i === 0 ? 'bg-amber-500 text-white' : 'bg-slate-200 text-slate-700'">{{ i + 1 }}</span>
              <div class="text-sm font-bold text-slate-800">{{ f.title }}</div>
              <span v-if="i === 0" class="ml-auto text-[10px] font-bold uppercase text-amber-700">Priority</span>
            </div>
            <p class="mt-1.5 text-xs text-slate-500">{{ f.why }}</p>
            <p class="mt-1 text-sm text-slate-700"><b>How:</b> {{ f.how }}</p>
          </div>
        </div>
      </div>

      <!-- ── DRILLS + GOAL ─────────────────────────────────────────────────── -->
      <div v-if="coach.drills?.length" class="card p-4">
        <div class="mb-2 font-display text-base font-bold text-slate-800">🏸 Drills for this week</div>
        <div class="space-y-2">
          <div v-for="(d, i) in coach.drills" :key="i" class="rounded-2xl border border-violet-200 bg-violet-50 p-3">
            <div class="flex items-start justify-between gap-2">
              <div class="text-sm font-bold text-slate-800">{{ d.name }}</div>
              <span v-if="d.dose" class="shrink-0 rounded-full bg-white px-2 py-0.5 text-[10px] font-semibold text-violet-700">{{ d.dose }}</span>
            </div>
            <p class="mt-1 text-xs text-slate-600">{{ d.how }}</p>
          </div>
        </div>
      </div>

      <div v-if="coach.next_goal" class="rounded-3xl border-2 border-cyan-300 bg-cyan-50 p-4 text-center">
        <div class="text-[10px] font-bold uppercase tracking-widest text-cyan-700">Your goal for the next match</div>
        <p class="mt-1 font-display text-base font-bold text-slate-800">{{ coach.next_goal }}</p>
      </div>
    </template>

    <!-- ── PROGRESS over every analysed match ────────────────────────────────── -->
    <div v-if="p.player_id" class="card p-4">
      <AiProgress :player-id="p.player_id" compact :title="`${first(p.name)}'s progress`" />
    </div>
    <p v-else class="text-center text-[11px] text-slate-400">Link this player to a roster name to track progress across matches.</p>

    <p class="px-2 text-center text-[10px] leading-relaxed text-slate-400">
      Measured with body-pose tracking: "base" is where you usually stand in that part of the match; recovery counts
      only strokes played away from it. The report and voice are AI-generated from these numbers.
    </p>
  </div>
</template>

<style scoped>
.coach-hero { background: radial-gradient(120% 90% at 100% 0%, #7c3aed 0%, transparent 55%),
                          radial-gradient(90% 80% at 0% 100%, #0891b2 0%, transparent 60%), #0f172a; }
.coach-spin { animation: cspin .8s linear infinite; }
@keyframes cspin { to { transform: rotate(360deg); } }
@media (prefers-reduced-motion: reduce) { .coach-spin { animation: none; } }
</style>
