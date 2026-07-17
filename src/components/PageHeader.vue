<script setup>
defineProps({
  icon: String,
  title: String,
  subtitle: String,
  help: String          // optional collapsible help text
})
import { ref } from 'vue'
const showHelp = ref(false)
</script>

<template>
  <div class="mb-4">
    <div class="flex items-start justify-between gap-2">
      <div class="flex items-center gap-3">
        <div class="icon-tile icon-tile-cyan w-11 h-11 text-xl">{{ icon }}</div>
        <div>
          <h2 class="font-display text-xl font-bold tracking-tight leading-tight">{{ title }}</h2>
          <p class="text-xs text-slate-400">{{ subtitle }}</p>
        </div>
      </div>
      <button v-if="help" @click="showHelp = !showHelp"
        class="shrink-0 rounded-xl border border-slate-200 px-2.5 py-1 text-xs text-slate-500 hover:text-teal-600 hover:border-teal-400 transition">
        {{ showHelp ? 'Hide help' : '? Help' }}
      </button>
    </div>

    <div v-if="help && showHelp"
      class="mt-3 rounded-2xl border border-teal-200 bg-teal-50 p-4 text-sm text-slate-600 leading-relaxed">
      <slot name="help">{{ help }}</slot>
    </div>
  </div>
</template>
