<script setup>
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'

const router = useRouter()
const { user } = useAuth()
</script>

<template>
  <div class="max-w-2xl mx-auto px-4 pb-6" :class="user ? 'pb-28 pt-[calc(env(safe-area-inset-top,0px)+3.25rem)]' : 'pt-6'">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-cyan-700 transition mb-6" @click="router.back()">‹ Back</button>

    <h1 class="font-display text-2xl font-extrabold gradient-text mb-1">Privacy Policy</h1>
    <p class="text-xs text-slate-400 mb-8">Last updated June 2026 · Badminton 360</p>

    <div class="space-y-6 text-sm text-slate-600 leading-relaxed">

      <section>
        <h2 class="font-display text-base font-bold text-slate-800 mb-2">What we collect</h2>
        <ul class="list-disc pl-5 space-y-1">
          <li>Your name, email and profile photo from Google when you sign in</li>
          <li>Anything you add yourself — nickname, phone, bio, gender</li>
          <li>Match results, Elo history and attendance for clubs you play in</li>
          <li>Split Pay / Wallet records among your club's members</li>
          <li>Basic device info (browser, rough location via IP) and in-app activity, used for security and to keep the leaderboard accurate</li>
          <li>If you enable biometric app-lock: a device credential reference only — your fingerprint or face data never leaves your device and is never sent to us</li>
        </ul>
      </section>

      <section>
        <h2 class="font-display text-base font-bold text-slate-800 mb-2">What's public vs. private</h2>
        <p>
          Your <strong>nickname</strong>, <strong>bio</strong> and match stats are visible to anyone using the app —
          that's how leaderboards and club/player profiles work. Your <strong>phone number, email,
          and gender</strong> are never shown to other players.
        </p>
      </section>

      <section>
        <h2 class="font-display text-base font-bold text-slate-800 mb-2">Who else processes your data</h2>
        <p class="mb-2">We don't sell your data. We use a small set of services to run the app:</p>
        <ul class="list-disc pl-5 space-y-1">
          <li><strong>Supabase</strong> — hosts our database and handles authentication</li>
          <li><strong>Google</strong> — sign-in (we never see your Google password)</li>
          <li><strong>Resend</strong> — delivers transactional emails like club invites</li>
          <li><strong>ipapi.co</strong> — a one-time, anonymous lookup to guess your country for the homepage</li>
        </ul>
      </section>

      <section>
        <h2 class="font-display text-base font-bold text-slate-800 mb-2">Your rights</h2>
        <p>
          You can edit or remove most of your info any time from
          <RouterLink to="/profile" class="text-cyan-700 hover:underline">your Profile</RouterLink>.
          You can permanently delete your account and personal data from
          <RouterLink to="/profile" class="text-cyan-700 hover:underline">Profile → Danger Zone</RouterLink> —
          match history is anonymised rather than deleted outright so your club's rankings stay accurate,
          and deletion is blocked while you're a club owner or have an unsettled Split Pay balance, so you can
          resolve those first.
        </p>
      </section>

      <section>
        <h2 class="font-display text-base font-bold text-slate-800 mb-2">Questions</h2>
        <p>
          Email <a href="mailto:hello@badminton360.app" class="text-cyan-700 hover:underline">hello@badminton360.app</a>
          for anything about your data or this policy.
        </p>
      </section>

    </div>
  </div>
</template>
