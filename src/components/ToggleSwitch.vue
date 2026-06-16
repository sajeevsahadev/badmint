<script setup>
defineProps({ modelValue: Boolean, disabled: Boolean })
defineEmits(['update:modelValue'])
</script>

<template>
  <button
    type="button"
    role="switch"
    :aria-checked="modelValue"
    :disabled="disabled"
    @click="$emit('update:modelValue', !modelValue)"
    class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors duration-200 disabled:opacity-40 disabled:cursor-not-allowed"
    :style="modelValue ? 'background:linear-gradient(135deg,#00b4d8,#0077a8)' : 'background:rgba(15,23,42,.15)'"
  >
    <span
      class="inline-block h-[18px] w-[18px] rounded-full bg-white shadow transition-transform duration-200"
      :class="modelValue ? 'translate-x-[22px]' : 'translate-x-[3px]'"
    />
  </button>
</template>
