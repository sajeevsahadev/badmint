<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../lib/supabase'
import { buildNameMap } from '../lib/playerNames'
import { useAuth } from '../composables/useAuth'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()

const playerId = route.params.id

const player      = ref(null)
const profile     = ref(null)
const stats       = ref(null)
const matches     = ref([])
const clubName    = ref('')
const emirates    = ref('')
const loading     = ref(true)
const matchLimit  = ref(10)
const loadingMore = ref(false)

const isOwnProfile = computed(() =>
  user.value && player.value?.user_id === user.value.id
)

const publicName = computed(() =>
  profile.value?.nickname || player.value?.display_name || '—'
)

const initials = computed(() => {
  const n = publicName.value
  return n.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
})

async function load() {
  loading.value = true

  // 1. Player base row
  const { data: p } = await supabase
    .from('players')
    .select('id, display_name, elo, club_id, user_id')
    .eq('id', playerId)
    .single()
  player.value = p

  if (!p) { loading.value = false; return }

  // 2. Public profile (nickname + bio only — deliberately no phone/email)
  const [profRes, statsRes, clubRes, matchRes] = await Promise.all([
    p.user_id
      ? supabase.from('user_profiles')
          .select('nickname, bio, emirate, avatar_url')   // ← phone & email intentionally omitted
          .eq('user_id', p.user_id)
          .maybeSingle()
      : { data: null },

    supabase.from('v_leaderboard')
      .select('elo, club_rank, games, wins, win_pct, days_played, composite')
      .eq('id', playerId)
      .maybeSingle(),

    supabase.from('clubs')
      .select('name, emirates')
      .eq('id', p.club_id)
      .single(),

    supabase.from('matches')
      .select(`
        id, played_on, display_name, match_number,
        match_sides(
          side, score, is_winner,
          match_participants(
            elo_before, elo_after,
            players(id, display_name)
          )
        )
      `)
      .eq('club_id', p.club_id)
      .order('created_at', { ascending: false })
      .limit(matchLimit.value)
  ])

  profile.value  = profRes.data
  stats.value    = statsRes.data
  clubName.value = clubRes.data?.name ?? ''
  emirates.value = profRes.data?.emirate ?? clubRes.data?.emirates ?? ''

  // Collect all participant IDs for nickname resolution
  const allParticipantIds = [...new Set(
    (matchRes.data ?? []).flatMap(m =>
      (m.match_sides ?? []).flatMap(s =>
        (s.match_participants ?? []).map(mp => mp.players?.id)
      )
    ).filter(Boolean)
  )]
  const nameMap = await buildNameMap(allParticipantIds)

  // Filter matches that include this player
  matches.value = (matchRes.data ?? [])
    .filter(m => m.match_sides?.some(s =>
      s.match_participants?.some(mp => mp.players?.id === playerId)
    ))
    .map(m => {
      const sideA = m.match_sides?.find(s => s.side === 'A')
      const sideB = m.match_sides?.find(s => s.side === 'B')
      const playerInA = sideA?.match_participants?.some(mp => mp.players?.id === playerId)
      const mySide = playerInA ? sideA : sideB
      const oppSide = playerInA ? sideB : sideA
      return {
        id: m.id,
        date: m.played_on,
        name: m.display_name ?? `Match #${m.match_number}`,
        won: mySide?.is_winner ?? false,
        myScore:  mySide?.score  ?? 0,
        oppScore: oppSide?.score ?? 0,
        myTeam:  (mySide?.match_participants ?? []).map(mp => nameMap[mp.players?.id] || mp.players?.display_name).filter(Boolean),
        oppTeam: (oppSide?.match_participants ?? []).map(mp => nameMap[mp.players?.id] || mp.players?.display_name).filter(Boolean),
        eloDelta: (() => {
          const mp = mySide?.match_participants?.find(p => p.players?.id === playerId)
          return mp?.elo_after != null ? Math.round(mp.elo_after - mp.elo_before) : null
        })()
      }
    })

  loading.value = false
}

onMounted(load)

async function loadMore() {
  loadingMore.value = true
  matchLimit.value += 20
  await load()
  loadingMore.value = false
}

