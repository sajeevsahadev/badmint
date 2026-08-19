<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue'
import { useRouter, useRoute, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import { useAuth } from '../composables/useAuth'
import PageHeader from '../components/PageHeader.vue'
import Avatar from '../components/Avatar.vue'

const router = useRouter()
const route  = useRoute()
const { currentClub, isManager } = useClub()
const { user } = useAuth()

const matches        = ref([])
const loading        = ref(true)
const activeLive     = ref(null)
const expanded       = ref(null)
const renaming       = ref(null)
const renameVal      = ref('')
const deleting       = ref(null)
const collapsedDates = ref(new Set())
const allExpanded    = ref(false)
const loadingMore    = ref(false)
const hasMore        = ref(false)
const PAGE_SIZE      = 30

// ── Lineup suggestion (available to all members) ──
const lineup         = ref(null)
const lineupLoading  = ref(false)
const lineupError    = ref(null)
const lineupSwapMode = ref(false)
const swapTarget     = ref(null)
const showLineup     = ref(false)

const todayStr = new Date().toISOString().slice(0, 10)

async function suggestLineup(shuffle = false) {
  if (!currentClub.value) return
  lineupLoading.value = true
  lineupError.value   = null
  lineup.value        = null
  lineupSwapMode.value = false
  const { data, error } = await supabase.rpc('suggest_lineup_by_date', {
    p_club_id: currentClub.value.club_id,
    p_date:    todayStr,
    p_shuffle: shuffle
  })
  lineupLoading.value = false
  if (error || data?.error) { lineupError.value = data?.error ?? error.message; return }
  lineup.value = data
}

function startSwap(side, index) {
  if (!isManager()) return
  lineupSwapMode.value = true
  swapTarget.value = { side, index }
}

function completeSwap(fromSide, fromIndex) {
  if (!swapTarget.value || !lineup.value) return
  const { side: toSide, index: toIndex } = swapTarget.value
  if (toSide === fromSide && toIndex === fromIndex) {
    lineupSwapMode.value = false; swapTarget.value = null; return
  }
  const la = [...lineup.value.side_a]
  const lb = [...lineup.value.side_b]
  const bench = [...(lineup.value.bench ?? [])]
  const get = (s, i) => s === 'a' ? la[i] : s === 'b' ? lb[i] : bench[i]
  const set = (s, i, p) => { if (s === 'a') la[i] = p; else if (s === 'b') lb[i] = p; else bench[i] = p }
  const pTo = get(toSide, toIndex); const pFrom = get(fromSide, fromIndex)
  set(toSide, toIndex, pFrom); set(fromSide, fromIndex, pTo)
  const eloSum = arr => arr.reduce((s, p) => s + (p?.elo ?? 0), 0)
  lineup.value = { ...lineup.value, side_a: la, side_b: lb, bench, elo_a: eloSum(la), elo_b: eloSum(lb) }
  lineupSwapMode.value = false; swapTarget.value = null
}

function acceptLineup() {
  if (!lineup.value) return
  const sideAIds = lineup.value.side_a.map(p => p.id).join(',')
  const sideBIds = lineup.value.side_b.map(p => p.id).join(',')
  router.push(`/match?sideA=${sideAIds}&sideB=${sideBIds}&date=${todayStr}`)
}

// Map one match from get_club_matches jsonb → the shape the template expects.
// Names + avatars come from the deduped players map (resolved server-side, no
// second round trip, avatar bytes sent once per player rather than per match).
function mapMatch(m, pmap) {
  const sA = m.sides?.find(s => s.side === 'A')
  const sB = m.sides?.find(s => s.side === 'B')
  const mapPlayers = arr => (arr ?? []).map(p => ({
    id: p.id,
    name: pmap[p.id]?.name ?? '—',
    user_id: pmap[p.id]?.user_id ?? null,
    avatar: pmap[p.id]?.avatar ?? null,
    delta: p.elo_after != null ? Math.round(p.elo_after - p.elo_before) : null,
    elo:   p.elo_after != null ? Math.round(p.elo_after) : null,
  }))
  return {
    id: m.id,
    played_on: m.played_on,
    created_at: m.created_at,
    created_by: m.created_by,
    name: m.display_name ?? `Match #${m.match_number}`,
    match_number: m.match_number,
    sideA: { score: sA?.score ?? 0, winner: sA?.is_winner ?? false, players: mapPlayers(sA?.players) },
    sideB: { score: sB?.score ?? 0, winner: sB?.is_winner ?? false, players: mapPlayers(sB?.players) },
  }
}

async function load() {
  if (!currentClub.value) return
  loading.value = true
  const { data } = await supabase.rpc('get_club_matches', {
    p_club_id: currentClub.value.club_id, p_limit: PAGE_SIZE, p_before: null,
  })
  const pmap = data?.players ?? {}
  const list = (data?.matches ?? []).map(m => mapMatch(m, pmap))
  matches.value = list
  hasMore.value = list.length === PAGE_SIZE
  // Collapse all dates by default — most recent date stays open
  const dates = [...new Set(list.map(m => m.played_on))]
  collapsedDates.value = new Set(dates.slice(1))
  allExpanded.value = false
  loading.value = false
}

// Lazy pagination — fetch older matches (keyset on created_at).
async function loadMore() {
  if (!currentClub.value || !hasMore.value || loadingMore.value) return
  loadingMore.value = true
  const oldest = matches.value[matches.value.length - 1]?.created_at
  const { data } = await supabase.rpc('get_club_matches', {
    p_club_id: currentClub.value.club_id, p_limit: PAGE_SIZE, p_before: oldest,
  })
  const pmap = data?.players ?? {}
  const list = (data?.matches ?? []).map(m => mapMatch(m, pmap))
  const existingCount = matches.value.length
  matches.value = [...matches.value, ...list]
  hasMore.value = list.length === PAGE_SIZE
  // Newly loaded dates start collapsed (except any already open)
  const existing = new Set(matches.value.slice(0, existingCount).map(m => m.played_on))
  const s = new Set(collapsedDates.value)
  for (const m of list) if (!existing.has(m.played_on)) s.add(m.played_on)
  collapsedDates.value = s
  loadingMore.value = false
}
async function checkActiveLive() {
  if (!currentClub.value) return
  const { data } = await supabase
    .from('live_matches')
    .select('id, score_a, score_b')
    .eq('club_id', currentClub.value.club_id)
    .eq('status', 'active')
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  activeLive.value = data ?? null
}

onMounted(async () => {
  await Promise.all([load(), checkActiveLive()])
  const openId = route.query.open
  if (openId) {
    // Deep-link: expand the date group containing the target match
    const targetDate = matches.value.find(m => m.id === openId)?.played_on
    if (targetDate) collapsedDates.value.delete(targetDate)
    expanded.value = openId
    await nextTick()
    document.getElementById('match-' + openId)
      ?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
})
watch(currentClub, async () => {
  await load()
  // Re-collapse all dates when club changes
  collapsedDates.value = new Set(groupedMatches.value.map(g => g.date))
  allExpanded.value = false
})

function toggleDate(date) {
  const s = new Set(collapsedDates.value)
  if (s.has(date)) s.delete(date)
  else s.add(date)
  collapsedDates.value = s
  allExpanded.value = s.size === 0
}

function toggleExpandAll() {
  if (allExpanded.value) {
    collapsedDates.value = new Set(groupedMatches.value.map(g => g.date))
    allExpanded.value = false
  } else {
    collapsedDates.value = new Set()
    allExpanded.value = true
  }
}

function toggle(id) {
  expanded.value = expanded.value === id ? null : id
  renaming.value = null
}

function startRename(m) {
  renaming.value = m.id
  renameVal.value = m.name
}

async function saveRename(m) {
  if (!renameVal.value.trim()) { renaming.value = null; return }
  const { error } = await supabase.rpc('rename_match', {
    p_match_id: m.id, p_name: renameVal.value.trim()
  })
  if (!error) m.name = renameVal.value.trim()
  renaming.value = null
}

// confirmDelete holds the match object pending user's Yes/No
const confirmDelete  = ref(null)
const deleteError    = ref(null)

function askDelete(m) {
  deleteError.value  = null
  confirmDelete.value = m
}

async function confirmDoDelete() {
  const m = confirmDelete.value
  if (!m) return
  confirmDelete.value = null
  deleting.value = m.id
  const { error } = await supabase.rpc('delete_match', { p_match_id: m.id })
  deleting.value = null
  if (error) { deleteError.value = error.message; return }
  expanded.value = null
  await load()
}

const fmt = d => new Date(d + 'T00:00:00').toLocaleDateString('en-AE', { weekday:'short', day:'numeric', month:'short', year:'numeric' })

// Group matches by played_on date (preserves order: newest date first)
const groupedMatches = computed(() => {
  const groups = []
  const seen = new Map()
  for (const m of matches.value) {
    if (!seen.has(m.played_on)) {
      const g = { date: m.played_on, matches: [] }
      groups.push(g)
      seen.set(m.played_on, g)
    }
    seen.get(m.played_on).matches.push(m)
  }
  return groups
})
const deltaColor = d => d > 0 ? 'text-emerald-400' : d < 0 ? 'text-rose-400' : 'text-slate-500'
const deltaText  = d => d > 0 ? `+${d}` : `${d}`

const canDelete = m =>
  m.created_by === user.value?.id || currentClub.value?.role === 'owner'
</script>

<template>
  <!-- Back button when arriving via deep-link from a profile -->
  <button v-if="route.query.open"
    class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4 fade-up"
    @click="router.back()">
    ← Back to Profile
  </button>

  <!-- Header row -->
  <div class="flex items-center justify-between mb-4 fade-up">
    <div>
      <h2 class="font-display text-xl font-bold gradient-text">Match History</h2>
      <p class="text-xs text-slate-400 mt-0.5">Grouped by date · newest first</p>
    </div>
    <div class="flex items-center gap-2">
      <button v-if="matches.length" class="btn-ghost px-3 py-1.5 text-xs font-semibold"
        @click="toggleExpandAll">
        {{ allExpanded ? '⊟ Collapse All' : '⊞ Expand All' }}
      </button>
      <button v-if="isManager()" class="btn-primary px-4 py-2 text-sm"
        @click="router.push('/match')">
        ➕ Add Match
      </button>
    </div>
  </div>

  <!-- ── Active live match banner ── -->
  <RouterLink v-if="activeLive" :to="`/live/${activeLive.id}`"
    class="card mb-4 flex items-center gap-3 px-4 py-3 fade-up no-underline hover:opacity-90 transition">
    <span class="relative flex h-3 w-3 shrink-0">
      <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
      <span class="relative inline-flex rounded-full h-3 w-3 bg-rose-500"></span>
    </span>
    <div class="flex-1 min-w-0">
      <span class="text-sm font-bold text-rose-600">Live Match in Progress</span>
      <span class="ml-2 text-sm text-slate-500">{{ activeLive.score_a }} – {{ activeLive.score_b }}</span>
    </div>
    <span class="text-xs text-neon font-semibold shrink-0">Open →</span>
  </RouterLink>

  <!-- ── Suggested Next Match card ── -->
  <div class="card overflow-hidden mb-4 fade-up">
    <button class="w-full px-4 py-3 flex items-center justify-between" @click="showLineup = !showLineup">
      <div class="flex items-center gap-2">
        <span class="text-base">🤖</span>
        <div class="text-left">
          <div class="text-sm font-bold text-slate-800">Suggested Next Match</div>
          <div class="text-[10px] text-slate-500">Balanced teams · today's attendees</div>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <!-- Generate only appears before a lineup exists; once teams are shown,
             reshuffling lives solely on the "Reshuffle" button below. -->
        <button v-if="!lineup" class="btn-ghost text-xs px-3 py-1.5" :disabled="lineupLoading"
          @click.stop="suggestLineup(false); showLineup = true">
          {{ lineupLoading ? '…' : '✨ Generate' }}
        </button>
        <span class="text-slate-400 text-xs transition-transform duration-200"
          :style="showLineup ? 'transform:rotate(180deg)' : ''">▾</span>
      </div>
    </button>

    <div v-if="showLineup" class="border-t border-[rgba(15,23,42,0.06)] px-4 py-3 space-y-3">

      <div v-if="lineupError" class="text-xs text-rose-400">⚠️ {{ lineupError }}</div>

      <div v-if="!lineup && !lineupError" class="text-[11px] text-slate-500 text-center py-2">
        Tap ✨ Generate to suggest balanced teams from today's attendees.
      </div>

      <template v-if="lineup">
        <div v-if="lineup.rotated"
          class="text-[10px] text-amber-600 rounded-lg px-3 py-1.5"
          style="background:rgba(251,191,36,.1); border:1px solid rgba(251,191,36,.2)">
          🔄 Players from last match rotated to bench
        </div>
        <div v-if="lineup.used_schedule"
          class="text-[10px] text-neon rounded-lg px-3 py-1.5"
          style="background:rgba(0,180,216,.08); border:1px solid rgba(0,180,216,.2)">
          📅 Using today's saved attendance list
        </div>

        <div class="grid grid-cols-2 gap-2">
          <div class="rounded-xl p-3" style="background:rgba(0,180,216,.08); border:1px solid rgba(0,180,216,.2)">
            <div class="text-[10px] font-bold text-neon uppercase tracking-wider mb-2">Side A · {{ lineup.elo_a }}</div>
            <div v-for="(p, i) in lineup.side_a" :key="p.id"
              class="flex items-center justify-between py-1 rounded px-1 transition cursor-pointer"
              :class="lineupSwapMode && swapTarget?.side==='a' && swapTarget?.index===i ? 'bg-cyan-100' : lineupSwapMode ? 'hover:bg-cyan-50' : ''"
              @click="lineupSwapMode ? completeSwap('a', i) : startSwap('a', i)">
              <div class="flex items-center gap-1.5 min-w-0">
                <div class="w-5 h-5 rounded-full bg-cyan-500/20 flex items-center justify-center text-[9px] font-bold text-neon shrink-0">{{ p.name?.[0]?.toUpperCase() }}</div>
                <span class="text-xs text-slate-800 truncate font-medium">{{ p.name }}</span>
              </div>
              <span class="text-[10px] text-slate-500 shrink-0">{{ p.elo }}</span>
            </div>
          </div>

          <div class="rounded-xl p-3" style="background:rgba(168,85,247,.08); border:1px solid rgba(168,85,247,.2)">
            <div class="text-[10px] font-bold text-violet uppercase tracking-wider mb-2">Side B · {{ lineup.elo_b }}</div>
            <div v-for="(p, i) in lineup.side_b" :key="p.id"
              class="flex items-center justify-between py-1 rounded px-1 transition cursor-pointer"
              :class="lineupSwapMode && swapTarget?.side==='b' && swapTarget?.index===i ? 'bg-violet-100' : lineupSwapMode ? 'hover:bg-violet-50' : ''"
              @click="lineupSwapMode ? completeSwap('b', i) : startSwap('b', i)">
              <div class="flex items-center gap-1.5 min-w-0">
                <div class="w-5 h-5 rounded-full bg-violet-500/20 flex items-center justify-center text-[9px] font-bold text-violet shrink-0">{{ p.name?.[0]?.toUpperCase() }}</div>
                <span class="text-xs text-slate-800 truncate font-medium">{{ p.name }}</span>
              </div>
              <span class="text-[10px] text-slate-500 shrink-0">{{ p.elo }}</span>
            </div>
          </div>
        </div>

        <!-- Elo balance bar -->
        <div>
          <div class="flex justify-between text-[10px] mb-1">
            <span class="text-neon font-semibold">A {{ lineup.elo_a }}</span>
            <span class="text-slate-400">Δ{{ Math.abs(lineup.elo_a - lineup.elo_b) }} gap</span>
            <span class="text-violet font-semibold">{{ lineup.elo_b }} B</span>
          </div>
          <div class="h-1.5 rounded-full overflow-hidden flex" style="background:rgba(0,0,0,.06)">
            <div class="h-full bg-cyan-400 rounded-l-full transition-all duration-500"
              :style="`width:${Math.round(lineup.elo_a/(lineup.elo_a+lineup.elo_b)*100)}%`"/>
            <div class="h-full bg-violet-400 rounded-r-full flex-1"/>
          </div>
        </div>

        <!-- Bench -->
        <div v-if="lineup.bench?.length">
          <div class="text-[10px] text-slate-500 mb-1.5 uppercase tracking-wide">Bench</div>
          <div class="flex flex-wrap gap-1.5">
            <div v-for="(p, i) in lineup.bench" :key="p.id"
              class="flex items-center gap-1 rounded-lg px-2 py-1 text-[11px] text-slate-600 transition"
              style="background:rgba(0,0,0,.05); border:1px solid rgba(0,0,0,.07)"
              :class="lineupSwapMode ? 'cursor-pointer hover:border-cyan-300' : ''"
              @click="lineupSwapMode ? completeSwap('bench', i) : null">
              {{ p.name }} <span class="text-slate-400 text-[10px]">{{ p.elo }}</span>
            </div>
          </div>
        </div>

        <div v-if="lineupSwapMode" class="text-[10px] text-amber-600 text-center rounded-lg py-1.5 px-3"
          style="background:rgba(251,191,36,.08); border:1px solid rgba(251,191,36,.2)">
          Tap the player to swap with ·
          <button class="underline" @click="lineupSwapMode = false; swapTarget = null">Cancel</button>
        </div>

        <div class="flex gap-2 pt-1">
          <button class="btn-ghost flex-1 text-xs py-2.5" :disabled="lineupLoading" @click="suggestLineup(true)">🔄 Reshuffle</button>
          <button v-if="isManager()" class="btn-primary flex-1 text-xs py-2.5" @click="acceptLineup">
            ✅ Start This Match
          </button>
          <div v-else class="flex-1 text-center text-[11px] text-slate-500 py-2.5 rounded-xl"
            style="background:rgba(0,0,0,.04); border:1px solid rgba(0,0,0,.06)">
            Ask manager to start
          </div>
        </div>
      </template>
    </div>
  </div>
  <!-- ── End Suggested Next Match ── -->

  <!-- Loading -->
  <div v-if="loading" class="space-y-2">
    <div v-for="i in 5" :key="i" class="h-16 shimmer rounded-2xl" />
  </div>

  <!-- Empty -->
  <div v-else-if="!matches.length" class="card-neon p-10 text-center fade-up">
    <div class="text-4xl mb-4">🏸</div>
    <p class="font-bold gradient-text text-lg mb-2">No matches yet</p>
    <p class="text-slate-400 text-sm mb-5">Record your first match to see history here.</p>
    <button v-if="isManager()" class="btn-primary px-6" @click="router.push('/match')">
      ➕ Record First Match
    </button>
  </div>

  <!-- Match list grouped by date -->
  <div v-else class="fade-up">
    <div v-for="group in groupedMatches" :key="group.date" class="mb-4">

      <!-- Date header — clickable to collapse/expand -->
      <button class="w-full flex items-center gap-2 mb-2 group" @click="toggleDate(group.date)">
        <span class="text-xs font-bold text-slate-300 group-hover:text-neon transition-colors">
          {{ fmt(group.date) }}
        </span>
        <span class="text-xs px-2 py-0.5 rounded-full text-slate-500 font-medium"
          style="background:rgba(255,255,255,.06)">
          {{ group.matches.length }} {{ group.matches.length === 1 ? 'match' : 'matches' }}
        </span>
        <div class="flex-1 h-px" style="background:rgba(255,255,255,.06)"></div>
        <span class="text-slate-500 text-xs transition-transform duration-200 group-hover:text-neon"
          :style="collapsedDates.has(group.date) ? '' : 'transform:rotate(180deg)'">▾</span>
      </button>

      <!-- Matches for this date (hidden when collapsed) -->
      <div v-if="!collapsedDates.has(group.date)" class="space-y-2">
      <div v-for="m in group.matches" :key="m.id"
        :id="'match-' + m.id"
        class="card overflow-hidden transition-all duration-200"
        :class="expanded === m.id ? 'card-neon' : 'hover:border-[rgba(15,23,42,0.15)]'">

      <!-- Summary row -->
      <button class="w-full px-4 py-3 flex items-center gap-3 text-left" @click="toggle(m.id)">
        <!-- Match # -->
        <div class="shrink-0 w-10 h-10 rounded-xl flex items-center justify-center text-xs font-black text-slate-950"
          style="background:linear-gradient(135deg,#00e5ff,#0099cc)">
          #{{ m.match_number ?? '?' }}
        </div>

        <!-- Score -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <!-- Rename input or name -->
            <template v-if="renaming === m.id" @click.stop>
              <input v-model="renameVal" class="input py-0.5 text-sm w-32"
                @keyup.enter="saveRename(m)" @keyup.escape="renaming = null"
                @click.stop />
              <button class="text-neon text-xs" @click.stop="saveRename(m)">Save</button>
            </template>
            <span v-else class="text-sm font-semibold text-slate-200 truncate">{{ m.name }}</span>
          </div>
          <div class="text-xs text-slate-500 mt-0.5">{{ fmt(m.played_on) }}</div>
        </div>

        <!-- Scores -->
        <div class="shrink-0 flex items-center gap-2 text-sm font-extrabold">
          <span :class="m.sideA.winner ? 'text-neon' : 'text-slate-400'">{{ m.sideA.score }}</span>
          <span class="text-slate-600 text-xs font-normal">–</span>
          <span :class="m.sideB.winner ? 'text-neon' : 'text-slate-400'">{{ m.sideB.score }}</span>
        </div>

        <!-- Chevron -->
        <div class="shrink-0 text-slate-600 transition-transform duration-200"
          :style="expanded === m.id ? 'transform:rotate(180deg)' : ''">▾</div>
      </button>

      <!-- Expanded detail -->
      <div v-if="expanded === m.id" class="border-t border-[rgba(15,23,42,0.06)] px-4 py-3">
        <div class="grid grid-cols-2 gap-3">
          <!-- Side A -->
          <div :class="m.sideA.winner ? 'card-neon' : 'card'" class="p-3">
            <div class="text-xs uppercase tracking-widest mb-2 font-bold"
              :class="m.sideA.winner ? 'text-neon' : 'text-slate-500'">
              {{ m.sideA.winner ? '🏆 Winner' : 'Side A' }}
            </div>
            <div class="text-2xl font-extrabold mb-2"
              :class="m.sideA.winner ? 'text-neon' : 'text-slate-400'">
              {{ m.sideA.score }}
            </div>
            <div v-for="p in m.sideA.players" :key="p.id ?? p.name" class="flex justify-between items-center py-1">
              <div class="flex items-center gap-2 min-w-0">
                <Avatar :name="p.name" :src="p.avatar" :size="24" />
                <RouterLink v-if="p.id" :to="'/player/' + p.id"
                  class="text-xs text-slate-200 truncate hover:text-neon transition-colors">{{ p.name }}</RouterLink>
                <span v-else class="text-xs text-slate-200 truncate">{{ p.name }}</span>
              </div>
              <span v-if="p.delta != null" class="text-xs font-semibold ml-2 shrink-0"
                :class="deltaColor(p.delta)">
                {{ deltaText(p.delta) }}
              </span>
            </div>
          </div>

          <!-- Side B -->
          <div :class="m.sideB.winner ? 'card-neon' : 'card'" class="p-3">
            <div class="text-xs uppercase tracking-widest mb-2 font-bold"
              :class="m.sideB.winner ? 'text-neon' : 'text-slate-500'">
              {{ m.sideB.winner ? '🏆 Winner' : 'Side B' }}
            </div>
            <div class="text-2xl font-extrabold mb-2"
              :class="m.sideB.winner ? 'text-neon' : 'text-slate-400'">
              {{ m.sideB.score }}
            </div>
            <div v-for="p in m.sideB.players" :key="p.id ?? p.name" class="flex justify-between items-center py-1">
              <div class="flex items-center gap-2 min-w-0">
                <Avatar :name="p.name" :src="p.avatar" :size="24" />
                <RouterLink v-if="p.id" :to="'/player/' + p.id"
                  class="text-xs text-slate-200 truncate hover:text-neon transition-colors">{{ p.name }}</RouterLink>
                <span v-else class="text-xs text-slate-200 truncate">{{ p.name }}</span>
              </div>
              <span v-if="p.delta != null" class="text-xs font-semibold ml-2 shrink-0"
                :class="deltaColor(p.delta)">
                {{ deltaText(p.delta) }}
              </span>
            </div>
          </div>
        </div>

        <!-- Match actions -->
        <div v-if="(isManager() || canDelete(m)) && renaming !== m.id" class="mt-2">
          <p v-if="deleteError && deleting !== m.id" class="text-xs text-rose-400 mb-1.5 px-2">
            ⚠️ {{ deleteError }}
          </p>
          <div class="flex justify-between items-center">
            <button v-if="isManager()" class="text-xs text-slate-500 hover:text-neon transition px-2 py-1"
              @click="startRename(m)">✏️ Rename</button>
            <div v-else />
            <button v-if="canDelete(m)"
              class="text-xs text-rose-500/70 hover:text-rose-400 transition px-2 py-1 flex items-center gap-1"
              :disabled="deleting === m.id"
              @click="askDelete(m)">
              {{ deleting === m.id ? '⏳ Deleting…' : '🗑️ Delete match' }}
            </button>
          </div>
        </div>
      </div><!-- closes expanded detail -->
      </div><!-- closes match card -->
      </div><!-- end space-y-2 -->
    </div><!-- end date group -->

    <!-- Lazy pagination — older matches load on demand -->
    <button v-if="hasMore" class="w-full card py-3 text-sm font-semibold text-neon hover:opacity-80 transition"
      :disabled="loadingMore" @click="loadMore">
      {{ loadingMore ? 'Loading…' : '↓ Load older matches' }}
    </button>
  </div><!-- end grouped list -->

  <!-- ── Delete confirmation modal ── -->
  <Teleport to="body">
    <div v-if="confirmDelete"
      class="fixed inset-0 z-50 flex items-center justify-center px-5"
      style="background:rgba(0,0,0,.7); backdrop-filter:blur(6px)"
      @click.self="confirmDelete = null">

      <div class="w-full max-w-sm rounded-2xl p-6"
        style="background:#0d1a2e; border:1px solid rgba(244,63,94,.25);
               box-shadow:0 0 40px rgba(244,63,94,.12);">

        <!-- Icon -->
        <div class="text-center mb-4">
          <div class="inline-flex w-14 h-14 rounded-2xl items-center justify-center text-3xl mb-3"
            style="background:rgba(244,63,94,.12); border:1px solid rgba(244,63,94,.25)">
            🗑️
          </div>
          <h3 class="font-display text-lg font-bold text-slate-100">Delete Match?</h3>
          <p class="text-sm text-slate-400 mt-1 truncate">{{ confirmDelete.name }}</p>
        </div>

        <!-- Warning -->
        <div class="rounded-xl p-3.5 mb-5 text-xs text-amber-300 leading-relaxed"
          style="background:rgba(251,191,36,.08); border:1px solid rgba(251,191,36,.2)">
          ⚠️ If deleted, the Elo rankings for all players in this club will be
          <strong class="text-amber-200">recalculated from scratch</strong> based on the
          remaining matches — as if this match never happened.
        </div>

        <!-- Buttons -->
        <div class="flex gap-3">
          <button class="flex-1 py-3 rounded-xl text-sm font-semibold text-slate-300
                         border border-white/10 hover:border-white/25 hover:text-white
                         transition-all duration-150"
            @click="confirmDelete = null">
            No, Keep It
          </button>
          <button class="flex-1 py-3 rounded-xl text-sm font-bold text-white
                         transition-all duration-150 active:scale-[0.97]"
            style="background:rgba(220,38,38,.85); border:1px solid rgba(244,63,94,.4)"
            @click="confirmDoDelete">
            Yes, Delete
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
