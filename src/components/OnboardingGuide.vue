<script setup>
import { ref } from 'vue'

const emit = defineEmits(['done'])

const step = ref(0)

const slides = [
  {
    emoji: '🏸',
    title: 'Welcome to Badminton 360',
    story: "Meet Dev's Saturday Crew — 14 friends who book a court every weekend. They've been settling scores by memory, splitting costs on WhatsApp, and arguing about who's actually the best player.",
    tip: 'This guide walks you through the whole app in 2 minutes.',
    color: 'cyan',
  },
  {
    emoji: '🏟️',
    title: 'Create Your Club',
    story: 'Dev opens the app and taps Manage → Create Club. He types "Dev\'s Saturday Crew", hits Create — done. His club is live in under 10 seconds.',
    tip: '→ Tap ⚙️ Manage in the bottom nav, then Create Club.',
    color: 'violet',
  },
  {
    emoji: '📲',
    title: 'Invite Your Crew',
    story: "Dev goes to Manage → Invite Members and copies the invite link. He drops it in the WhatsApp group. Everyone taps the link, signs in with Google, and they're on the roster instantly.",
    tip: '→ Manage → Invite Members → share the link on WhatsApp.',
    color: 'cyan',
  },
  {
    emoji: '🎯',
    title: 'Record a Match',
    story: "First game done — Dev opens Add Match, picks the 4 players, assigns them to Side A and Side B, types in the score, and hits Record. The Elo engine updates everyone's rating in one tap.",
    tip: '→ Tap ➕ Add Match in the bottom nav (or hamburger menu).',
    color: 'amber',
  },
  {
    emoji: '🏆',
    title: 'The Leaderboard',
    story: "After three games, the leaderboard is already alive. Dev's crew finally has proof — ranked by Elo rating, updated after every match. No more arguments about who's the best.",
    tip: '→ Tap 🏠 Home in the bottom nav to see live rankings.',
    color: 'violet',
  },
  {
    emoji: '⚖️',
    title: 'Split Costs with PaySplits',
    story: "The court cost AED 180 for 12 players. Dev opens PaySplits → Activities, adds the expense, selects everyone who played — the app divides it equally and shows exactly who owes who.",
    tip: '→ Tap 💰 PaySplits → Activities → Add Expense.',
    color: 'cyan',
  },
  {
    emoji: '💰',
    title: 'The Wallet — No More "I\'ll Pay Later"',
    story: "Dev gets everyone to top up AED 50 into the club Wallet upfront. From now on, court fees just deduct from the pool automatically. No awkward chasing. No WhatsApp payment requests.",
    tip: '→ PaySplits → Wallet tab → Add Contribution.',
    color: 'amber',
  },
  {
    emoji: '🎉',
    title: "Dev's crew is ready!",
    story: "Matches tracked. Rankings live. Costs split fairly. Wallet pre-funded. Dev's Saturday Crew runs like a proper league now — and it took less than 5 minutes to set up.",
    tip: 'The whole game. The whole club. One app. 360°.',
    color: 'violet',
  },
]

const total = slides.length

function next() {
  if (step.value < total - 1) step.value++
  else finish()
}
function prev() { if (step.value > 0) step.value-- }
function finish() { emit('done') }

const colorMap = {
  cyan:   { badge: '#00e5ff', glow: 'rgba(0,229,255,0.15)', text: '#0077a8' },
  violet: { badge: '#a855f7', glow: 'rgba(168,85,247,0.15)', text: '#7c3aed' },
  amber:  { badge: '#fbbf24', glow: 'rgba(251,191,36,0.15)',  text: '#b45309' },
}
</script>

