<script setup>
import { useAuth } from '../composables/useAuth'
const { signInWithGoogle } = useAuth()
</script>

<template>
  <div class="relative grid min-h-screen place-items-center px-6 overflow-hidden">

    <!-- Animated background orbs -->
    <div class="pointer-events-none absolute inset-0 overflow-hidden">
      <div class="absolute -top-40 -right-40 w-[600px] h-[600px] rounded-full opacity-20"
        style="background: radial-gradient(circle, #00e5ff 0%, transparent 70%); animation: pulse-glow 4s ease-in-out infinite;" />
      <div class="absolute -bottom-40 -left-40 w-[500px] h-[500px] rounded-full opacity-15"
        style="background: radial-gradient(circle, #a855f7 0%, transparent 70%); animation: pulse-glow 4s ease-in-out infinite 2s;" />
      <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[300px] h-[300px] rounded-full opacity-10"
        style="background: radial-gradient(circle, #fbbf24 0%, transparent 70%);" />
    </div>

    <!-- Grid lines overlay -->
    <div class="pointer-events-none absolute inset-0 opacity-[0.03]"
      style="background-image: linear-gradient(rgba(0,229,255,.8) 1px, transparent 1px), linear-gradient(90deg, rgba(0,229,255,.8) 1px, transparent 1px); background-size: 60px 60px;" />

    <div class="relative w-full max-w-sm fade-up">

      <!-- Logo -->
      <div class="text-center mb-10">
        <div class="relative inline-block mb-5">
          <div class="text-7xl leading-none" style="filter: drop-shadow(0 0 30px rgba(0,229,255,.5));">🏸</div>
        </div>
        <h1 class="font-display text-5xl font-extrabold tracking-tight gradient-text mb-1">Badmint</h1>
        <p class="text-slate-400 text-sm tracking-wide">Smart rankings for your badminton team</p>
      </div>

      <!-- Feature grid -->
      <div class="grid grid-cols-2 gap-2.5 mb-8">
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-white/20">
          <div class="text-2xl mb-2">📊</div>
          <div class="text-xs font-semibold text-slate-200">Elo Skill Rating</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Beat stronger pairs, earn more</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-white/20">
          <div class="text-2xl mb-2">📅</div>
          <div class="text-xs font-semibold text-slate-200">Attendance Score</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Regulars get rewarded</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-white/20">
          <div class="text-2xl mb-2">⚔️</div>
          <div class="text-xs font-semibold text-slate-200">Head-to-Head</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Track your rivalries</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-white/20">
          <div class="text-2xl mb-2">🏢</div>
          <div class="text-xs font-semibold text-slate-200">Multi-Club</div>
          <div class="text-[10px] text-slate-500 mt-0.5">Join unlimited teams</div>
        </div>
      </div>

      <!-- CTA -->
      <button class="btn-primary w-full py-3.5 text-base gap-3 pulse-glow mb-4"
        @click="signInWithGoogle">
        <svg width="20" height="20" viewBox="0 0 24 24">
          <path fill="currentColor" d="M21.35 11.1h-9.18v2.92h5.27c-.23 1.4-1.64 4.1-5.27 4.1-3.17 0-5.76-2.62-5.76-5.86s2.59-5.86 5.76-5.86c1.81 0 3.02.77 3.71 1.43l2.53-2.44C16.9 3.6 14.76 2.7 12.17 2.7 6.98 2.7 2.8 6.88 2.8 12.07s4.18 9.37 9.37 9.37c5.41 0 9-3.8 9-9.16 0-.62-.07-1.08-.16-1.55z"/>
        </svg>
        Continue with Google
      </button>

      <p class="text-center text-xs text-slate-500 leading-relaxed">
        Free forever · Works offline · 🇦🇪 Built for UAE courts
      </p>
    </div>
  </div>
</template>
