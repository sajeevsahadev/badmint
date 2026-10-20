<script setup>
import { ref, computed } from 'vue'
import { COUNTRIES, countryName } from '../utils/countries'
import { useGeo } from '../composables/useGeo'

const props = defineProps({ modelValue: { type: String, default: '' } })
const emit  = defineEmits(['update:modelValue'])
const { flagEmoji } = useGeo()

const open = ref(false)
const q    = ref('')

const items = COUNTRIES.map(code => ({ code, name: countryName(code) }))
  .sort((a, b) => a.name.localeCompare(b.name))

const filtered = computed(() => {
  const term = q.value.trim().toLowerCase()
  if (!term) return items
  return items.filter(i => i.name.toLowerCase().includes(term) || i.code.toLowerCase() === term)
})

function toggle() { open.value = !open.value; if (open.value) q.value = '' }
function pick(code) { emit('update:modelValue', code); open.value = false; q.value = '' }
</script>

<template>
  <div class="relative">
    <button type="button" @click="toggle"
      class="input w-full flex items-center justify-between gap-2 text-left">
      <span class="truncate">
        {{ modelValue ? `${flagEmoji(modelValue)} ${countryName(modelValue)}` : 'Select a country…' }}
      </span>
      <span class="text-slate-400 shrink-0">▾</span>
    </button>

    <!-- backdrop closes on outside click -->
    <div v-if="open" class="fixed inset-0 z-20" @click="open = false" />

    <div v-if="open"
      class="absolute z-30 mt-1 w-full bg-white rounded-xl shadow-xl border border-slate-200 overflow-hidden">
      <input v-model="q" placeholder="Search country…" autofocus @click.stop
        class="w-full px-3 py-2.5 text-sm border-b border-slate-100 outline-none" />
      <div class="max-h-64 overflow-y-auto">
        <button v-for="c in filtered" :key="c.code" type="button" @click="pick(c.code)"
          class="w-full text-left px-3 py-2 text-sm hover:bg-cyan-50 transition flex items-center gap-2"
          :class="c.code === modelValue ? 'bg-cyan-50 font-semibold text-cyan-700' : 'text-slate-700'">
          {{ flagEmoji(c.code) }} {{ c.name }}
        </button>
        <p v-if="!filtered.length" class="px-3 py-3 text-xs text-slate-400 text-center">No country matches "{{ q }}"</p>
      </div>
    </div>
  </div>
</template>