<template>
  <Teleport to="body">
    <Transition name="guide-fade">
      <div class="fixed inset-0 z-[200] flex items-end sm:items-center justify-center p-0 sm:p-4"
        style="background:rgba(5,13,26,0.85); backdrop-filter:blur(8px);">

        <div class="guide-panel w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden flex flex-col"
          style="background:#0d1f3a; border:1px solid rgba(0,229,255,0.12);
                 box-shadow:0 0 60px rgba(0,229,255,0.08), 0 24px 64px rgba(0,0,0,0.5);
                 max-height:92dvh;">

          <!-- Skip button -->
          <div class="flex justify-end px-5 pt-4 pb-0 shrink-0">
            <button @click="finish"
              class="text-xs text-slate-400 hover:text-slate-200 transition px-2 py-1 rounded-lg hover:bg-white/5">
              Skip guide ✕
            </button>
          </div>

          <!-- Slide content -->
          <div class="flex-1 overflow-y-auto px-6 pt-2 pb-4">

            <!-- Illustration area -->
            <div class="flex flex-col items-center text-center mb-6">

              <!-- Step illustration SVG -->
              <div class="relative mb-5">
                <!-- Glow orb behind emoji -->
                <div class="w-28 h-28 rounded-full flex items-center justify-center text-6xl relative"
                  :style="`background:${colorMap[slides[step].color].glow}; border:1px solid ${colorMap[slides[step].color].badge}22;`">
                  <span>{{ slides[step].emoji }}</span>
                  <!-- Pulse ring -->
                  <div class="absolute inset-0 rounded-full animate-ping opacity-20"
                    :style="`border:2px solid ${colorMap[slides[step].color].badge}`"></div>
                </div>

                <!-- Step counter badge -->
                <div class="absolute -bottom-1 -right-1 w-7 h-7 rounded-full flex items-center justify-center text-[11px] font-bold"
                  :style="`background:${colorMap[slides[step].color].badge}; color:#050d1a;`">
                  {{ step + 1 }}
                </div>
              </div>

              <!-- Title -->
              <h2 class="font-display text-xl font-extrabold mb-3 leading-tight"
                :style="`color:${colorMap[slides[step].color].badge}`">
                {{ slides[step].title }}
              </h2>

              <!-- Story -->
              <p class="text-slate-300 text-sm leading-relaxed mb-4">
                {{ slides[step].story }}
              </p>

              <!-- Tip chip -->
              <div class="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-medium text-left w-full"
                :style="`background:${colorMap[slides[step].color].glow}; border:1px solid ${colorMap[slides[step].color].badge}33; color:${colorMap[slides[step].color].badge};`">
                <span class="shrink-0">💡</span>
                <span>{{ slides[step].tip }}</span>
              </div>
            </div>

            <!-- Illustrated mini-diagram per slide -->
            <div class="rounded-2xl overflow-hidden mb-2"
              style="background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.06);">
              <component :is="'svg'" viewBox="0 0 360 140" xmlns="http://www.w3.org/2000/svg"
                class="w-full" style="display:block;">

                <!-- Slide 0: Welcome — players on a court -->
                <template v-if="step === 0">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Court lines -->
                  <rect x="40" y="30" width="280" height="80" rx="4" fill="none" stroke="#00e5ff22" stroke-width="1.5"/>
                  <line x1="200" y1="30" x2="200" y2="110" stroke="#00e5ff22" stroke-width="1.5"/>
                  <line x1="40" y1="70" x2="320" y2="70" stroke="#a855f722" stroke-width="1"/>
                  <!-- Net -->
                  <rect x="196" y="28" width="8" height="84" rx="2" fill="#00e5ff33"/>
                  <!-- Player dots - Side A -->
                  <circle cx="100" cy="52" r="10" fill="#00e5ff" opacity=".9"/>
                  <text x="100" y="56" text-anchor="middle" font-size="10" fill="#050d1a" font-weight="bold">D</text>
                  <circle cx="140" cy="88" r="10" fill="#00e5ff" opacity=".7"/>
                  <text x="140" y="92" text-anchor="middle" font-size="10" fill="#050d1a" font-weight="bold">A</text>
                  <!-- Player dots - Side B -->
                  <circle cx="260" cy="52" r="10" fill="#a855f7" opacity=".9"/>
                  <text x="260" y="56" text-anchor="middle" font-size="10" fill="#fff">R</text>
                  <circle cx="220" cy="88" r="10" fill="#a855f7" opacity=".7"/>
                  <text x="220" y="92" text-anchor="middle" font-size="10" fill="#fff">K</text>
                  <!-- Shuttlecock -->
                  <ellipse cx="200" cy="55" rx="5" ry="7" fill="#fbbf24" opacity=".9"/>
                  <!-- Score -->
                  <text x="100" y="128" text-anchor="middle" font-size="11" fill="#00e5ff" font-weight="bold">21</text>
                  <text x="180" y="128" text-anchor="middle" font-size="11" fill="#ffffff44">vs</text>
                  <text x="260" y="128" text-anchor="middle" font-size="11" fill="#a855f7" font-weight="bold">18</text>
                </template>

                <!-- Slide 1: Create Club -->
                <template v-else-if="step === 1">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Phone outline -->
                  <rect x="120" y="15" width="120" height="110" rx="14" fill="none" stroke="#00e5ff33" stroke-width="1.5"/>
                  <rect x="128" y="26" width="104" height="88" rx="8" fill="#0d1f3a"/>
                  <!-- Club name input -->
                  <rect x="136" y="36" width="88" height="18" rx="5" fill="none" stroke="#00e5ff55" stroke-width="1"/>
                  <text x="142" y="48" font-size="8" fill="#00e5ff99">Dev's Saturday Crew</text>
                  <!-- Create button -->
                  <rect x="136" y="62" width="88" height="18" rx="5" fill="#00e5ff"/>
                  <text x="180" y="74" text-anchor="middle" font-size="8" fill="#050d1a" font-weight="bold">Create Club</text>
                  <!-- Success tick -->
                  <circle cx="180" cy="105" r="12" fill="#00e5ff22" stroke="#00e5ff55" stroke-width="1"/>
                  <text x="180" y="110" text-anchor="middle" font-size="13">✓</text>
                  <!-- Glow -->
                  <circle cx="180" cy="70" r="55" fill="#00e5ff" opacity=".03"/>
                </template>

                <!-- Slide 2: Invite -->
                <template v-else-if="step === 2">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Central phone -->
                  <rect x="148" y="20" width="64" height="100" rx="10" fill="none" stroke="#a855f733" stroke-width="1.5"/>
                  <rect x="154" y="28" width="52" height="84" rx="6" fill="#0d1f3a"/>
                  <!-- WhatsApp icon area -->
                  <circle cx="180" cy="55" r="14" fill="#25d36622"/>
                  <text x="180" y="60" text-anchor="middle" font-size="14">💬</text>
                  <!-- Link text -->
                  <rect x="157" y="77" width="46" height="8" rx="3" fill="#a855f722"/>
                  <text x="180" y="83" text-anchor="middle" font-size="6" fill="#a855f7">invite link</text>
                  <!-- Arrow lines going out to people -->
                  <line x1="148" y1="70" x2="80" y2="50" stroke="#a855f744" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="148" y1="80" x2="75" y2="100" stroke="#a855f744" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="212" y1="70" x2="280" y2="50" stroke="#a855f744" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="212" y1="80" x2="285" y2="100" stroke="#a855f744" stroke-width="1" stroke-dasharray="3,2"/>
                  <!-- Person dots -->
                  <circle cx="68" cy="48" r="10" fill="#a855f7" opacity=".7"/><text x="68" y="52" text-anchor="middle" font-size="9" fill="#fff">A</text>
                  <circle cx="63" cy="100" r="10" fill="#a855f7" opacity=".7"/><text x="63" y="104" text-anchor="middle" font-size="9" fill="#fff">B</text>
                  <circle cx="292" cy="48" r="10" fill="#00e5ff" opacity=".7"/><text x="292" y="52" text-anchor="middle" font-size="9" fill="#050d1a">C</text>
                  <circle cx="297" cy="100" r="10" fill="#00e5ff" opacity=".7"/><text x="297" y="104" text-anchor="middle" font-size="9" fill="#050d1a">D</text>
                </template>

                <!-- Slide 3: Record Match -->
                <template v-else-if="step === 3">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Two side cards -->
                  <rect x="30" y="25" width="130" height="90" rx="10" fill="#00e5ff11" stroke="#00e5ff33" stroke-width="1"/>
                  <text x="95" y="42" text-anchor="middle" font-size="9" fill="#00e5ff" font-weight="bold">SIDE A</text>
                  <circle cx="70" cy="65" r="10" fill="#00e5ff"/><text x="70" y="69" text-anchor="middle" font-size="9" fill="#050d1a">D</text>
                  <circle cx="120" cy="65" r="10" fill="#00e5ff" opacity=".7"/><text x="120" y="69" text-anchor="middle" font-size="9" fill="#050d1a">A</text>
                  <text x="95" y="100" text-anchor="middle" font-size="20" fill="#fbbf24" font-weight="bold">21</text>

                  <rect x="200" y="25" width="130" height="90" rx="10" fill="#a855f711" stroke="#a855f733" stroke-width="1"/>
                  <text x="265" y="42" text-anchor="middle" font-size="9" fill="#a855f7" font-weight="bold">SIDE B</text>
                  <circle cx="240" cy="65" r="10" fill="#a855f7"/><text x="240" y="69" text-anchor="middle" font-size="9" fill="#fff">R</text>
                  <circle cx="290" cy="65" r="10" fill="#a855f7" opacity=".7"/><text x="290" y="69" text-anchor="middle" font-size="9" fill="#fff">K</text>
                  <text x="265" y="100" text-anchor="middle" font-size="20" fill="#fbbf24" font-weight="bold">18</text>

                  <!-- VS / Record button -->
                  <text x="180" y="65" text-anchor="middle" font-size="11" fill="#ffffff44">vs</text>
                  <rect x="140" y="120" width="80" height="14" rx="7" fill="#fbbf24"/>
                  <text x="180" y="130" text-anchor="middle" font-size="8" fill="#050d1a" font-weight="bold">Record Match</text>
                </template>

                <!-- Slide 4: Leaderboard -->
                <template v-else-if="step === 4">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Podium -->
                  <rect x="140" y="55" width="80" height="60" rx="4" fill="#fbbf2422" stroke="#fbbf2444" stroke-width="1"/>
                  <rect x="70"  y="75" width="65" height="40" rx="4" fill="#94a3b822" stroke="#94a3b844" stroke-width="1"/>
                  <rect x="225" y="82" width="65" height="33" rx="4" fill="#f97316" opacity=".15" stroke="#f9731644" stroke-width="1"/>
                  <text x="180" y="46" text-anchor="middle" font-size="16">🥇</text>
                  <text x="102" y="68" text-anchor="middle" font-size="14">🥈</text>
                  <text x="257" y="74" text-anchor="middle" font-size="14">🥉</text>
                  <!-- Names -->
                  <text x="180" y="75" text-anchor="middle" font-size="8" fill="#fbbf24" font-weight="bold">Dev</text>
                  <text x="180" y="86" text-anchor="middle" font-size="7" fill="#fbbf2499">1187 Elo</text>
                  <text x="102" y="91" text-anchor="middle" font-size="8" fill="#94a3b8">Anil</text>
                  <text x="257" y="96" text-anchor="middle" font-size="8" fill="#f97316">Ravi</text>
                  <!-- Rank rows below -->
                  <rect x="40" y="122" width="280" height="10" rx="3" fill="#ffffff06"/>
                  <text x="50" y="130" font-size="7" fill="#ffffff44">#4  Sam  · 1050 Elo</text>
                  <text x="220" y="130" font-size="7" fill="#ffffff44">#5  Kiran</text>
                </template>

                <!-- Slide 5: PaySplits -->
                <template v-else-if="step === 5">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Expense card -->
                  <rect x="50" y="18" width="260" height="50" rx="10" fill="#00e5ff08" stroke="#00e5ff22" stroke-width="1"/>
                  <text x="68" y="36" font-size="8" fill="#ffffff88">Court Booking — Saturday</text>
                  <text x="68" y="51" font-size="16" fill="#00e5ff" font-weight="bold">AED 180</text>
                  <text x="288" y="44" text-anchor="end" font-size="8" fill="#ffffff55">÷ 12</text>
                  <!-- Arrow -->
                  <text x="180" y="84" text-anchor="middle" font-size="13" fill="#00e5ff66">↓</text>
                  <!-- Per-person rows -->
                  <rect x="50" y="88" width="260" height="44" rx="10" fill="#0d1f3a" stroke="#ffffff0a" stroke-width="1"/>
                  <text x="65" y="106" font-size="7" fill="#ffffff88">Dev</text>
                  <text x="295" y="106" text-anchor="end" font-size="7" fill="#f87171">owes AED 15</text>
                  <line x1="60" y1="112" x2="300" y2="112" stroke="#ffffff08" stroke-width="1"/>
                  <text x="65" y="124" font-size="7" fill="#ffffff88">Anil</text>
                  <text x="295" y="124" text-anchor="end" font-size="7" fill="#4ade80">gets AED 30</text>
                </template>

                <!-- Slide 6: Wallet -->
                <template v-else-if="step === 6">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- Pool bucket -->
                  <rect x="130" y="25" width="100" height="70" rx="12" fill="#fbbf2408" stroke="#fbbf2433" stroke-width="1.5"/>
                  <text x="180" y="54" text-anchor="middle" font-size="11" fill="#fbbf24" font-weight="bold">Club Pool</text>
                  <text x="180" y="70" text-anchor="middle" font-size="18" fill="#fbbf24" font-weight="bold">AED 700</text>
                  <text x="180" y="82" text-anchor="middle" font-size="7" fill="#fbbf2488">14 × AED 50</text>
                  <!-- Coins raining in -->
                  <circle cx="95" cy="40" r="8" fill="#fbbf2422" stroke="#fbbf2444" stroke-width="1"/>
                  <text x="95" y="44" text-anchor="middle" font-size="8">💰</text>
                  <circle cx="265" cy="40" r="8" fill="#fbbf2422" stroke="#fbbf2444" stroke-width="1"/>
                  <text x="265" y="44" text-anchor="middle" font-size="8">💰</text>
                  <line x1="100" y1="46" x2="128" y2="56" stroke="#fbbf2444" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="260" y1="46" x2="232" y2="56" stroke="#fbbf2444" stroke-width="1" stroke-dasharray="3,2"/>
                  <!-- Court auto-deduct -->
                  <rect x="80" y="108" width="200" height="22" rx="8" fill="#fbbf2411" stroke="#fbbf2433" stroke-width="1"/>
                  <text x="180" y="122" text-anchor="middle" font-size="7.5" fill="#fbbf24">Court fee auto-deducted each week ✓</text>
                </template>

                <!-- Slide 7: Ready! -->
                <template v-else-if="step === 7">
                  <rect width="360" height="140" fill="#0a1628"/>
                  <!-- 360 ring -->
                  <circle cx="180" cy="70" r="50" fill="none" stroke="url(#readyGrad)" stroke-width="2" opacity=".5"/>
                  <circle cx="180" cy="70" r="38" fill="none" stroke="#ffffff08" stroke-width="1"/>
                  <!-- Feature icons around ring -->
                  <text x="180" y="32" text-anchor="middle" font-size="12">🏆</text>
                  <text x="222" y="48" text-anchor="middle" font-size="12">📋</text>
                  <text x="230" y="92" text-anchor="middle" font-size="12">💰</text>
                  <text x="180" y="112" text-anchor="middle" font-size="12">📅</text>
                  <text x="130" y="92" text-anchor="middle" font-size="12">👥</text>
                  <text x="138" y="48" text-anchor="middle" font-size="12">🎯</text>
                  <!-- Center -->
                  <text x="180" y="63" text-anchor="middle" font-size="20">🏸</text>
                  <text x="180" y="80" text-anchor="middle" font-size="8" fill="#00e5ff" font-weight="bold">B360</text>
                  <defs>
                    <linearGradient id="readyGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stop-color="#00e5ff"/>
                      <stop offset="100%" stop-color="#a855f7"/>
                    </linearGradient>
                  </defs>
                </template>

              </component>
            </div>

          </div>

          <!-- Progress dots + navigation -->
          <div class="shrink-0 px-6 pb-6 pt-3" style="border-top:1px solid rgba(255,255,255,0.06)">

            <!-- Dots -->
            <div class="flex justify-center gap-1.5 mb-4">
              <button v-for="(_, i) in slides" :key="i"
                @click="step = i"
                class="rounded-full transition-all duration-200"
                :style="i === step
                  ? `width:20px; height:6px; background:${colorMap[slides[step].color].badge};`
                  : 'width:6px; height:6px; background:rgba(255,255,255,0.2);'"
                :aria-label="`Go to slide ${i + 1}`"/>
            </div>

            <!-- Buttons -->
            <div class="flex gap-3">
              <button v-if="step > 0" @click="prev"
                class="flex-1 py-3 rounded-xl text-sm font-semibold transition"
                style="background:rgba(255,255,255,0.06); color:rgba(255,255,255,0.7);
                       border:1px solid rgba(255,255,255,0.08);">
                ← Back
              </button>
              <div v-else class="flex-1" />

              <button @click="next"
                class="flex-1 py-3 rounded-xl text-sm font-bold transition"
                :style="`background:${colorMap[slides[step].color].badge}; color:#050d1a;`">
                {{ step === total - 1 ? "Let's go! 🏸" : 'Next →' }}
              </button>
            </div>

          </div>

        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.guide-fade-enter-active { transition: opacity 0.25s ease; }
.guide-fade-leave-active { transition: opacity 0.2s ease; }
.guide-fade-enter-from, .guide-fade-leave-to { opacity: 0; }

.guide-fade-enter-active .guide-panel {
  transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.25s ease;
}
.guide-fade-leave-active .guide-panel {
  transition: transform 0.2s ease, opacity 0.2s ease;
}
.guide-fade-enter-from .guide-panel { transform: translateY(40px); opacity: 0; }
.guide-fade-leave-to .guide-panel   { transform: translateY(20px); opacity: 0; }
</style>
