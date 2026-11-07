<script setup>
// Per-player report, three expert lenses: Coach (primary) | Physio (injury risk) | Player (dashboard).
// Reads the stored analysis_reports.content + player_metrics for one subject tag. Confidence is
// surfaced, never hidden (whitepaper rule). Mock data is clearly badged.
import { ref, computed } from 'vue'

const props = defineProps({
  name:    { type: String, default: 'Player' },
  photo:   { type: String, default: '' },        // presigned URL of the player's crop from the video
  metrics: { type: Object, default: null },   // player_metrics row { metrics, confidence, is_mock }
  reports: { type: Array,  default: () => [] }, // analysis_reports rows for this tag
})

const lens = ref('coach')
const byLens = (l) => props.reports.find(r => r.lens === l)?.content || null
const coach  = computed(() => byLens('coach'))
const physio = computed(() => byLens('physio'))
const player = computed(() => byLens('player'))
const isMock = computed(() => props.metrics?.is_mock || props.reports.some(r => r.is_mock))

const m = computed(() => props.metrics?.metrics || {})
const conf = computed(() => props.metrics?.confidence || {})
const sevClass = (s) => ({ warning: 'border-red-200 bg-red-50', watch: 'border-amber-200 bg-amber-50', info: 'border-slate-200 bg-slate-50' }[s] || 'border-slate-200 bg-slate-50')
const sevDot = (s) => ({ warning: 'bg-red-500', watch: 'bg-amber-500', info: 'bg-cyan-500' }[s] || 'bg-cyan-500')

function lowConf(key) { const c = conf.value[key]; return typeof c === 'number' && c < 0.7 }
const shotMix = computed(() => Object.entries(m.value.shot_mix || {}))
const metricRows = computed(() => ([
  ['Court coverage', m.value.coverage_pct, '%', 'coverage_pct'],
  ['Recovery to base', m.value.recovery_s, 's', 'recovery_s'],
  ['Split-step', m.value.split_step_pct, '%', 'split_step_pct'],
  ['Net win rate', m.value.net_win_pct, '%', 'net_win_pct'],
  ['Landing safety', m.value.landing_score, '', 'landing_score'],
].filter(r => r[1] !== undefined && r[1] !== null)))
</script>

