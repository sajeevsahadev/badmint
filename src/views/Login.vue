<script setup>
import { useAuth } from '../composables/useAuth'
const { signInWithGoogle } = useAuth()
</script>

<template>
  <div class="grid min-h-screen place-items-center px-6">
    <div class="w-full max-w-sm">
      <!-- Hero -->
      <div class="text-center mb-8">
        <div class="text-6xl mb-4">🏸</div>
        <h1 class="font-display text-4xl font-bold tracking-tight">Badmint</h1>
        <p class="mt-2 text-slate-400">Smart ranking for your badminton team.</p>
      </div>

      <!-- Feature pills -->
      <div class="grid grid-cols-2 gap-2 mb-8">
        <div class="card p-3 text-center">
          <div class="text-xl mb-1">📊</div>
          <div class="text-xs font-medium">Elo Skill Rating</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Beat strong pairs, earn more</div>
        </div>
        <div class="card p-3 text-center">
          <div class="text-xl mb-1">📅</div>
          <div class="text-xs font-medium">Attendance Score</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Regulars get rewarded</div>
        </div>
        <div class="card p-3 text-center">
          <div class="text-xl mb-1">⚔️</div>
          <div class="text-xs font-medium">Head-to-Head</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Track your rivalries</div>
        </div>
        <div class="card p-3 text-center">
          <div class="text-xl mb-1">🏢</div>
          <div class="text-xs font-medium">Multi-Team</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Add unlimited clubs</div>
        </div>
      </div>

      <button class="btn-primary w-full flex items-center justify-center gap-2 py-3"
        @click="signInWithGoogle">
        <svg width="18" height="18" viewBox="0 0 24 24">
          <path fill="currentColor" d="M21.35 11.1h-9.18v2.92h5.27c-.23 1.4-1.64 4.1-5.27 4.1-3.17 0-5.76-2.62-5.76-5.86s2.59-5.86 5.76-5.86c1.81 0 3.02.77 3.71 1.43l2.53-2.44C16.9 3.6 14.76 2.7 12.17 2.7 6.98 2.7 2.8 6.88 2.8 12.07s4.18 9.37 9.37 9.37c5.41 0 9-3.8 9-9.16 0-.62-.07-1.08-.16-1.55z"/>
        </svg>
        Continue with Google
      </button>

      <p class="mt-4 text-center text-xs text-slate-500">
        Free forever · Works offline · UAE-made 🇦🇪
      </p>
    </div>
  </div>
</template>
