<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'
import InfoTip from '../components/InfoTip.vue'
import PageHeader from '../components/PageHeader.vue'
import Avatar from '../components/Avatar.vue'
import { usePlayerAvatars } from '../composables/usePlayerAvatars'

const { user } = useAuth()
const { currentClub } = useClub()
const { avatarMap, loadAvatars } = usePlayerAvatars()

const board     = ref([])
const bestPairs = ref([])
const dayHeroes = ref({ date: null, players: [] })
const loading   = ref(true)
const showFull  = ref(true)

const medals = ['🥇', '🥈', '🥉']
const isMe   = p => p.user_id === user.value?.id
const trendColor = elo => elo >= 1050 ? 'text-neon' : elo <= 950 ? 'text-rose-400' : 'text-slate-500'
const medalBg = i => i === 0
  ? 'bg-amber-50 border-amber-200'
  : i === 1
    ? 'bg-slate-50 border-slate-200'
    : 'bg-orange-50 border-orange-200'
const medalColor = i => i === 0 ? '#b45309' : i === 1 ? '#64748b' : '#c2410c'

let _loadKey = 0
async function load() {
  if (!currentClub.value) { loading.value = false; return }
  const key = ++_loadKey
  loading.value = true
  const cid = currentClub.value.club_id
  const [{ data: lb }, { data: bp }, { data: heroes }] = await Promise.all([
    supabase.from('v_leaderboard').select('*').eq('club_id', cid).gt('games', 0).order('club_rank'),
    supabase.from('v_best_pairs').select('*').eq('club_id', cid)
      .order('win_pct', { ascending: false }).order('games', { ascending: false }).limit(5),
    supabase.rpc('get_day_heroes', { p_club_id: cid }),
  ])
  if (key !== _loadKey) return
  board.value     = lb ?? []
  bestPairs.value = bp ?? []
  dayHeroes.value = heroes ?? { date: null, players: [] }
  loading.value   = false
  loadAvatars([
    ...board.value.map(p => p.user_id),
    ...bestPairs.value.flatMap(p => [p.p1_user_id, p.p2_user_id])
  ])
}

onMounted(load)
watch(currentClub, load)

const clubName = computed(() => currentClub.value?.clubs?.name ?? '')
const podium   = computed(() => board.value.slice(0, 3))
const rest     = computed(() => board.value.slice(3))

// ── Today's Heroes — standouts from the club's most recent match day ──
const todayStr = (() => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
})()
const heroesDate   = computed(() => dayHeroes.value?.date || null)
const heroesToday  = computed(() => heroesDate.value === todayStr)
const heroDateLabel = computed(() => heroesDate.value
  ? new Date(heroesDate.value + 'T00:00:00').toLocaleDateString('en-AE', { weekday: 'long', day: 'numeric', month: 'short' })
  : '')

// Pick up to three DIFFERENT people so recognition is spread around, not all
// heaped on one player. Top Climber → Most Wins → Most Active, each excluding
// anyone already awarded.
const dayAwards = computed(() => {
  const arr = dayHeroes.value?.players || []
  if (!arr.length) return []
  const used = new Set()
  const out = []
  const pick = (label, icon, better, statFn, guard) => {
    const cand = arr.filter(p => !used.has(p.player_id) && guard(p))
    if (!cand.length) return
    const win = cand.reduce((a, b) => (better(a, b) ? b : a))
    used.add(win.player_id)
    out.push({ label, icon, p: win, stat: statFn(win) })
  }
  pick('Top Climber', '🚀', (a, b) => b.delta > a.delta, p => `+${p.delta} Elo`, p => p.delta > 0)
  pick('Most Wins', '🏆', (a, b) => b.wins > a.wins || (b.wins === a.wins && b.delta > a.delta),
    p => `${p.wins} ${p.wins === 1 ? 'win' : 'wins'}`, p => p.wins > 0)
  pick('Most Active', '🎯', (a, b) => b.games > a.games || (b.games === a.games && b.wins > a.wins),
    p => `${p.games} games`, p => p.games >= 1)
  return out
})

