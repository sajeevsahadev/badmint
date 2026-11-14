<script setup>
// Searchable player picker: a button that opens a sheet (bottom sheet on phones, centred dialog on
// wider screens) with a type-to-filter list. Groups: club players, saved opponents, then actions
// (add the typed name as a new opponent, unknown person, leave empty).
// v-model is the tagger's "assign" string: '' | 'p:<playerId>' | 'label'.
import { ref, computed, nextTick, watch, onBeforeUnmount } from 'vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
  roster:     { type: Array,  default: () => [] },   // [{ id, display_name }]
  opponents:  { type: Array,  default: () => [] },   // [{ id, display_name }]
  taken:      { type: Object, default: () => ({}) }, // playerId -> where they are already picked
  title:      { type: String, default: 'Choose player' },
  busy:       { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue', 'create'])

const open   = ref(false)
const q      = ref('')
const active = ref(0)
const input  = ref(null)
const list   = ref(null)
const trigger = ref(null)
const uid = 'pp' + Math.random().toString(36).slice(2, 8)

const norm = (s) => String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim()
const match = (name) => !norm(q.value) || norm(name).includes(norm(q.value))

const selected = computed(() => {
  const v = props.modelValue
  if (v === 'label') return { name: 'Unknown person', kind: 'label' }
  if (!v.startsWith('p:')) return null
  const id = v.slice(2)
  const r = props.roster.find(p => p.id === id)
  if (r) return { name: r.display_name, kind: 'club' }
  const o = props.opponents.find(p => p.id === id)
  return o ? { name: o.display_name, kind: 'opp' } : null
})

// One flat list drives both rendering and keyboard movement.
const rows = computed(() => {
  const out = []
  const club = props.roster.filter(p => match(p.display_name))
  const opp  = props.opponents.filter(p => match(p.display_name))
  if (club.length) out.push({ type: 'head', text: 'Club players', n: club.length })
  for (const p of club) out.push({ type: 'opt', key: 'p:' + p.id, name: p.display_name, kind: 'club', taken: props.taken[p.id] })
  if (opp.length) out.push({ type: 'head', text: 'Saved opponents', n: opp.length })
  for (const p of opp) out.push({ type: 'opt', key: 'p:' + p.id, name: p.display_name, kind: 'opp', taken: props.taken[p.id] })
  const typed = q.value.trim()
  const exact = [...props.roster, ...props.opponents].some(p => norm(p.display_name) === norm(typed))
  out.push({ type: 'head', text: 'Not in the list?' })
  if (typed && !exact) out.push({ type: 'opt', key: 'create', name: `Add “${typed}” as a new opponent`, kind: 'create', sub: 'Saved, so you can pick them again next time' })
  out.push({ type: 'opt', key: 'label', name: 'Unknown person', kind: 'label', sub: 'Just for this video' })
  if (props.modelValue) out.push({ type: 'opt', key: '', name: 'Leave empty', kind: 'clear', sub: 'No report for this person' })
  return out.map((r, i) => ({ ...r, i }))
})
const options = computed(() => rows.value.filter(r => r.type === 'opt' && !r.taken))
const noPeople = computed(() => !rows.value.some(r => r.kind === 'club' || r.kind === 'opp'))

watch(q, () => { active.value = options.value[0]?.i ?? 0 })

function show() {
  open.value = true
  q.value = ''
  const cur = options.value.find(r => r.key === props.modelValue)
  active.value = (cur || options.value[0])?.i ?? 0
  document.documentElement.style.overflow = 'hidden'
  nextTick(() => { input.value?.focus(); scrollToActive() })
}
function hide() {
  if (!open.value) return
  open.value = false
  document.documentElement.style.overflow = ''
  nextTick(() => trigger.value?.focus())
}
onBeforeUnmount(() => { if (open.value) document.documentElement.style.overflow = '' })

function choose(r) {
  if (!r || r.taken) return
  if (r.kind === 'create') emit('create', q.value.trim())
  else emit('update:modelValue', r.key)
  hide()
}
function move(d) {
  const o = options.value
  if (!o.length) return
  const at = o.findIndex(r => r.i === active.value)
  active.value = o[(at + d + o.length) % o.length].i
  scrollToActive()
}
function scrollToActive() {
  nextTick(() => list.value?.querySelector(`#${uid}-o${active.value}`)?.scrollIntoView({ block: 'nearest' }))
}
function onKey(e) {
  if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
  else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
  else if (e.key === 'Enter') { e.preventDefault(); choose(rows.value[active.value]) }
  else if (e.key === 'Escape') { e.preventDefault(); hide() }
}

const initials = (n) => String(n || '?').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('').toUpperCase()
const tone = (k) => k === 'opp' ? 'bg-violet-100 text-violet-700' : k === 'club' ? 'bg-cyan-100 text-cyan-800' : 'bg-slate-100 text-slate-500'
</script>

<template>
  <div>
    <button ref="trigger" type="button" @click="show" :disabled="busy"
      aria-haspopup="dialog" :aria-expanded="open"
      class="mt-1 flex min-h-[44px] w-full items-center gap-2.5 rounded-xl border bg-white px-3 py-2 text-left transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400"
      :class="selected ? 'border-cyan-300' : 'border-slate-300 hover:border-cyan-300'">
      <span v-if="selected" class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[11px] font-bold" :class="tone(selected.kind)">
        {{ selected.kind === 'label' ? '?' : initials(selected.name) }}
      </span>
      <span class="min-w-0 flex-1 truncate text-sm" :class="selected ? 'font-semibold text-slate-800' : 'text-slate-500'">
        {{ selected ? selected.name : 'Choose a player…' }}
      </span>
      <span v-if="selected?.kind === 'opp'" class="shrink-0 rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-bold text-violet-700">Opponent</span>
      <svg class="h-4 w-4 shrink-0 text-slate-400" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M6 8l4 4 4-4" stroke-linecap="round" stroke-linejoin="round" /></svg>
    </button>

    <Teleport to="body">
      <Transition name="pp">
        <div v-if="open" class="fixed inset-0 z-[300] flex items-end justify-center sm:items-center sm:p-6" @keydown="onKey">
          <div class="pp-back absolute inset-0 bg-slate-900/45" @click="hide"></div>
          <div role="dialog" aria-modal="true" :aria-label="title"
            class="pp-sheet relative flex h-[80dvh] w-full flex-col overflow-hidden rounded-t-3xl bg-white shadow-2xl sm:h-auto sm:max-h-[640px] sm:max-w-md sm:rounded-3xl">
            <div class="mx-auto mt-2 h-1 w-10 rounded-full bg-slate-200 sm:hidden"></div>
            <div class="flex items-center justify-between px-4 pb-2 pt-3">
              <div class="text-base font-bold text-slate-800">{{ title }}</div>
              <button type="button" @click="hide" aria-label="Close"
                class="flex h-9 w-9 items-center justify-center rounded-full text-slate-500 hover:bg-slate-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-400">
                <svg class="h-5 w-5" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M5 5l10 10M15 5L5 15" stroke-linecap="round" /></svg>
              </button>
            </div>

            <div class="px-4 pb-3">
              <div class="relative">
                <svg class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="9" cy="9" r="6" /><path d="M14 14l4 4" stroke-linecap="round" /></svg>
                <input ref="input" v-model="q" type="text" maxlength="60" autocomplete="off" autocapitalize="words" enterkeyhint="done"
                  role="combobox" aria-autocomplete="list" aria-expanded="true" :aria-controls="uid + '-list'"
                  :aria-activedescendant="uid + '-o' + active"
                  placeholder="Type a name to search or add"
                  class="w-full rounded-xl border border-slate-200 bg-slate-50 py-2.5 pl-9 pr-3 text-base text-slate-800 placeholder:text-slate-400 focus:border-cyan-400 focus:bg-white focus:outline-none focus:ring-2 focus:ring-cyan-100" />
              </div>
            </div>

            <ul ref="list" :id="uid + '-list'" role="listbox" :aria-label="title" class="flex-1 overflow-y-auto overscroll-contain px-2 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
              <li v-if="noPeople && q.trim()" class="px-3 py-3 text-sm text-slate-500" role="presentation">
                No one called “{{ q.trim() }}” yet.
              </li>
              <template v-for="r in rows" :key="r.type + r.i">
                <li v-if="r.type === 'head'" role="presentation"
                  class="sticky top-0 z-10 flex items-center justify-between bg-white/95 px-3 pb-1 pt-3 text-[11px] font-bold uppercase tracking-wide text-slate-500">
                  <span>{{ r.text }}</span><span v-if="r.n" class="font-semibold text-slate-400">{{ r.n }}</span>
                </li>
                <li v-else :id="uid + '-o' + r.i" role="option" :aria-selected="r.key === modelValue" :aria-disabled="!!r.taken"
                  @click="choose(r)" @mousemove="!r.taken && (active = r.i)"
                  class="flex min-h-[48px] items-center gap-3 rounded-xl px-3 py-2"
                  :class="[r.taken ? 'cursor-not-allowed opacity-50' : 'cursor-pointer', active === r.i && !r.taken ? 'bg-cyan-50' : '']">
                  <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                    :class="r.kind === 'create' ? 'bg-cyan-600 text-white' : tone(r.kind)">
                    <svg v-if="r.kind === 'create'" class="h-4 w-4" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><path d="M10 4v12M4 10h12" stroke-linecap="round" /></svg>
                    <template v-else-if="r.kind === 'label'">?</template>
                    <svg v-else-if="r.kind === 'clear'" class="h-4 w-4" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M5 10h10" stroke-linecap="round" /></svg>
                    <template v-else>{{ initials(r.name) }}</template>
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-sm font-semibold" :class="r.kind === 'create' ? 'text-cyan-700' : 'text-slate-800'">{{ r.name }}</span>
                    <span v-if="r.taken || r.sub" class="block truncate text-xs text-slate-500">{{ r.taken ? 'Already picked · ' + r.taken : r.sub }}</span>
                  </span>
                  <svg v-if="r.key === modelValue && r.key" class="h-5 w-5 shrink-0 text-cyan-600" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><path d="M4 10.5l4 4 8-9" stroke-linecap="round" stroke-linejoin="round" /></svg>
                </li>
              </template>
            </ul>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.pp-enter-active { transition: opacity 0.2s ease-out; }
.pp-leave-active { transition: opacity 0.14s ease-in; }
.pp-enter-from, .pp-leave-to { opacity: 0; }
.pp-enter-active .pp-sheet { transition: transform 0.24s cubic-bezier(0.2, 0.8, 0.2, 1); }
.pp-leave-active .pp-sheet { transition: transform 0.14s ease-in; }
.pp-enter-from .pp-sheet, .pp-leave-to .pp-sheet { transform: translateY(24px); }
@media (prefers-reduced-motion: reduce) {
  .pp-enter-active, .pp-leave-active, .pp-enter-active .pp-sheet, .pp-leave-active .pp-sheet { transition: none; }
}
</style>
