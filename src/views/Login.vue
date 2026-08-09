<script setup>
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { useInstall } from '../composables/useInstall'

const { signInWithGoogle, signInWithApple } = useAuth()
const { canInstall, isIOS, promptInstall } = useInstall()
const router = useRouter()
</script>

<template>
  <div class="relative grid min-h-screen place-items-center px-5 overflow-hidden">

    <!-- Animated background orbs -->
    <div class="pointer-events-none absolute inset-0 overflow-hidden">
      <div class="absolute -top-40 -right-40 w-[600px] h-[600px] rounded-full opacity-20"
        style="background:radial-gradient(circle,#00e5ff 0%,transparent 70%); animation:pulse-glow 4s ease-in-out infinite;" />
      <div class="absolute -bottom-40 -left-40 w-[500px] h-[500px] rounded-full opacity-15"
        style="background:radial-gradient(circle,#a855f7 0%,transparent 70%); animation:pulse-glow 4s ease-in-out infinite 2s;" />
    </div>
    <!-- Grid lines -->
    <div class="pointer-events-none absolute inset-0 opacity-[0.025]"
      style="background-image:linear-gradient(rgba(0,229,255,.8) 1px,transparent 1px),linear-gradient(90deg,rgba(0,229,255,.8) 1px,transparent 1px); background-size:60px 60px;" />

    <div class="relative w-full max-w-sm fade-up">

      <!-- Logo -->
      <div class="text-center mb-8">
        <div class="text-7xl mb-4 leading-none" style="filter:drop-shadow(0 0 28px rgba(0,229,255,.5));">🏸</div>
        <h1 class="font-display text-5xl font-extrabold tracking-tight gradient-text mb-1">Badminton 360</h1>
        <p class="text-slate-400 text-sm">Your club · Your game · One app</p>
      </div>

      <!-- Feature grid -->
      <div class="grid grid-cols-2 gap-2 mb-6">
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-[rgba(15,23,42,0.20)]">
          <div class="text-2xl mb-1.5">📊</div>
          <div class="text-xs font-semibold text-slate-200">Elo Rankings</div>
          <div class="text-xs text-slate-500 mt-0.5">Beat strong pairs, earn more</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-[rgba(15,23,42,0.20)]">
          <div class="text-2xl mb-1.5">💸</div>
          <div class="text-xs font-semibold text-slate-200">Split Payments</div>
          <div class="text-xs text-slate-500 mt-0.5">Court fees, split equally</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-[rgba(15,23,42,0.20)]">
          <div class="text-2xl mb-1.5">🌍</div>
          <div class="text-xs font-semibold text-slate-200">Clubs Worldwide</div>
          <div class="text-xs text-slate-500 mt-0.5">Any court, any country</div>
        </div>
        <div class="card p-3.5 text-center transition-all duration-300 hover:border-[rgba(15,23,42,0.20)]">
          <div class="text-2xl mb-1.5">📋</div>
          <div class="text-xs font-semibold text-slate-200">Match History</div>
          <div class="text-xs text-slate-500 mt-0.5">Every game recorded</div>
        </div>
      </div>

      <!-- Explore without login -->
      <button class="btn-ghost w-full mb-3 text-sm" @click="$router.push('/explore')">
        🌍 Browse Clubs
      </button>

      <!-- Google sign-in -->
      <button class="btn-primary w-full py-3.5 text-base gap-3 pulse-glow mb-4"
        @click="signInWithGoogle">
        <svg width="20" height="20" viewBox="0 0 24 24">
          <path fill="currentColor" d="M21.35 11.1h-9.18v2.92h5.27c-.23 1.4-1.64 4.1-5.27 4.1-3.17 0-5.76-2.62-5.76-5.86s2.59-5.86 5.76-5.86c1.81 0 3.02.77 3.71 1.43l2.53-2.44C16.9 3.6 14.76 2.7 12.17 2.7 6.98 2.7 2.8 6.88 2.8 12.07s4.18 9.37 9.37 9.37c5.41 0 9-3.8 9-9.16 0-.62-.07-1.08-.16-1.55z"/>
        </svg>
        Continue with Google — Free
      </button>

      <!-- Sign in with Apple (required on iOS; works once enabled in Supabase) -->
      <button class="w-full py-3.5 mb-4 rounded-2xl bg-black text-white font-semibold text-base flex items-center justify-center gap-2.5 active:scale-[.99] transition"
        @click="signInWithApple">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path d="M17.05 12.04c-.03-2.6 2.12-3.85 2.22-3.9-1.21-1.77-3.1-2.02-3.77-2.05-1.6-.16-3.13.94-3.94.94-.81 0-2.07-.92-3.4-.9-1.75.03-3.37 1.02-4.27 2.59-1.82 3.16-.47 7.84 1.31 10.41.87 1.26 1.9 2.67 3.26 2.62 1.31-.05 1.8-.85 3.39-.85 1.58 0 2.03.85 3.41.82 1.41-.03 2.3-1.28 3.16-2.55.99-1.46 1.4-2.87 1.42-2.94-.03-.01-2.73-1.05-2.76-4.15zM14.6 4.6c.72-.88 1.21-2.1 1.08-3.31-1.04.04-2.3.69-3.05 1.56-.67.77-1.25 2.01-1.09 3.19 1.16.09 2.34-.59 3.06-1.44z"/>
        </svg>
        Sign in with Apple
      </button>

      <!-- PWA install buttons -->
      <div v-if="canInstall || isIOS" class="grid gap-2 mb-4">
        <button v-if="canInstall"
          class="btn-ghost w-full text-sm gap-2" @click="promptInstall">
          <span>🤖</span> Add to Android / Chrome
        </button>
        <div v-if="isIOS" class="card px-4 py-3 text-xs text-slate-400 leading-relaxed">
          <span class="font-bold text-slate-300">🍎 Add to iPhone:</span>
          Tap <strong class="text-slate-300">Share ↑</strong> in Safari →
          <strong class="text-slate-300">"Add to Home Screen"</strong>
        </div>
      </div>

      <p class="text-center text-xs text-slate-600">
        🌍 Built for badminton clubs everywhere
      </p>
    </div>
  </div>
</template>