<template>
  <div class="card p-4">
    <div class="mb-3 flex items-center justify-between gap-2">
      <div class="flex min-w-0 items-center gap-2">
        <img v-if="photo" :src="photo" :alt="name" class="h-10 w-10 shrink-0 rounded-full border border-slate-200 object-cover object-top" />
        <div class="truncate font-display text-lg font-bold text-slate-800">{{ name }}</div>
      </div>
      <span v-if="isMock" class="badge-pending shrink-0">Sample data</span>
    </div>

    <!-- Lens switch -->
    <div class="mb-4 flex gap-1 rounded-xl bg-slate-100 p-1 text-sm">
      <button @click="lens = 'coach'" class="flex-1 rounded-lg py-1.5 font-semibold transition"
        :class="lens === 'coach' ? 'bg-white text-neon shadow' : 'text-slate-500'">🎯 Coach</button>
      <button @click="lens = 'physio'" class="flex-1 rounded-lg py-1.5 font-semibold transition"
        :class="lens === 'physio' ? 'bg-white text-neon shadow' : 'text-slate-500'">🩺 Physio</button>
      <button @click="lens = 'player'" class="flex-1 rounded-lg py-1.5 font-semibold transition"
        :class="lens === 'player' ? 'bg-white text-neon shadow' : 'text-slate-500'">📊 You</button>
    </div>

    <!-- COACH -->
    <div v-if="lens === 'coach'">
      <div v-if="!coach" class="py-6 text-center text-sm text-slate-400">No coaching analysis yet.</div>
      <template v-else>
        <div class="space-y-2">
          <div class="rounded-xl border border-emerald-200 bg-emerald-50 p-3">
            <div class="text-[11px] font-bold uppercase tracking-wide text-emerald-600">What you're doing well</div>
            <div class="text-sm font-semibold text-slate-800">{{ coach.well }}</div>
          </div>
          <div class="rounded-xl border border-amber-200 bg-amber-50 p-3">
            <div class="text-[11px] font-bold uppercase tracking-wide text-amber-600">What's holding you back</div>
            <div class="text-sm font-semibold text-slate-800">{{ coach.holding_back }}</div>
          </div>
          <div class="rounded-xl border border-violet-200 bg-violet-50 p-3">
            <div class="text-[11px] font-bold uppercase tracking-wide text-violet-600">Your biggest opportunity</div>
            <div class="text-sm font-semibold text-slate-800">{{ coach.opportunity }}</div>
          </div>
        </div>
        <div v-if="coach.findings?.length" class="mt-3 space-y-2">
          <div class="text-xs font-bold uppercase tracking-wide text-slate-400">Focus areas &amp; drills</div>
          <div v-for="f in coach.findings" :key="f.code" class="rounded-xl border p-3" :class="sevClass(f.severity)">
            <div class="flex items-center gap-2">
              <span class="h-2 w-2 rounded-full" :class="sevDot(f.severity)"></span>
              <span class="text-sm font-semibold text-slate-800">{{ f.title }}</span>
            </div>
            <p class="mt-1 text-xs text-slate-600">{{ f.message }}</p>
            <p v-if="f.drill" class="mt-1 text-xs text-slate-700"><b>Drill:</b> {{ f.drill }}</p>
          </div>
        </div>
      </template>
    </div>

    <!-- PHYSIO -->
    <div v-else-if="lens === 'physio'">
      <div class="mb-3 rounded-xl border border-slate-200 bg-slate-50 p-3 text-xs text-slate-500">
        {{ physio?.disclaimer || 'General movement-safety screen — not a medical diagnosis.' }}
      </div>
      <div v-if="!physio?.findings?.length" class="py-6 text-center text-sm text-emerald-600">
        ✅ No elevated movement-injury patterns detected in this video.
      </div>
      <div v-else class="space-y-2">
        <div v-for="f in physio.findings" :key="f.code" class="rounded-xl border p-3" :class="sevClass(f.severity)">
          <div class="flex items-center gap-2">
            <span class="h-2 w-2 rounded-full" :class="sevDot(f.severity)"></span>
            <span class="text-sm font-semibold text-slate-800">{{ f.title }}</span>
          </div>
          <p class="mt-1 text-xs text-slate-600">{{ f.message }}</p>
          <p v-if="f.drill" class="mt-1 text-xs text-slate-700"><b>Prevention:</b> {{ f.drill }}</p>
        </div>
      </div>
    </div>

    <!-- PLAYER -->
    <div v-else>
      <div class="flex items-center gap-4">
        <div class="relative flex h-20 w-20 shrink-0 items-center justify-center rounded-full"
          style="background: conic-gradient(#00b4d8 var(--p), #e2e8f0 0)"
          :style="{ '--p': (player?.score || 0) + '%' }">
          <div class="flex h-16 w-16 flex-col items-center justify-center rounded-full bg-white">
            <span class="text-xl font-bold text-slate-800">{{ player?.score ?? '—' }}</span>
            <span class="text-[9px] uppercase text-slate-400">score</span>
          </div>
        </div>
        <div class="min-w-0">
          <div class="text-[11px] font-bold uppercase tracking-wide text-slate-400">Today's focus</div>
          <div class="text-sm font-semibold text-slate-800">{{ player?.focus || '—' }}</div>
        </div>
      </div>

      <div v-if="metricRows.length" class="mt-4 space-y-2">
        <div class="text-xs font-bold uppercase tracking-wide text-slate-400">Your numbers</div>
        <div v-for="r in metricRows" :key="r[3]" class="flex items-center justify-between text-sm">
          <span class="text-slate-600">{{ r[0] }}</span>
          <span class="font-semibold text-slate-800">
            {{ r[1] }}{{ r[2] }}
            <span v-if="lowConf(r[3])" class="ml-1 text-[10px] font-normal text-amber-600">(estimate)</span>
          </span>
        </div>
      </div>

      <div v-if="shotMix.length" class="mt-4">
        <div class="mb-1 text-xs font-bold uppercase tracking-wide text-slate-400">Shot mix</div>
        <div class="space-y-1">
          <div v-for="[k, v] in shotMix" :key="k" class="flex items-center gap-2 text-xs">
            <span class="w-14 capitalize text-slate-500">{{ k }}</span>
            <div class="h-2 flex-1 overflow-hidden rounded-full bg-slate-100">
              <div class="h-full bg-violet-400" :style="{ width: Math.min(100, v) + '%' }"></div>
            </div>
            <span class="w-8 text-right text-slate-500">{{ v }}%</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
