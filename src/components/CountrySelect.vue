<script setup>
import { ref, computed, nextTick, onBeforeUnmount } from 'vue'
import { COUNTRIES, countryName } from '../utils/countries'
import { useGeo } from '../composables/useGeo'

const props = defineProps({ modelValue: { type: String, default: '' } })
const emit  = defineEmits(['update:modelValue'])
const { flagEmoji } = useGeo()

const open = ref(false)
const q    = ref('')
const btn  = ref(null)
// Panel is teleported to <body> with fixed positioning so it never gets clipped
// by a parent card's overflow:hidden or covered by a sibling's stacking context.
const pos  = ref({ top: 0, left: 0, width: 0, maxH: 300 })

const items = COUNTRIES.map(code => ({ code, name: countryName(code) }))
  .sort((a, b) => a.name.localeCompare(b.name))

const filtered = computed(() => {
  const term = q.value.trim().toLowerCase()
  if (!term) return items
  return items.filter(i => i.name.toLowerCase().includes(term) || i.code.toLowerCase() === term)
})

function place() {
  const r = btn.value?.getBoundingClientRect()
  if (!r) return
  const want  = 320
  const below = window.innerHeight - r.bottom - 8
  const above = r.top - 8
  if (below < 220 && above > below) {
    pos.value = { top: Math.max(8, r.top - Math.min(want, above) - 4), left: r.left, width: r.width, maxH: Math.min(want, above) }
  } else {
    pos.value = { top: r.bottom + 4, left: r.left, width: r.width, maxH: Math.max(180, Math.min(want, below)) }
  }
}
async function toggle() {
  open.value = !open.value
  if (open.value) {
    q.value = ''
    place()
    await nextTick()
    window.addEventListener('scroll', place, true)
    window.addEventListener('resize', place)
  } else { detach() }
}
function detach() {
  window.removeEventListener('scroll', place, true)
  window.removeEventListener('resize', place)
}
function close() { open.value = false; detach() }
function pick(code) { emit('update:modelValue', code); q.value = ''; close() }
onBeforeUnmount(detach)
</script>

<template>
  <div>
    <button ref="btn" type="button" @click="toggle"
      class="input w-full flex items-center justify-between gap-2 text-left">
      <span class="truncate">
        {{ modelValue ? `${flagEmoji(modelValue)} ${countryName(modelValue)}` : 'Select a country…' }}
      </span>
      <span class="text-slate-400 shrink-0">▾</span>
    </button>

    <Teleport to="body">
      <div v-if="open" class="fixed inset-0 z-[998]" @click="close" />
      <div v-if="open"
        class="fixed z-[999] bg-white rounded-xl shadow-xl border border-slate-200 overflow-hidden flex flex-col"
        :style="{ top: pos.top + 'px', left: pos.left + 'px', width: pos.width + 'px', maxHeight: pos.maxH + 'px' }"
        @click.stop>
        <input v-model="q" placeholder="Search country…" autofocus
          class="w-full px-3 py-2.5 text-sm border-b border-slate-100 outline-none shrink-0" />
        <div class="overflow-y-auto">
          <button v-for="c in filtered" :key="c.code" type="button" @click="pick(c.code)"
            class="w-full text-left px-3 py-2 text-sm hover:bg-cyan-50 transition flex items-center gap-2"
            :class="c.code === modelValue ? 'bg-cyan-50 font-semibold text-cyan-700' : 'text-slate-700'">
            {{ flagEmoji(c.code) }} {{ c.name }}
          </button>
          <p v-if="!filtered.length" class="px-3 py-3 text-xs text-slate-400 text-center">No country matches "{{ q }}"</p>
        </div>
      </div>
    </Teleport>
  </div>
</template>