// Per-award celebration colours (accent text, glow halo, soft stat pill).
const HERO_STYLE = {
  'Top Climber': { accent: '#d97706', glow: 'rgba(245,158,11,.40)', soft: 'rgba(245,158,11,.14)' },
  'Most Wins':   { accent: '#0891a8', glow: 'rgba(0,180,216,.40)',  soft: 'rgba(0,180,216,.14)' },
  'Most Active': { accent: '#8b5cf6', glow: 'rgba(168,85,247,.40)', soft: 'rgba(168,85,247,.14)' },
}
const heroStyle = label => HERO_STYLE[label] || HERO_STYLE['Top Climber']
</script>

<template>
  <!-- Loading skeleton -->
  <div v-if="loading" class="space-y-3 fade-up">
    <div class="h-10 shimmer rounded-2xl" />
    <div class="grid grid-cols-3 gap-2">
      <div class="h-28 shimmer rounded-2xl" />
      <div class="h-28 shimmer rounded-2xl" />
      <div class="h-28 shimmer rounded-2xl" />
    </div>
    <div class="h-64 shimmer rounded-2xl" />
  </div>

  <div v-else class="space-y-4 fade-up">

    <!-- Header -->
    <div class="flex items-center justify-between">
      <PageHeader icon="🏆" title="Scoreboard" :subtitle="clubName" />
      <button class="text-xs text-neon hover:opacity-75 transition shrink-0"
        @click="showFull = !showFull">
        {{ showFull ? 'Show less ↑' : 'Show more ↓' }}
      </button>
    </div>

    <!-- No data -->
    <div v-if="!board.length" class="card p-8 text-center">
      <div class="text-3xl mb-3">🏸</div>
      <p class="text-sm font-semibold text-slate-700 mb-1">No matches yet</p>
      <p class="text-xs text-slate-400">Record your first match to start the scoreboard.</p>
    </div>

    <template v-else>

      <!-- ── Top 3 Podium ──────────────────────────────────────────────── -->
      <div class="grid grid-cols-3 gap-2">
        <div v-for="(p, i) in podium" :key="p.id"
          class="rounded-2xl border p-3 flex flex-col items-center text-center"
          :class="[medalBg(i), isMe(p) ? 'ring-2 ring-cyan-400/50' : '']">

          <!-- Medal badge with rank number -->
          <div class="relative mb-2">
            <span class="text-2xl">{{ medals[i] }}</span>
            <div class="absolute -bottom-1 -right-2 w-5 h-5 rounded-full flex items-center justify-center
                        text-[9px] font-bold text-white shadow-sm"
              :style="`background:${medalColor(i)}`">
              {{ i + 1 }}
            </div>
          </div>

          <!-- Avatar -->
          <Avatar :name="p.display_name" :src="avatarMap[p.user_id]" :size="44" class="mb-1.5" />

          <!-- Name -->
          <RouterLink :to="'/player/' + p.id"
            class="text-xs font-bold leading-tight mb-1.5 hover:text-neon transition-colors line-clamp-2"
            :class="isMe(p) ? 'text-cyan-700' : 'text-slate-700'">
            {{ p.display_name }}
          </RouterLink>

          <!-- Elo — the app's single ranking metric -->
          <div class="text-sm font-extrabold" :style="`color:${medalColor(i)}`">
            {{ p.elo }} <span class="text-[10px] font-semibold text-slate-400">Elo</span>
          </div>
          <div class="text-[10px] text-slate-400 mt-0.5">{{ p.win_pct }}% win</div>
        </div>
      </div>

      <!-- ── Today's Heroes (latest match day) ─────────────────────────── -->
      <div v-if="dayAwards.length" class="card overflow-hidden hero-card">
        <div class="hero-header px-4 py-3 border-b border-slate-100 flex items-center justify-between">
          <!-- floating confetti bits -->
          <span class="confetti c1"></span><span class="confetti c2"></span>
          <span class="confetti c3"></span><span class="confetti c4"></span>
          <span class="confetti c5"></span><span class="confetti c6"></span>
          <div class="relative z-[1]">
            <div class="text-xs font-bold text-slate-700">
              {{ heroesToday ? "🎉 Today's Heroes" : "🎉 Last Session Heroes" }}
            </div>
            <div class="text-[10px] text-slate-500 mt-0.5">{{ heroDateLabel }}</div>
          </div>
          <InfoTip text="Standouts from the club's most recent match day — Elo gained, wins and games played. Refreshes every time you play, so there's a new hero to chase each session." />
        </div>
        <div class="grid" :style="`grid-template-columns:repeat(${dayAwards.length},minmax(0,1fr))`">
          <RouterLink v-for="(a, i) in dayAwards" :key="a.label" :to="'/player/' + a.p.player_id"
            class="hero-cell flex flex-col items-center text-center px-2 py-5"
            :class="i > 0 ? 'border-l border-slate-100' : ''"
            :style="`--accent:${heroStyle(a.label).accent};--glow:${heroStyle(a.label).glow};--soft:${heroStyle(a.label).soft}`">
            <div class="text-lg leading-none mb-1">{{ a.icon }}</div>
            <div class="text-[9px] font-bold uppercase tracking-wide mb-2.5" :style="`color:${heroStyle(a.label).accent}`">{{ a.label }}</div>
            <div class="hero-avatar-wrap">
              <span class="hero-glow"></span>
              <span v-if="i === 0" class="hero-crown">👑</span>
              <span class="hero-spark s1">✨</span>
              <span class="hero-spark s2">✦</span>
              <span class="hero-spark s3">✧</span>
              <Avatar :name="a.p.name" :src="avatarMap[a.p.user_id]" :size="46" class="hero-avatar" />
            </div>
            <div class="text-xs font-bold text-slate-700 leading-tight line-clamp-1 w-full mt-2">{{ a.p.name }}</div>
            <div class="hero-stat">{{ a.stat }}</div>
          </RouterLink>
        </div>
      </div>

      <!-- ── Full Leaderboard Table ────────────────────────────────────── -->
      <div class="card overflow-hidden">
        <div class="px-4 py-3 flex items-center justify-between border-b border-slate-100">
          <span class="text-xs font-bold text-slate-600 tracking-wide">Full Leaderboard</span>
          <InfoTip text="Ranked by Elo rating — updated after every match. Win against stronger players to climb faster." />
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-slate-100 bg-slate-50/60">
                <th class="pl-4 pr-2 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-400 font-semibold">#</th>
                <th class="pl-2 pr-3 py-2.5 text-left text-[10px] uppercase tracking-wider text-slate-400 font-semibold">Player</th>
                <th class="px-2 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400 font-semibold">Elo</th>
                <th class="px-2 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400 font-semibold">W%</th>
                <th class="pl-2 pr-4 py-2.5 text-right text-[10px] uppercase tracking-wider text-slate-400 font-semibold">Days</th>
              </tr>
            </thead>
            <tbody>
              <!-- Top 3 always shown -->
              <tr v-for="(p, i) in podium" :key="p.id"
                class="border-b border-slate-50 transition-colors"
                :class="isMe(p) ? 'bg-cyan-50/70' : i === 0 ? 'bg-amber-50/40' : 'hover:bg-slate-50'">
                <td class="pl-4 pr-2 py-3 text-base leading-none">{{ medals[i] }}</td>
                <td class="pl-2 pr-3 py-3">
                  <div class="flex items-center gap-2">
                    <Avatar :name="p.display_name" :src="avatarMap[p.user_id]" :size="28" />
                    <RouterLink :to="'/player/' + p.id"
                      class="font-semibold hover:text-neon transition-colors"
                      :class="isMe(p) ? 'text-cyan-700' : 'text-slate-800'">
                      {{ p.display_name }}
                      <span v-if="isMe(p)" class="text-[10px] text-cyan-500 font-normal ml-1">you</span>
                    </RouterLink>
                  </div>
                </td>
                <td class="px-2 py-3 text-right text-xs font-semibold" :class="trendColor(p.elo)">{{ p.elo }}</td>
                <td class="px-2 py-3 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
                <td class="pl-2 pr-4 py-3 text-right text-xs text-slate-400">{{ p.days_played }}</td>
              </tr>

              <!-- Rest: shown only when expanded -->
              <template v-if="showFull">
                <tr v-for="(p, i) in rest" :key="p.id"
                  class="border-b border-slate-50 last:border-0 transition-colors"
                  :class="isMe(p) ? 'bg-cyan-50/70' : 'hover:bg-slate-50'">
                  <td class="pl-4 pr-2 py-3 text-xs font-bold text-slate-400">{{ i + 4 }}</td>
                  <td class="pl-2 pr-3 py-3">
                    <div class="flex items-center gap-2">
                      <Avatar :name="p.display_name" :src="avatarMap[p.user_id]" :size="28" />
                      <RouterLink :to="'/player/' + p.id"
                        class="font-semibold hover:text-neon transition-colors"
                        :class="isMe(p) ? 'text-cyan-700' : 'text-slate-800'">
                        {{ p.display_name }}
                        <span v-if="isMe(p)" class="text-[10px] text-cyan-500 font-normal ml-1">you</span>
                      </RouterLink>
                    </div>
                  </td>
                  <td class="px-2 py-3 text-right text-xs font-semibold" :class="trendColor(p.elo)">{{ p.elo }}</td>
                  <td class="px-2 py-3 text-right text-xs text-slate-400">{{ p.win_pct }}%</td>
                  <td class="pl-2 pr-4 py-3 text-right text-xs text-slate-400">{{ p.days_played }}</td>
                </tr>
              </template>

              <!-- Collapsed hint -->
              <tr v-if="!showFull && rest.length">
                <td colspan="5" class="text-center py-3">
                  <button class="text-xs text-neon hover:opacity-75 transition" @click="showFull = true">
                    + {{ rest.length }} more players · Show all ↓
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- ── Best Pairs ────────────────────────────────────────────────── -->
      <div v-if="bestPairs.length" class="card overflow-hidden">
        <div class="px-4 py-3 border-b border-slate-100">
          <div class="text-xs font-bold text-slate-600">🏅 Best Pairs</div>
          <div class="text-[10px] text-slate-400 mt-0.5">Top duos by win % (min 1 game played together)</div>
        </div>
        <div v-for="(pair, i) in bestPairs" :key="pair.p1 + pair.p2"
          class="flex items-center gap-3 px-4 py-3 border-b border-slate-50 last:border-0">
          <span class="text-lg shrink-0 w-6 text-center font-bold text-slate-400"
            :class="i < 3 ? '' : 'text-sm'">{{ medals[i] ?? `#${i + 1}` }}</span>
          <div class="flex -space-x-2 shrink-0">
            <Avatar :name="pair.p1_name" :src="avatarMap[pair.p1_user_id]" :size="28" class="ring-2 ring-white" />
            <Avatar :name="pair.p2_name" :src="avatarMap[pair.p2_user_id]" :size="28" class="ring-2 ring-white" />
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold text-slate-700 truncate">{{ pair.p1_name }} + {{ pair.p2_name }}</p>
            <p class="text-xs text-slate-400 mt-0.5">
              {{ pair.games }} games · {{ pair.wins }}W / {{ pair.games - pair.wins }}L
            </p>
          </div>
          <div class="text-lg font-extrabold text-neon shrink-0">{{ pair.win_pct }}%</div>
        </div>
      </div>

      <!-- Compare link -->
      <RouterLink to="/compare"
        class="card w-full py-3 text-sm text-slate-400 hover:text-neon transition-all flex items-center justify-center gap-2">
        ⚔️ Head-to-Head Comparison →
      </RouterLink>

    </template>
  </div>
