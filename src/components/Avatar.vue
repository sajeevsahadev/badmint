<script setup>
import { ref, computed } from 'vue'
const props = defineProps({
  name: { type: String, default: '' },
  src:  { type: String, default: '' },
  size: { type: Number, default: 40 }
})
const broken = ref(false)
const initials = computed(() => {
  const parts = (props.name || '?').trim().split(/\s+/).map(w => w[0]).filter(Boolean)
  return (parts.slice(0, 2).join('') || '?').toUpperCase()
})
const showImg = computed(() => !!props.src && !broken.value)
</script>
<template>
  <span class="inline-flex items-center justify-center rounded-full overflow-hidden shrink-0 select-none align-middle"
        :style="{ width: size + 'px', height: size + 'px' }">
    <img v-if="showImg" :src="src" :alt="name" class="w-full h-full object-cover" @error="broken = true" />
    <span v-else class="w-full h-full flex items-center justify-center font-bold text-white leading-none"
          :style="{ fontSize: (size * 0.4) + 'px', background: 'linear-gradient(135deg,#00b4d8,#a855f7)' }">{{ initials }}</span>
  </span>
</template>
