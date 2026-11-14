<script setup>
// AI Match Analysis — Head Coach Report (premium). The headline of Deep Coaching: per player, the
// measured KPIs ("last time → this time"), the coach's verdict (strengths, top-3 focus, drills, next-match
// goal) with an AI voice note, and the player's progress over every analysed match.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { supabase } from '../lib/supabase'
import { HEADLINE_KEYS, LOCKED_KPIS, kpiDef, fmtKpi, kpiDelta, hasValue } from '../lib/coachKpis'
import AiProgress from './AiProgress.vue'
import FocusCoach from './FocusCoach.vue'
import CoachFigure from './CoachFigure.vue'
import { matchDrill, staminaCheck, shuttleConfirmed } from '../lib/coachMoves'

const props = defineProps({
  videoId:  { type: String, required: true },
  runId:    { type: String, default: null },       // version shown in the commentary below (admin picker)
  subjects: { type: Array, default: () => [] },    // [{ id: tag_id, name, photo }]
  playUrl:  { type: String, default: '' },         // match video, for the "watch my mistake" clips
})

// Simple (default) shows the verdict, the fixes and the drills. Detailed adds every number.
const VIEW_KEY = 'b360_coach_view'
const detailed = ref(false)
try { detailed.value = localStorage.getItem(VIEW_KEY) === 'detailed' } catch { /* ignore */ }
function setView(d) { detailed.value = d; try { localStorage.setItem(VIEW_KEY, d ? 'detailed' : 'simple') } catch { /* ignore */ } }

const shots = ref([])          // measured strokes of this run (clips + stamina)
const focusIdx = ref(0)
const openDrill = ref(0)

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
  focusIdx.value = 0
  if (!players.value.find(x => x.tag_id === activeTag.value)) activeTag.value = players.value[0]?.tag_id || null
  loading.value = false
  loadShots()
}
async function loadShots() {
  if (!shownRun.value) { shots.value = []; return }
  const { data } = await supabase.rpc('get_deep_analysis', { p_video_id: props.videoId, p_run_id: shownRun.value })
  // Strokes someone marked "not a real shot" are left out of clips and the stamina check.
  const { data: fb } = await supabase.from('shot_feedback').select('shot_id').eq('video_id', props.videoId)
  const gone = new Set((fb ?? []).map(f => f.shot_id))
  shots.value = (data?.shots ?? []).filter(s => !s.is_mock && !gone.has(s.id))
}
const removed = ref(null)       // last stroke marked "not a real shot" (for Undo)
const flagErr = ref('')
async function flagShot(s) {
  flagErr.value = ''
  const { error } = await supabase.rpc('flag_shot', { p_shot_id: s.id })
  if (error) { flagErr.value = error.message; return }
  shots.value = shots.value.filter(x => x.id !== s.id)
  removed.value = s
}
async function undoFlag() {
  const s = removed.value
  if (!s) return
  const { error } = await supabase.rpc('unflag_shot', { p_shot_id: s.id })
  if (error) { flagErr.value = error.message; return }
  shots.value = [...shots.value, s].sort((a, b) => Number(a.t_s) - Number(b.t_s))
  removed.value = null
}
onMounted(load)
watch(() => props.runId, () => { stopAudio(); load() })
watch(activeTag, () => { stopAudio(); focusIdx.value = 0; openDrill.value = 0 })

const verified = computed(() => shuttleConfirmed(shots.value))
const stamina = computed(() => p.value && verified.value ? staminaCheck(shots.value, p.value.tag_id) : null)
const drills = computed(() => (coach.value?.drills || []).map(d => ({ ...d, move: matchDrill(d) })))

