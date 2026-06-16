<script setup>
import { useRouter } from 'vue-router'
import { useTheme, DARK_THEME_READY } from '../../composables/useTheme'

const router = useRouter()
const { theme, setTheme } = useTheme()

const OPTIONS = [
  { value: 'light',  icon: '☀️', label: 'Light',  hint: "Today's look — bright cards on a soft blue-white background." },
  { value: 'dark',   icon: '🌙', label: 'Dark',   hint: 'Coming soon — your pick is saved and switches over automatically once it ships.' },
  { value: 'system', icon: '⚙️', label: 'System', hint: 'Match your device setting (uses Light until Dark is ready).' },
]
</script>

<template>
  <div class="max-w-sm mx-auto pt-2 fade-up">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-6" @click="router.back()">‹ Back</button>

    <h1 class="font-display text-xl font-extrabold gradient-text mb-1">🎨 Appearance</h1>
    <p class="text-sm text-slate-400 mb-5">Choose how Badminton 360 looks on this device.</p>

    <div class="space-y-3">
      <button
        v-for="opt in OPTIONS" :key="opt.value"
        @click="setTheme(opt.value)"
        class="w-full text-left p-4 rounded-2xl border-2 transition flex items-start gap-3"
        :class="theme === opt.value ? '' : 'hover:border-cyan-300'"
        :style="theme === opt.value ? 'border-color:rgba(0,168,204,.5); background:rgba(0,229,255,.05);' : 'border-color:rgba(15,23,42,.1); background:#fff;'"
      >
        <span class="text-2xl shrink-0">{{ opt.icon }}</span>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <span class="font-bold text-slate-800 text-sm">{{ opt.label }}</span>
            <span v-if="opt.value === 'dark' && !DARK_THEME_READY" class="badge-pending">Soon</span>
          </div>
          <div class="text-xs text-slate-500 mt-0.5 leading-relaxed">{{ opt.hint }}</div>
        </div>
        <span v-if="theme === opt.value" class="text-cyan-600 text-lg shrink-0">✓</span>
      </button>
    </div>
  </div>
</template>
