<script setup>
import { computed } from 'vue'
import { fmtDMY } from '../utils/formatters'

// Date picker that DISPLAYS dd-MM-yyyy regardless of browser locale, while
// keeping the model as a plain YYYY-MM-DD string (what every RPC expects).
// A native <input type="date"> is overlaid transparently so tapping still
// opens the OS date picker; only its rendered text (locale-formatted) is
// hidden — we draw our own dd-MM-yyyy label underneath.
const props = defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: 'dd-MM-yyyy' },
})
const emit = defineEmits(['update:modelValue'])

const display = computed(() => fmtDMY(props.modelValue))

function onInput(e) { emit('update:modelValue', e.target.value) }
</script>

<template>
  <div class="relative">
    <div class="input flex items-center justify-between gap-2">
      <span :class="display ? 'text-slate-800' : 'text-slate-400'">{{ display || placeholder }}</span>
      <span aria-hidden="true" class="text-slate-400 shrink-0">📅</span>
    </div>
    <input
      type="date"
      :value="modelValue"
      @input="onInput"
      class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
      aria-label="Select date" />
  </div>
</template>