// "Done this week" ticks — a per-device reminder only (not synced), keyed by player + drill + ISO week.
const week = (() => { const d = new Date(); const j = new Date(d.getFullYear(), 0, 1); return `${d.getFullYear()}w${Math.ceil(((d - j) / 864e5 + j.getDay() + 1) / 7)}` })()
const doneTick = ref(0)
const drillKey = (d) => `b360_drill_${p.value?.player_id || p.value?.tag_id}_${week}_${String(d.name).toLowerCase().replace(/\W+/g, '_').slice(0, 40)}`
function isDone(d) { doneTick.value; try { return localStorage.getItem(drillKey(d)) === '1' } catch { return false } }
function toggleDone(d) {
  try { isDone(d) ? localStorage.removeItem(drillKey(d)) : localStorage.setItem(drillKey(d), '1') } catch { /* ignore */ }
  doneTick.value++
}
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

    <!-- ── Simple / Detailed: same report, two depths ──────────────────────── -->
    <div class="flex items-center gap-1 rounded-2xl bg-slate-100 p-1" role="tablist" aria-label="How much detail">
      <button role="tab" :aria-selected="!detailed" @click="setView(false)" class="flex-1 rounded-xl py-2 text-xs font-bold transition"
        :class="!detailed ? 'bg-white text-slate-800 shadow' : 'text-slate-500'">✨ Simple</button>
      <button role="tab" :aria-selected="detailed" @click="setView(true)" class="flex-1 rounded-xl py-2 text-xs font-bold transition"
        :class="detailed ? 'bg-white text-slate-800 shadow' : 'text-slate-500'">📊 Detailed · all numbers</button>
    </div>

    <!-- ── SCOREBOARD: last time → this time (Detailed) ────────────────────── -->
    <div v-if="detailed && p.kpis.strokes" class="card p-4">
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
      <div v-if="coach.strengths?.length && !detailed" class="rounded-2xl border border-emerald-200 bg-emerald-50 px-3 py-2.5">
        <div class="text-[10px] font-bold uppercase tracking-wide text-emerald-700">💪 Already working</div>
        <div class="mt-1 flex flex-wrap gap-1.5">
          <span v-for="(s, i) in coach.strengths" :key="i" class="rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 shadow-sm">✔ {{ s.title }}</span>
        </div>
      </div>
      <div v-if="coach.strengths?.length && detailed" class="card p-4">
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
        <p class="mb-3 text-[11px] text-slate-500">One at a time. See the mistake, see the right way, then watch yourself.</p>
        <p v-if="shots.length && !verified" class="mb-3 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-800">
          Clips of your own strokes are hidden for this report: it was made without shuttle tracking, so we can't be
          sure every stroke was a real one. Re-analyse the video to get verified clips.
        </p>
        <p v-if="verified" class="mb-3 text-[11px] font-semibold text-emerald-700">✓ Strokes in this report were confirmed by shuttle tracking.</p>
        <!-- step pills -->
        <div class="mb-2 flex gap-1.5">
          <button v-for="(f, i) in coach.focus" :key="i" @click="focusIdx = i"
            class="flex-1 truncate rounded-xl px-2 py-1.5 text-[11px] font-bold transition"
            :class="focusIdx === i ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-500'">
            {{ i + 1 }} · {{ f.title }}
          </button>
        </div>
        <FocusCoach v-if="coach.focus[focusIdx]" :key="p.tag_id + ':' + focusIdx"
          :focus="coach.focus[focusIdx]" :index="focusIdx" :shots="shots" :tag-id="p.tag_id"
          :play-url="playUrl" :name="first(p.name)" :photo="photoOf(p.tag_id) || ''"
          :kpis="p.kpis" :prev-kpis="prev" :prev-at="p.previous?.at || ''" @flag="flagShot" />
        <p v-if="removed" class="mt-2 flex items-center justify-between gap-2 rounded-xl bg-slate-100 px-3 py-2 text-xs text-slate-700" role="status">
          <span>Removed — thanks, this helps the AI learn. The scores update when the video is re-analysed.</span>
          <button @click="undoFlag" class="shrink-0 font-bold text-cyan-700 underline">Undo</button>
        </p>
        <p v-if="flagErr" class="mt-2 text-xs text-rose-600">{{ flagErr }}</p>
        <div v-if="coach.focus.length > 1" class="mt-2 flex gap-2">
          <button @click="focusIdx = Math.max(0, focusIdx - 1)" :disabled="focusIdx === 0" class="btn-ghost flex-1 py-2 text-xs disabled:opacity-40">‹ Previous</button>
          <button @click="focusIdx = Math.min(coach.focus.length - 1, focusIdx + 1)" :disabled="focusIdx === coach.focus.length - 1"
            class="btn-primary flex-1 py-2 text-xs disabled:opacity-40">Next fix ›</button>
        </div>
      </div>

      <!-- ── DRILLS + GOAL ─────────────────────────────────────────────────── -->
      <div v-if="coach.drills?.length" class="card p-4">
        <div class="mb-2 font-display text-base font-bold text-slate-800">🏸 Drills for this week</div>
        <div class="space-y-2">
          <div v-for="(d, i) in drills" :key="i" class="overflow-hidden rounded-2xl border"
            :class="isDone(d) ? 'border-emerald-300 bg-emerald-50' : 'border-violet-200 bg-violet-50'">
            <button @click="openDrill = openDrill === i ? -1 : i" class="flex w-full items-center gap-2 p-3 text-left">
              <span class="text-base">{{ isDone(d) ? '✅' : '🏸' }}</span>
              <span class="min-w-0 flex-1 text-sm font-bold text-slate-800">{{ d.name }}</span>
              <span v-if="d.dose" class="shrink-0 rounded-full bg-white px-2 py-0.5 text-[10px] font-semibold text-violet-700">{{ d.dose }}</span>
              <span class="shrink-0 text-slate-400">{{ openDrill === i ? '▴' : '▾' }}</span>
            </button>
            <div v-if="openDrill === i" class="px-3 pb-3">
              <div class="grid items-start gap-3 sm:grid-cols-2">
                <CoachFigure v-if="d.move" :move="d.move" />
                <div>
                  <p class="text-xs leading-relaxed text-slate-600">{{ d.how }}</p>
                  <button @click="toggleDone(d)" class="press mt-2 w-full rounded-xl py-2 text-xs font-bold"
                    :class="isDone(d) ? 'bg-emerald-600 text-white' : 'bg-white text-violet-700 border border-violet-300'">
                    {{ isDone(d) ? '✓ Done this week — tap to undo' : 'I did this drill this week' }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── STAMINA: first half vs second half of this player's strokes ───── -->
      <div v-if="stamina" class="card p-4">
        <div class="mb-1 font-display text-base font-bold text-slate-800">🫀 Stamina check</div>
        <p class="text-xs text-slate-500">How often you got back to base — early in the match vs late.</p>
        <div class="mt-3 space-y-2">
          <div v-for="h in [{ l: 'First half', v: stamina.first }, { l: 'Second half', v: stamina.second }]" :key="h.l" class="flex items-center gap-2">
            <span class="w-20 shrink-0 text-[11px] font-semibold text-slate-500">{{ h.l }}</span>
            <div class="h-3 flex-1 overflow-hidden rounded-full bg-slate-100">
              <div class="stam-bar h-full rounded-full" :class="h.l === 'Second half' && stamina.state === 'fade' ? 'bg-rose-500' : 'bg-cyan-500'" :style="{ width: h.v + '%' }"></div>
            </div>
            <span class="w-9 shrink-0 text-right text-xs font-bold text-slate-700">{{ h.v }}%</span>
          </div>
        </div>
        <p class="mt-3 rounded-xl px-3 py-2 text-xs font-semibold"
          :class="stamina.state === 'fade' ? 'bg-rose-50 text-rose-700' : 'bg-emerald-50 text-emerald-700'">
          <template v-if="stamina.state === 'fade'">You faded: recovery dropped {{ stamina.drop }} points in the second half. That usually points to fitness more than technique.</template>
          <template v-else-if="stamina.state === 'strong_finish'">Strong finish — your recovery was {{ Math.abs(stamina.drop) }} points better late in the match.</template>
          <template v-else>Steady — your movement held up from start to finish.</template>
        </p>
        <div v-if="stamina.state === 'fade'" class="mt-3 grid grid-cols-2 gap-2">
          <CoachFigure move="skipping" />
          <CoachFigure move="shuttle_runs" />
        </div>
        <p v-if="stamina.state === 'fade'" class="mt-2 text-xs text-slate-600">
          <b>Twice a week:</b> 6 rounds of 30 seconds fast skipping, 30 seconds rest — then 6 line-to-line sprints. Build up by one round each week.
        </p>
        <details class="mt-2">
          <summary class="cursor-pointer text-[11px] font-semibold text-slate-400">Why intervals, and how this is measured</summary>
          <p class="mt-1 text-[11px] leading-relaxed text-slate-500">
            Badminton is stop-start: at elite level a rally lasts roughly 7 seconds with about twice that to rest, and heart rate stays
            close to 90% of maximum (Phomsoupha &amp; Laffaye, <i>Sports Medicine</i>, 2015). Short hard intervals train that pattern better
            than steady jogging. Measured here from {{ stamina.n }} strokes you played away from base, split into your first and second half.
            This is general fitness guidance, not medical advice.
          </p>
        </details>
      </div>

      <div v-if="coach.next_goal" class="rounded-3xl border-2 border-cyan-300 bg-cyan-50 p-4 text-center">
        <div class="text-[10px] font-bold uppercase tracking-widest text-cyan-700">Your goal for the next match</div>
        <p class="mt-1 font-display text-base font-bold text-slate-800">{{ coach.next_goal }}</p>
      </div>
    </template>

    <!-- ── PROGRESS over every analysed match ────────────────────────────────── -->
    <div v-if="p.player_id && detailed" class="card p-4">
      <AiProgress :player-id="p.player_id" compact :title="`${first(p.name)}'s progress`" />
    </div>
    <p v-else-if="!p.player_id && detailed" class="text-center text-[11px] text-slate-400">Link this player to a roster name to track progress across matches.</p>

    <button v-if="!detailed" @click="setView(true)" class="btn-ghost w-full py-2.5 text-xs">
      📊 Want every number? Open the Detailed view — scorecard, trends and how it's measured
    </button>

    <p v-if="detailed" class="px-2 text-center text-[10px] leading-relaxed text-slate-400">
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
.stam-bar { transition: width .8s ease; }
</style>
