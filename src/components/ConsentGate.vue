<script setup>
// Reusable AI-analysis consent gate. v-model is the boolean "agreed" state. Used by both the
// recorder and the uploader so the legal wording lives in exactly one place (src/lib/consent.js).
import { ref } from 'vue'
import { CONSENT_SUMMARY, CONSENT_POINTS } from '../lib/consent'

defineProps({ modelValue: { type: Boolean, default: false }, compact: { type: Boolean, default: false } })
const emit = defineEmits(['update:modelValue'])
const showFull = ref(false)
</script>

<template>
  <div class="card card-amber p-4" :class="compact ? 'mb-3' : 'mb-4'">
    <label class="flex items-start gap-3 cursor-pointer">
      <input type="checkbox" :checked="modelValue" @change="emit('update:modelValue', $event.target.checked)"
        class="mt-0.5 h-5 w-5 shrink-0 accent-cyan-600" />
      <span class="text-sm text-slate-700">
        <b>I have everyone's consent.</b> {{ CONSENT_SUMMARY }}
      </span>
    </label>
    <button type="button" @click="showFull = !showFull"
      class="mt-2 text-xs font-semibold text-neon">
      {{ showFull ? 'Hide full terms' : 'Read the full consent terms' }}
    </button>
    <ul v-if="showFull" class="mt-2 space-y-1.5 border-t border-amber-200/60 pt-2 text-xs text-slate-600">
      <li v-for="(p, i) in CONSENT_POINTS" :key="i" class="flex gap-2">
        <span class="text-amber-500">•</span><span>{{ p }}</span>
      </li>
    </ul>
  </div>
</template>
