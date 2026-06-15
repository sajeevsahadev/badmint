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
  cyan:   { accent: '#0099bb', light: 'rgba(0,153,187,0.08)', border: 'rgba(0,153,187,0.2)',  btn: '#00e5ff', btnText: '#050d1a' },
  violet: { accent: '#7c3aed', light: 'rgba(124,58,237,0.08)', border: 'rgba(124,58,237,0.2)', btn: '#a855f7', btnText: '#fff'    },
  amber:  { accent: '#b45309', light: 'rgba(180,83,9,0.08)',   border: 'rgba(180,83,9,0.2)',   btn: '#fbbf24', btnText: '#050d1a' },
}
</script>

<template>
  <Teleport to="body">
    <Transition name="guide-fade">
      <div class="fixed inset-0 z-[200] flex items-end sm:items-center justify-center p-0 sm:p-4"
        style="background:rgba(5,13,26,0.7); backdrop-filter:blur(6px);">

        <div class="guide-panel w-full sm:max-w-md rounded-t-3xl sm:rounded-3xl overflow-hidden flex flex-col"
          style="background:#ffffff; border:1px solid rgba(0,0,0,0.08);
                 box-shadow:0 24px 64px rgba(0,0,0,0.25), 0 4px 16px rgba(0,0,0,0.1);
                 max-height:92dvh;">

          <!-- Top stripe accent bar -->
          <div class="h-1 w-full shrink-0 transition-all duration-300"
            :style="`background:linear-gradient(90deg, ${colorMap[slides[step].color].btn}, ${colorMap[slides[step].color].accent})`" />

          <!-- Header row: step label + skip -->
          <div class="flex items-center justify-between px-5 pt-4 pb-0 shrink-0">
            <span class="text-[11px] font-bold tracking-widest uppercase"
              :style="`color:${colorMap[slides[step].color].accent}`">
              Step {{ step + 1 }} of {{ total }}
            </span>
            <button @click="finish"
              class="text-xs text-slate-400 hover:text-slate-600 transition px-2 py-1 rounded-lg hover:bg-slate-100">
              Skip ✕
            </button>
          </div>

          <!-- Slide content -->
          <div class="flex-1 overflow-y-auto px-6 pt-4 pb-2">

            <!-- Emoji + title -->
            <div class="flex flex-col items-center text-center mb-5">

              <div class="relative mb-4">
                <div class="w-24 h-24 rounded-2xl flex items-center justify-center text-5xl"
                  :style="`background:${colorMap[slides[step].color].light}; border:1.5px solid ${colorMap[slides[step].color].border};`">
                  {{ slides[step].emoji }}
                </div>
              </div>

              <!-- Title — dark text, readable on white -->
              <h2 class="font-display text-xl font-extrabold mb-3 leading-tight text-slate-800">
                {{ slides[step].title }}
              </h2>

              <!-- Story — proper dark body text -->
              <p class="text-slate-600 text-sm leading-relaxed mb-4">
                {{ slides[step].story }}
              </p>

              <!-- Tip chip -->
              <div class="flex items-start gap-2.5 px-4 py-3 rounded-xl text-xs font-medium text-left w-full"
                :style="`background:${colorMap[slides[step].color].light}; border:1px solid ${colorMap[slides[step].color].border};`">
                <span class="shrink-0 mt-0.5">💡</span>
                <span :style="`color:${colorMap[slides[step].color].accent}`" class="font-semibold">
                  {{ slides[step].tip }}
                </span>
              </div>
            </div>

            <!-- Mini diagram — dark card on white, looks like a preview screen -->
            <div class="rounded-2xl overflow-hidden mb-2"
              style="border:1px solid rgba(0,0,0,0.07); box-shadow:0 2px 8px rgba(0,0,0,0.06);">
              <svg viewBox="0 0 360 140" xmlns="http://www.w3.org/2000/svg"
                class="w-full" style="display:block;">

                <!-- Slide 0: Welcome — players on a court -->
                <template v-if="step === 0">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="40" y="30" width="280" height="80" rx="4" fill="none" stroke="#00e5ff30" stroke-width="1.5"/>
                  <line x1="200" y1="30" x2="200" y2="110" stroke="#00e5ff30" stroke-width="1.5"/>
                  <line x1="40" y1="70" x2="320" y2="70" stroke="#a855f720" stroke-width="1"/>
                  <rect x="196" y="28" width="8" height="84" rx="2" fill="#00e5ff40"/>
                  <circle cx="100" cy="52" r="11" fill="#00e5ff"/>
                  <text x="100" y="57" text-anchor="middle" font-size="10" fill="#050d1a" font-weight="bold">D</text>
                  <circle cx="140" cy="88" r="11" fill="#00e5ff" opacity=".75"/>
                  <text x="140" y="93" text-anchor="middle" font-size="10" fill="#050d1a" font-weight="bold">A</text>
                  <circle cx="260" cy="52" r="11" fill="#a855f7"/>
                  <text x="260" y="57" text-anchor="middle" font-size="10" fill="#fff">R</text>
                  <circle cx="220" cy="88" r="11" fill="#a855f7" opacity=".75"/>
                  <text x="220" y="93" text-anchor="middle" font-size="10" fill="#fff">K</text>
                  <ellipse cx="185" cy="52" rx="5" ry="7" fill="#fbbf24"/>
                  <text x="100" y="128" text-anchor="middle" font-size="12" fill="#00e5ff" font-weight="bold">21</text>
                  <text x="180" y="128" text-anchor="middle" font-size="11" fill="#ffffff40">vs</text>
                  <text x="260" y="128" text-anchor="middle" font-size="12" fill="#a855f7" font-weight="bold">18</text>
                </template>

                <!-- Slide 1: Create Club -->
                <template v-else-if="step === 1">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="120" y="12" width="120" height="116" rx="14" fill="none" stroke="#00e5ff30" stroke-width="1.5"/>
                  <rect x="128" y="22" width="104" height="96" rx="8" fill="#1e293b"/>
                  <rect x="136" y="34" width="88" height="18" rx="5" fill="none" stroke="#00e5ff50" stroke-width="1"/>
                  <text x="143" y="47" font-size="7.5" fill="#00e5ffcc">Dev's Saturday Crew</text>
                  <rect x="136" y="60" width="88" height="20" rx="6" fill="#00e5ff"/>
                  <text x="180" y="73" text-anchor="middle" font-size="9" fill="#050d1a" font-weight="bold">Create Club</text>
                  <circle cx="180" cy="108" r="14" fill="#00e5ff20" stroke="#00e5ff50" stroke-width="1"/>
                  <text x="180" y="114" text-anchor="middle" font-size="15" fill="#00e5ff">✓</text>
                </template>

                <!-- Slide 2: Invite -->
                <template v-else-if="step === 2">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="148" y="18" width="64" height="104" rx="10" fill="none" stroke="#a855f740" stroke-width="1.5"/>
                  <rect x="154" y="26" width="52" height="88" rx="6" fill="#1e293b"/>
                  <circle cx="180" cy="55" r="15" fill="#25d36620"/>
                  <text x="180" y="61" text-anchor="middle" font-size="16">💬</text>
                  <rect x="158" y="78" width="44" height="9" rx="3" fill="#a855f730"/>
                  <text x="180" y="85" text-anchor="middle" font-size="6.5" fill="#a855f7">invite link</text>
                  <line x1="148" y1="68" x2="78" y2="48" stroke="#a855f750" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="148" y1="80" x2="73" y2="102" stroke="#a855f750" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="212" y1="68" x2="282" y2="48" stroke="#a855f750" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="212" y1="80" x2="287" y2="102" stroke="#a855f750" stroke-width="1" stroke-dasharray="3,2"/>
                  <circle cx="66" cy="46" r="11" fill="#a855f7"/><text x="66" y="51" text-anchor="middle" font-size="9" fill="#fff">A</text>
                  <circle cx="61" cy="102" r="11" fill="#a855f7"/><text x="61" y="107" text-anchor="middle" font-size="9" fill="#fff">B</text>
                  <circle cx="294" cy="46" r="11" fill="#00e5ff"/><text x="294" y="51" text-anchor="middle" font-size="9" fill="#050d1a">C</text>
                  <circle cx="299" cy="102" r="11" fill="#00e5ff"/><text x="299" y="107" text-anchor="middle" font-size="9" fill="#050d1a">D</text>
                </template>

                <!-- Slide 3: Record Match -->
                <template v-else-if="step === 3">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="28" y="22" width="132" height="94" rx="10" fill="#00e5ff0d" stroke="#00e5ff40" stroke-width="1"/>
                  <text x="94" y="40" text-anchor="middle" font-size="9" fill="#00e5ff" font-weight="bold">SIDE A</text>
                  <circle cx="68" cy="64" r="11" fill="#00e5ff"/><text x="68" y="69" text-anchor="middle" font-size="9" fill="#050d1a">D</text>
                  <circle cx="120" cy="64" r="11" fill="#00e5ff" opacity=".7"/><text x="120" y="69" text-anchor="middle" font-size="9" fill="#050d1a">A</text>
                  <text x="94" y="103" text-anchor="middle" font-size="24" fill="#fbbf24" font-weight="bold">21</text>
                  <rect x="200" y="22" width="132" height="94" rx="10" fill="#a855f70d" stroke="#a855f740" stroke-width="1"/>
                  <text x="266" y="40" text-anchor="middle" font-size="9" fill="#a855f7" font-weight="bold">SIDE B</text>
                  <circle cx="240" cy="64" r="11" fill="#a855f7"/><text x="240" y="69" text-anchor="middle" font-size="9" fill="#fff">R</text>
                  <circle cx="292" cy="64" r="11" fill="#a855f7" opacity=".7"/><text x="292" y="69" text-anchor="middle" font-size="9" fill="#fff">K</text>
                  <text x="266" y="103" text-anchor="middle" font-size="24" fill="#fbbf24" font-weight="bold">18</text>
                  <text x="180" y="68" text-anchor="middle" font-size="11" fill="#ffffff40">vs</text>
                  <rect x="130" y="122" width="100" height="14" rx="7" fill="#fbbf24"/>
                  <text x="180" y="132" text-anchor="middle" font-size="8" fill="#050d1a" font-weight="bold">Record Match</text>
                </template>

                <!-- Slide 4: Leaderboard -->
                <template v-else-if="step === 4">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="140" y="52" width="80" height="62" rx="4" fill="#fbbf2420" stroke="#fbbf2450" stroke-width="1"/>
                  <rect x="72"  y="72" width="63" height="42" rx="4" fill="#64748b20" stroke="#64748b50" stroke-width="1"/>
                  <rect x="225" y="80" width="63" height="34" rx="4" fill="#f9731620" stroke="#f9731650" stroke-width="1"/>
                  <text x="180" y="44" text-anchor="middle" font-size="16">🥇</text>
                  <text x="103" y="65" text-anchor="middle" font-size="14">🥈</text>
                  <text x="256" y="72" text-anchor="middle" font-size="14">🥉</text>
                  <text x="180" y="74" text-anchor="middle" font-size="8.5" fill="#fbbf24" font-weight="bold">Dev</text>
                  <text x="180" y="86" text-anchor="middle" font-size="7" fill="#fbbf2499">1187 Elo</text>
                  <text x="103" y="90" text-anchor="middle" font-size="8" fill="#94a3b8">Anil</text>
                  <text x="256" y="96" text-anchor="middle" font-size="8" fill="#f97316">Ravi</text>
                  <rect x="38" y="122" width="284" height="12" rx="3" fill="#ffffff08"/>
                  <text x="50" y="131" font-size="7.5" fill="#ffffff50">#4  Sam  ·  1050 Elo</text>
                  <text x="220" y="131" font-size="7.5" fill="#ffffff50">#5  Kiran  ·  1038</text>
                </template>

                <!-- Slide 5: PaySplits -->
                <template v-else-if="step === 5">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="48" y="16" width="264" height="52" rx="10" fill="#00e5ff0a" stroke="#00e5ff30" stroke-width="1"/>
                  <text x="66" y="34" font-size="8" fill="#94a3b8">Court Booking — Saturday</text>
                  <text x="66" y="52" font-size="17" fill="#00e5ff" font-weight="bold">AED 180</text>
                  <text x="292" y="44" text-anchor="end" font-size="8" fill="#ffffff50">÷ 12 players</text>
                  <text x="180" y="82" text-anchor="middle" font-size="14" fill="#00e5ff50">↓</text>
                  <rect x="48" y="88" width="264" height="46" rx="10" fill="#1e293b" stroke="#ffffff0a" stroke-width="1"/>
                  <text x="64" y="107" font-size="8" fill="#94a3b8">Dev</text>
                  <text x="296" y="107" text-anchor="end" font-size="8" fill="#f87171" font-weight="bold">owes AED 15</text>
                  <line x1="58" y1="113" x2="302" y2="113" stroke="#ffffff10" stroke-width="1"/>
                  <text x="64" y="126" font-size="8" fill="#94a3b8">Anil</text>
                  <text x="296" y="126" text-anchor="end" font-size="8" fill="#4ade80" font-weight="bold">gets AED 30</text>
                </template>

                <!-- Slide 6: Wallet -->
                <template v-else-if="step === 6">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <rect x="128" y="22" width="104" height="72" rx="12" fill="#fbbf2410" stroke="#fbbf2440" stroke-width="1.5"/>
                  <text x="180" y="50" text-anchor="middle" font-size="11" fill="#fbbf24" font-weight="bold">Club Pool</text>
                  <text x="180" y="70" text-anchor="middle" font-size="19" fill="#fbbf24" font-weight="bold">AED 700</text>
                  <text x="180" y="84" text-anchor="middle" font-size="7.5" fill="#fbbf2480">14 × AED 50</text>
                  <circle cx="90" cy="36" r="9" fill="#fbbf2420" stroke="#fbbf2440" stroke-width="1"/>
                  <text x="90" y="41" text-anchor="middle" font-size="9">💰</text>
                  <circle cx="270" cy="36" r="9" fill="#fbbf2420" stroke="#fbbf2440" stroke-width="1"/>
                  <text x="270" y="41" text-anchor="middle" font-size="9">💰</text>
                  <line x1="97" y1="43" x2="126" y2="54" stroke="#fbbf2450" stroke-width="1" stroke-dasharray="3,2"/>
                  <line x1="263" y1="43" x2="234" y2="54" stroke="#fbbf2450" stroke-width="1" stroke-dasharray="3,2"/>
                  <rect x="76" y="108" width="208" height="24" rx="8" fill="#fbbf2412" stroke="#fbbf2440" stroke-width="1"/>
                  <text x="180" y="123" text-anchor="middle" font-size="8" fill="#fbbf24">Court fee auto-deducted each week ✓</text>
                </template>

                <!-- Slide 7: Ready! -->
                <template v-else-if="step === 7">
                  <rect width="360" height="140" fill="#0f172a"/>
                  <defs>
                    <linearGradient id="readyGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stop-color="#00e5ff"/>
                      <stop offset="100%" stop-color="#a855f7"/>
                    </linearGradient>
                  </defs>
                  <circle cx="180" cy="70" r="52" fill="none" stroke="url(#readyGrad)" stroke-width="1.5" opacity=".6"/>
                  <circle cx="180" cy="70" r="38" fill="none" stroke="#ffffff10" stroke-width="1"/>
                  <text x="180" y="30"  text-anchor="middle" font-size="14">🏆</text>
                  <text x="224" y="47"  text-anchor="middle" font-size="14">📋</text>
                  <text x="233" y="94"  text-anchor="middle" font-size="14">💰</text>
                  <text x="180" y="115" text-anchor="middle" font-size="14">📅</text>
                  <text x="127" y="94"  text-anchor="middle" font-size="14">👥</text>
                  <text x="136" y="47"  text-anchor="middle" font-size="14">🎯</text>
                  <text x="180" y="63"  text-anchor="middle" font-size="22">🏸</text>
                  <text x="180" y="81"  text-anchor="middle" font-size="8.5" fill="#00e5ff" font-weight="bold">B360</text>
                </template>

              </svg>
            </div>

          </div>

          <!-- Progress dots + navigation -->
          <div class="shrink-0 px-6 pb-6 pt-4" style="border-top:1px solid rgba(0,0,0,0.06)">

            <!-- Dots -->
            <div class="flex justify-center gap-1.5 mb-4">
              <button v-for="(_, i) in slides" :key="i"
                @click="step = i"
                class="rounded-full transition-all duration-300"
                :style="i === step
                  ? `width:20px; height:6px; background:${colorMap[slides[step].color].btn};`
                  : 'width:6px; height:6px; background:rgba(0,0,0,0.15);'"
                :aria-label="`Go to slide ${i + 1}`"/>
            </div>

            <!-- Buttons -->
            <div class="flex gap-3">
              <button v-if="step > 0" @click="prev"
                class="flex-1 py-3 rounded-xl text-sm font-semibold transition text-slate-600 hover:text-slate-800 hover:bg-slate-100"
                style="background:#f8fafc; border:1px solid rgba(0,0,0,0.1);">
                ← Back
              </button>
              <div v-else class="flex-1" />

              <button @click="next"
                class="flex-1 py-3 rounded-xl text-sm font-bold transition"
                :style="`background:${colorMap[slides[step].color].btn}; color:${colorMap[slides[step].color].btnText};`">
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