const fmt = d => new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short' })
const deltaColor = d => d > 0 ? 'text-emerald-400' : d < 0 ? 'text-rose-400' : 'text-slate-500'
const deltaText  = d => d > 0 ? `+${d}` : `${d}`
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <div v-else-if="!player" class="card p-8 text-center text-slate-400">
    <div class="text-3xl mb-3">❓</div>
    <p class="font-semibold mb-2">Player not found</p>
    <button class="btn-ghost px-6 text-sm" @click="router.back()">← Go Back</button>
  </div>

  <template v-else>

    <!-- Back button -->
    <button class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4 fade-up"
      @click="router.back()">
      ← Back
    </button>

    <!-- Header card -->
    <div class="card-neon p-5 mb-4 fade-up">
      <div class="flex items-center gap-4">
        <!-- Avatar -->
        <div class="w-16 h-16 rounded-2xl flex items-center justify-center text-xl font-black text-slate-950 shrink-0"
          style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
          {{ initials }}
        </div>

        <div class="flex-1 min-w-0">
          <h2 class="font-display text-xl font-extrabold gradient-text leading-tight truncate">
            {{ publicName }}
          </h2>
          <!-- Club + emirate -->
          <div class="flex items-center gap-2 mt-1 flex-wrap">
            <span class="text-xs text-slate-300">{{ clubName }}</span>
            <span v-if="emirates" class="badge-member text-[9px]">{{ emirates }}</span>
          </div>
          <!-- Bio -->
          <p v-if="profile?.bio" class="text-xs text-slate-400 mt-1.5 italic">{{ profile.bio }}</p>
        </div>
      </div>

      <!-- Own profile edit link -->
      <RouterLink v-if="isOwnProfile" to="/profile"
        class="mt-3 block text-center text-xs text-neon hover:opacity-80 transition border border-cyan-500/25 rounded-xl py-2">
        ✏️ Edit My Profile
      </RouterLink>
    </div>

    <!-- Stats row -->
    <div v-if="stats" class="grid grid-cols-4 gap-2 mb-4 fade-up">
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-gold">#{{ stats.club_rank }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Rank</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-neon">{{ stats.elo }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Elo</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-slate-200">{{ stats.games }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Games</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-violet">{{ stats.win_pct }}%</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Win%</div>
      </div>
    </div>

    <!-- Match history -->
    <div class="card overflow-hidden fade-up">
      <div class="px-4 py-3 border-b border-white/[0.06]">
        <span class="text-xs font-bold text-slate-200">Recent Matches</span>
        <span class="text-[10px] text-slate-600 ml-2">(last {{ matches.length }})</span>
      </div>

      <div v-if="!matches.length" class="px-4 py-6 text-center text-sm text-slate-500">
        No matches recorded yet.
      </div>

      <button v-for="m in matches" :key="m.id"
        class="w-full text-left px-4 py-3 border-b border-white/[0.04] last:border-0
               hover:bg-white/[0.03] transition-colors duration-150 group"
        @click="router.push('/matches?open=' + m.id)">
        <div class="flex items-center justify-between mb-1">
          <span class="text-xs text-slate-500">{{ fmt(m.date) }} · {{ m.name }}</span>
          <div class="flex items-center gap-2">
            <span class="text-xs font-bold"
              :class="m.won ? 'text-neon' : 'text-rose-400'">
              {{ m.won ? '🏆 Won' : 'Lost' }}
            </span>
            <span v-if="m.eloDelta != null" class="text-[11px] font-semibold"
              :class="deltaColor(m.eloDelta)">
              {{ deltaText(m.eloDelta) }}
            </span>
            <span class="text-slate-700 group-hover:text-slate-400 transition text-xs">›</span>
          </div>
        </div>
        <div class="text-xs text-slate-400">
          <span class="text-slate-200 font-medium">{{ m.myTeam.join(' + ') }}</span>
          <span class="mx-1.5 text-slate-600">{{ m.myScore }}–{{ m.oppScore }}</span>
          <span>{{ m.oppTeam.join(' + ') }}</span>
        </div>
      </button>
      <!-- Load more -->
      <div v-if="matches.length === matchLimit" class="px-4 py-3 border-t border-white/[0.05]">
        <button class="btn-ghost w-full text-sm" :disabled="loadingMore" @click="loadMore">
          {{ loadingMore ? 'Loading…' : 'Load More Matches' }}
        </button>
      </div>
    </div>

  </template>
</template>
