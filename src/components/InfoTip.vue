<script setup>
import { ref } from 'vue'
defineProps({ text: String })
const show = ref(false)
</script>

<template>
  <span class="relative inline-block">
    <button @click="show = !show"
      class="ml-1 inline-flex h-4 w-4 items-center justify-center rounded-full border border-slate-300 text-[10px] text-slate-400 hover:border-teal-400 hover:text-teal-500 transition align-middle">
      ?
    </button>
    <span v-if="show"
      class="absolute right-0 top-6 z-50 w-64 rounded-xl border border-slate-200 bg-white p-3 text-xs text-slate-600 shadow-xl leading-relaxed"
      style="max-width:min(16rem, calc(100vw - 2rem))"
      @click.stop>
      {{ text }}
      <button @click="show = false" class="mt-2 block text-teal-600 font-semibold text-[10px]">Got it ✕</button>
    </span>
  </span>
</template>