</template>

<style scoped>
/* ── Today's Heroes celebration ── */
.hero-card { animation: heroPop .5s cubic-bezier(.22,1,.36,1) both; }
@keyframes heroPop { from { opacity: 0; transform: translateY(8px) scale(.98); } to { opacity: 1; transform: none; } }

.hero-header {
  position: relative;
  overflow: hidden;
  background: linear-gradient(90deg, rgba(0,180,216,.12), rgba(168,85,247,.09), rgba(251,191,36,.13));
}
/* diagonal shine sweep */
.hero-header::after {
  content: '';
  position: absolute; inset: 0;
  background: linear-gradient(120deg, transparent 35%, rgba(255,255,255,.55) 50%, transparent 65%);
  transform: translateX(-120%);
  animation: heroShine 4.5s ease-in-out infinite;
}
@keyframes heroShine { 0% { transform: translateX(-120%); } 55%,100% { transform: translateX(120%); } }

/* confetti dots drifting down inside the header */
.confetti {
  position: absolute; top: -8px; width: 6px; height: 6px; border-radius: 1px;
  opacity: 0; animation: confettiFall 3.8s linear infinite;
}
.confetti.c1 { left: 12%; background: #00b4d8; animation-delay: 0s;   }
.confetti.c2 { left: 28%; background: #a855f7; animation-delay: .7s;  transform: rotate(20deg); }
.confetti.c3 { left: 44%; background: #f59e0b; animation-delay: 1.4s; }
.confetti.c4 { left: 60%; background: #10b981; animation-delay: 2.1s; transform: rotate(35deg); }
.confetti.c5 { left: 76%; background: #f43f5e; animation-delay: 1s;   }
.confetti.c6 { left: 90%; background: #00b4d8; animation-delay: 2.6s; transform: rotate(15deg); }
@keyframes confettiFall {
  0%   { opacity: 0; transform: translateY(-6px) rotate(0deg); }
  10%  { opacity: .9; }
  100% { opacity: 0; transform: translateY(46px) rotate(220deg); }
}

.hero-cell { position: relative; transition: background .15s; }
.hero-cell:hover { background: rgba(0,0,0,.02); }

.hero-avatar-wrap {
  position: relative;
  width: 46px; height: 46px;
  display: flex; align-items: center; justify-content: center;
}
.hero-glow {
  position: absolute; inset: -12px; border-radius: 9999px;
  background: radial-gradient(circle, var(--glow) 0%, transparent 68%);
  animation: heroPulse 2.4s ease-in-out infinite;
}
@keyframes heroPulse { 0%,100% { transform: scale(.8);  opacity: .5; } 50% { transform: scale(1.15); opacity: .95; } }

.hero-avatar {
  position: relative; z-index: 1;
  border-radius: 9999px;
  box-shadow: 0 0 0 2px #fff, 0 0 0 4px var(--accent);
}

.hero-crown {
  position: absolute; top: -15px; left: 50%; z-index: 3;
  font-size: 15px; transform: translateX(-50%) rotate(-12deg);
  animation: crownBob 2.2s ease-in-out infinite;
}
@keyframes crownBob {
  0%,100% { transform: translateX(-50%) rotate(-12deg) translateY(0); }
  50%     { transform: translateX(-50%) rotate(-7deg) translateY(-2px); }
}

.hero-spark { position: absolute; z-index: 2; font-size: 10px; opacity: 0; animation: twinkle 2.6s ease-in-out infinite; }
.hero-spark.s1 { top: -6px;  right: -8px; animation-delay: .2s; }
.hero-spark.s2 { bottom: -4px; left: -9px; animation-delay: 1s;  }
.hero-spark.s3 { top: 12px;  right: -13px; animation-delay: 1.7s; }
@keyframes twinkle { 0%,100% { opacity: 0; transform: scale(.5); } 50% { opacity: 1; transform: scale(1.1); } }

.hero-stat {
  margin-top: 6px;
  font-size: 11px; font-weight: 800; color: var(--accent);
  background: var(--soft);
  padding: 2px 9px; border-radius: 9999px;
}

@media (prefers-reduced-motion: reduce) {
  .hero-card, .hero-header::after, .confetti, .hero-glow, .hero-crown, .hero-spark { animation: none; }
  .confetti, .hero-spark { opacity: 0; }
  .hero-glow { opacity: .6; }
}
</style>
