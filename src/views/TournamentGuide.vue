<script setup>
import { onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import { applySeo, setJsonLd } from '../lib/seo'

const steps = [
  {
    icon: '🏆', title: '1 · Create your tournament',
    text: 'Tap Create Tournament on the Tournaments page. Any club member can run one.',
    points: [
      'Pick a format: Knock-out (eliminator), Round-robin, or Groups → Knock-out.',
      'Scoring: simple Win / Walkover / Loss by default, or Best-of-3 games for a championship.',
      'Set category (Men’s / Women’s / Mixed), skill level, courts, entry fee & currency, dates.',
      'Add the venue and a Google Maps link so players can get directions.',
    ],
  },
  {
    icon: '👥', title: '2 · Add tournament admins (optional)',
    text: 'Share the load — add co-organisers by email in Settings → Tournament admins.',
    points: [
      'They must have signed in to Badminton 360 once.',
      'Every admin can approve teams, run the draw and enter scores.',
      'Only a Badminton 360 admin can rename or delete a tournament.',
    ],
  },
  {
    icon: '📣', title: '3 · Open registration & share the link',
    text: 'Set the status to “Registration open”. Your public page gets a big Register button and a shareable link.',
    points: [
      'Players register from any phone — no app or account needed, like a Google Form.',
      'They enter both players’ names + at least one email or phone; the team name auto-fills.',
      'You can also add walk-in / phone / WhatsApp teams yourself from Manage → Teams.',
    ],
  },
  {
    icon: '✅', title: '4 · Approve teams',
    text: 'You get an email for every sign-up. Review and confirm.',
    points: [
      'Open a request to check it isn’t junk or a duplicate.',
      'Approve with a confirmation message (editable) — it’s emailed to the team.',
      'When the field is full, new teams join the waitlist; promote them if a spot frees up.',
    ],
  },
  {
    icon: '🎯', title: '5 · Generate the draw',
    text: 'One tap builds the bracket from your confirmed teams.',
    points: [
      'Seeded automatically (seed 1 = random), byes handled, courts assigned for parallel play.',
      'Groups → knock-out builds the groups first, then the knock-out from the standings.',
      'Export the game plan as PDF or Excel to print or share.',
    ],
  },
  {
    icon: '🔴', title: '6 · Run it live',
    text: 'Enter results as matches finish. Followers watch the scores update live.',
    points: [
      'Simple scoring: tap the winner, or Walkover. Best-of-3: enter each game (21–18, 19–21…).',
      'Winners advance automatically; the bracket fills itself in.',
      'The public page refreshes on its own, with a LIVE badge.',
    ],
  },
  {
    icon: '🥇', title: '7 · Crown the champions',
    text: 'When the final is done, the podium is set automatically.',
    points: [
      'Download a shareable Champion card and an announcement Poster.',
      'Winners appear on their player profiles as tournament honours.',
      'Add group & tournament photos to the souvenir page.',
    ],
  },
]

const faqs = [
  { q: 'Who can create a tournament?', a: 'Any member of a club can create one for that club. The creator becomes a tournament admin automatically.' },
  { q: 'Do players need an account to register?', a: 'No. Registration is a public form — players just fill in their details. Only creating and running a tournament needs an account.' },
  { q: 'How does scoring work?', a: 'By default it’s simple: Win = 2, Walkover = 1, Loss = 0 — no point-by-point entry. Flag a tournament as “Best of 3” for full 21-point game scoring in championships.' },
  { q: 'Who can rename or delete a tournament?', a: 'Only a Badminton 360 admin. Regular tournament admins can manage everything else.' },
  { q: 'Is there a limit on teams?', a: 'You set the max teams. Once it’s full, extra sign-ups go on a waitlist you can promote from.' },
  { q: 'What does it cost?', a: 'Running tournaments on Badminton 360 is free.' },
]

onMounted(() => {
  applySeo({
    title: 'How to run a badminton tournament | Badminton 360',
    description: 'A step-by-step guide to running a badminton doubles tournament — create it, open registration, approve teams, generate the draw, score it live, and crown champions. Free.',
    keywords: 'run a badminton tournament, organise badminton tournament, badminton tournament software, doubles bracket, badminton draw',
    path: '/tournament-guide',
    type: 'article',
  })
  setJsonLd('ld-tour-guide', {
    '@context': 'https://schema.org', '@type': 'HowTo',
    name: 'How to run a badminton tournament on Badminton 360',
    step: steps.map((s, i) => ({ '@type': 'HowToStep', position: i + 1, name: s.title.replace(/^\d+ · /, ''), text: s.text })),
  })
})
</script>

<template>
  <div class="min-h-screen" style="background:#eef4ff">
    <!-- Hero -->
    <header class="relative overflow-hidden text-white"
      style="background:linear-gradient(135deg,#0b1220 0%,#0f2a4a 55%,#0a5b74 100%)">
      <div class="absolute inset-0 opacity-20" aria-hidden="true"
        style="background-image:radial-gradient(circle at 20% 30%,#22d3ee55,transparent 40%),radial-gradient(circle at 82% 22%,#a855f755,transparent 40%)"></div>
      <div class="relative max-w-3xl mx-auto px-5 sm:px-8 pb-9 pt-[calc(env(safe-area-inset-top,0px)+3.75rem)] md:pt-10">
        <RouterLink to="/tournaments" class="inline-flex items-center gap-1.5 text-sm text-white/70 hover:text-white transition mb-5">‹ Tournaments</RouterLink>
        <p class="text-[11px] uppercase tracking-widest text-cyan-300 font-bold">Guide</p>
        <h1 class="font-display text-3xl sm:text-4xl font-extrabold leading-tight mt-1">How to run a badminton tournament 🏸</h1>
        <p class="text-white/80 mt-2 max-w-xl">From your first sign-up to crowning the champions — the whole journey in seven simple steps. Setup takes about a minute.</p>
      </div>
    </header>

    <main class="max-w-3xl mx-auto px-4 sm:px-8 py-7 space-y-8">
      <!-- Steps timeline -->
      <div class="space-y-4">
        <div v-for="(s, i) in steps" :key="i" class="card p-5 flex gap-4">
          <div class="flex flex-col items-center shrink-0">
            <div class="w-11 h-11 rounded-2xl flex items-center justify-center text-xl shadow-sm"
              style="background:linear-gradient(135deg,#00e5ff,#a855f7)">{{ s.icon }}</div>
            <div v-if="i < steps.length - 1" class="w-px flex-1 bg-slate-200 mt-2"></div>
          </div>
          <div class="min-w-0">
            <h2 class="font-display font-bold text-slate-800">{{ s.title }}</h2>
            <p class="text-sm text-slate-500 mt-1">{{ s.text }}</p>
            <ul class="mt-2.5 space-y-1.5">
              <li v-for="(p, j) in s.points" :key="j" class="flex gap-2 text-xs text-slate-600 leading-relaxed">
                <span class="text-emerald-500 shrink-0">✓</span><span>{{ p }}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <!-- FAQ -->
      <div>
        <h2 class="font-display text-xl font-bold text-slate-800 mb-3">Frequently asked</h2>
        <div class="space-y-2">
          <details v-for="(f, i) in faqs" :key="i" class="card p-4 group">
            <summary class="cursor-pointer list-none flex items-center justify-between gap-3 font-semibold text-slate-800 text-sm">
              {{ f.q }}
              <span class="text-slate-400 group-open:rotate-45 transition-transform text-lg leading-none">+</span>
            </summary>
            <p class="text-sm text-slate-500 mt-2 leading-relaxed">{{ f.a }}</p>
          </details>
        </div>
      </div>

      <!-- CTA -->
      <div class="rounded-3xl p-6 text-center text-white relative overflow-hidden"
        style="background:linear-gradient(120deg,#00b4d8 0%,#7c3aed 100%)">
        <div class="absolute inset-0 opacity-25" aria-hidden="true"
          style="background-image:radial-gradient(circle at 15% 20%,#ffffff55,transparent 35%),radial-gradient(circle at 85% 80%,#ffffff33,transparent 40%)"></div>
        <div class="relative">
          <p class="font-display text-2xl font-extrabold">Ready to run yours?</p>
          <p class="text-white/85 text-sm mt-1">Create a tournament and share the link in minutes.</p>
          <RouterLink to="/tournaments" class="inline-block mt-4 bg-white text-slate-900 font-bold rounded-full px-7 py-2.5 text-sm shadow no-underline">
            Go to Tournaments →
          </RouterLink>
        </div>
      </div>

      <div class="text-center py-4">
        <RouterLink to="/" class="text-xs text-slate-400 hover:text-neon transition">Powered by <span class="font-semibold gradient-text">Badminton 360</span> →</RouterLink>
      </div>
    </main>
  </div>
</template>
