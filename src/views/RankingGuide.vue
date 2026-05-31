<script setup>
import PageHeader from '../components/PageHeader.vue'
const steps = [
  {
    icon: '🏁',
    title: 'Everyone starts at 1,000 Elo',
    body: 'When you join Badmint, your skill score begins at 1,000. Think of this as your starting bank balance. It goes up when you win and down when you lose — but by how much depends on who you played against.'
  },
  {
    icon: '⚡',
    title: 'Beating a stronger pair earns more',
    body: 'If you beat a pair with higher combined Elo than yours, you gain more points — because it was an upset. If you beat a weaker pair, you gain less — it was expected. This keeps the system honest and prevents easy point-farming.'
  },
  {
    icon: '👥',
    title: 'Doubles uses the pair\'s average',
    body: 'Since teams mix every day, the app averages the two players\' Elo on each side before calculating the expected result. Both players on the winning side gain points; both on the losing side lose points. Your partner\'s skill affects how much you gain.'
  },
  {
    icon: '📅',
    title: 'Attendance rewards regulars',
    body: 'Your attendance score is simply the total number of days you\'ve shown up to play. This is kept separate from skill. Someone who plays every day and wins 50% of matches will rank higher than a skilled player who only comes twice a month.'
  },
  {
    icon: '🧮',
    title: 'Final rank = Skill (70%) + Attendance (30%)',
    body: 'Both scores are scaled to 0–100 within your club, then blended. The best Elo player gets 100 for skill. The most regular attender gets 100 for participation. Everyone else falls in between. Your manager can adjust the 70/30 split in Settings.'
  },
  {
    icon: '📈',
    title: 'Rankings settle over time',
    body: 'Elo takes 20–30 matches per person to stabilise. The first few weeks will feel slightly noisy. After 4–6 weeks of regular play, the leaderboard will reflect true skill and commitment levels accurately.'
  }
]

const faqs = [
  {
    q: 'Can I gain points even if I lose?',
    a: 'No — Elo always transfers from losers to winners. But if you lose to a much stronger pair, you lose very few points (e.g. just 2–4). The system expects you to lose, so it doesn\'t punish you much.'
  },
  {
    q: 'What if I don\'t come for a month?',
    a: 'Your Elo stays frozen — it doesn\'t decay. Your attendance score won\'t grow either. Other regulars\' attendance scores will pull ahead, which lowers your composite rank even though your skill is unchanged.'
  },
  {
    q: 'Does my partner\'s rating affect mine?',
    a: 'Yes — your gains and losses are calculated using the side average. Playing with a much weaker partner means you\'re the "stronger side" on paper, so you gain less from winning and lose more from losing. Choose your partner wisely!'
  },
  {
    q: 'What is K-factor?',
    a: 'K is how many points are at stake each match. Default is 24. Higher K means bigger swings after each match (more exciting, less stable). Lower K means slower movement (more stable, takes longer to reflect true skill). Your manager can change it in Settings.'
  },
  {
    q: 'Why is my Elo score different from my ranking points?',
    a: 'Elo is the raw skill number (e.g. 1,143). Ranking points are the blended composite score (0–100 scale) that combines skill + attendance. The leaderboard sorts by composite, not raw Elo.'
  },
  {
    q: 'Best Pair — how is it calculated?',
    a: 'Every time two players are on the same side, that match counts as a pair result. The pair with the highest win percentage (minimum 1 game together) is shown as Best Pair. Win % is games won ÷ games played together.'
  }
]
</script>

<template>
  <div>
    <PageHeader icon="📖" title="How Ranking Works"
      subtitle="Everything you need to understand your Badmint rank" />

    <!-- Formula card -->
    <div class="card p-5 mb-5 ring-1 ring-teal-500/20">
      <div class="label">The Formula</div>
      <div class="rounded-xl bg-white/5 px-4 py-3 font-mono text-sm text-center mb-3">
        <span class="text-teal-400">Rank Points</span> =
        <span class="text-amber-400">Skill</span> × 70% +
        <span class="text-purple-400">Attendance</span> × 30%
      </div>
      <div class="grid grid-cols-3 gap-2 text-center text-xs">
        <div class="rounded-lg bg-teal-500/10 p-2">
          <div class="text-teal-400 font-semibold">Skill (Elo)</div>
          <div class="text-slate-400 mt-0.5">Normalised 0–100 within your club</div>
        </div>
        <div class="rounded-lg bg-white/5 p-2 flex items-center justify-center text-slate-500">
          +
        </div>
        <div class="rounded-lg bg-purple-500/10 p-2">
          <div class="text-purple-400 font-semibold">Attendance</div>
          <div class="text-slate-400 mt-0.5">Total days played, normalised 0–100</div>
        </div>
      </div>
      <p class="text-xs text-slate-500 mt-3 text-center">
        Managers can adjust the 70/30 split in ⚙️ Manage → Ranking Weights
      </p>
    </div>

    <!-- Step by step -->
    <div class="label mb-2">Step by Step</div>
    <div class="space-y-2 mb-5">
      <div v-for="(s, i) in steps" :key="i" class="card p-4 flex gap-3">
        <div class="text-2xl shrink-0 mt-0.5">{{ s.icon }}</div>
        <div>
          <div class="font-semibold text-sm mb-1">{{ s.title }}</div>
          <div class="text-xs text-slate-400 leading-relaxed">{{ s.body }}</div>
        </div>
      </div>
    </div>

    <!-- Elo example -->
    <div class="card p-4 mb-5 border-amber-400/20 border">
      <div class="label">Live Example</div>
      <div class="text-xs text-slate-300 space-y-2 leading-relaxed">
        <div class="flex gap-2 items-center">
          <div class="rounded-lg bg-teal-500/15 px-2 py-1 text-teal-300 text-[11px]">Side A</div>
          <span>Ahmed (1100) + Ravi (900) → average <strong>1000</strong></span>
        </div>
        <div class="flex gap-2 items-center">
          <div class="rounded-lg bg-amber-500/15 px-2 py-1 text-amber-300 text-[11px]">Side B</div>
          <span>Sanjay (1050) + Khalid (1050) → average <strong>1050</strong></span>
        </div>
        <div class="border-t border-white/10 pt-2">
          Side B is slightly favoured. If <strong>Side A wins</strong>:
          Ahmed +14 pts, Ravi +14 pts, Sanjay −14 pts, Khalid −14 pts.
        </div>
        <div>
          If <strong>Side B wins</strong> (expected):
          Each gains only +10 pts (smaller reward for expected result).
        </div>
      </div>
    </div>

    <!-- FAQ -->
    <div class="label mb-2">Common Questions</div>
    <div class="space-y-2">
      <details v-for="(f, i) in faqs" :key="i"
        class="card group open:ring-1 open:ring-teal-500/20">
        <summary class="flex items-center justify-between px-4 py-3 cursor-pointer list-none text-sm font-medium">
          {{ f.q }}
          <span class="text-slate-500 group-open:text-teal-400 transition text-lg leading-none">+</span>
        </summary>
        <div class="px-4 pb-4 text-xs text-slate-400 leading-relaxed border-t border-white/5 pt-3">
          {{ f.a }}
        </div>
      </details>
    </div>
  </div>
</template>
