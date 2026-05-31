<script setup>
import { ref, watch, onMounted, nextTick } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const router = useRouter()
const route  = useRoute()
const { currentClub, isManager } = useClub()

const matches   = ref([])
const loading   = ref(true)
const expanded  = ref(null)
const renaming  = ref(null)
const renameVal = ref('')
const deleting  = ref(null)   // match id currently being deleted

async function load() {
  if (!currentClub.value) return
  loading.value = true
  const { data } = await supabase
    .from('matches')
    .select(`
      id, played_on, created_at, display_name, match_number,
      match_sides(
        id, side, score, is_winner,
        match_participants(
          elo_before, elo_after,
          players(id, display_name)
        )
      )
    `)
    .eq('club_id', currentClub.value.club_id)
    .order('created_at', { ascending: false })
    .limit(100)

  matches.value = (data ?? []).map(m => {
    const sA = m.match_sides?.find(s => s.side === 'A')
    const sB = m.match_sides?.find(s => s.side === 'B')
    return {
      id: m.id,
      played_on: m.played_on,
      created_at: m.created_at,
      name: m.display_name ?? `Match #${m.match_number}`,
      match_number: m.match_number,
      sideA: {
        score: sA?.score ?? 0,
        winner: sA?.is_winner ?? false,
        players: (sA?.match_participants ?? []).map(mp => ({
          name: mp.players?.display_name,
          delta: mp.elo_after != null ? Math.round(mp.elo_after - mp.elo_before) : null,
          elo: mp.elo_after != null ? Math.round(mp.elo_after) : null,
        }))
      },
      sideB: {
        score: sB?.score ?? 0,
        winner: sB?.is_winner ?? false,
        players: (sB?.match_participants ?? []).map(mp => ({
          name: mp.players?.display_name,
          delta: mp.elo_after != null ? Math.round(mp.elo_after - mp.elo_before) : null,
          elo: mp.elo_after != null ? Math.round(mp.elo_after) : null,
        }))
      }
    }
  })
  loading.value = false
}
onMounted(async () => {
  await load()
  // Auto-expand match if arriving from a profile/deep-link
  const openId = route.query.open
  if (openId) {
    expanded.value = openId
    await nextTick()
    document.getElementById('match-' + openId)
      ?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }
})
watch(currentClub, load)

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

async function deleteMatch(m) {
  if (!confirm(`Delete "${m.name}"?\n\nAll player Elo ratings will be recalculated from scratch based on remaining matches.\n\nThis cannot be undone.`)) return
  deleting.value = m.id
  const { error } = await supabase.rpc('delete_match', { p_match_id: m.id })
  deleting.value = null
  if (error) { alert('Delete failed: ' + error.message); return }
  expanded.value = null
  await load()
}

const fmt = d => new Date(d).toLocaleDateString('en-AE', { day:'numeric', month:'short', year:'numeric' })
const deltaColor = d => d > 0 ? 'text-emerald-400' : d < 0 ? 'text-rose-400' : 'text-slate-500'
const deltaText  = d => d > 0 ? `+${d}` : `${d}`
</script>

<template>
  <!-- Back button when arriving via deep-link from a profile -->
  <button v-if="route.query.open"
    class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4 fade-up"
    @click="router.back()">
    ← Back to Profile
  </button>

  <!-- Add match button (managers) -->
  <div class="flex items-center justify-between mb-4 fade-up">
    <div>
      <h2 class="font-display text-xl font-bold gradient-text">Match History</h2>
      <p class="text-xs text-slate-400 mt-0.5">All matches · newest first</p>
    </div>
    <button v-if="isManager()" class="btn-primary px-4 py-2 text-sm"
      @click="router.push('/match')">
      ➕ Add Match
    </button>
  </div>

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

  <!-- Match list -->
  <div v-else class="space-y-2 fade-up">
    <div v-for="m in matches" :key="m.id"
      :id="'match-' + m.id"
      class="card overflow-hidden transition-all duration-200"
      :class="expanded === m.id ? 'card-neon' : 'hover:border-white/15'">

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
          <div class="text-[11px] text-slate-500 mt-0.5">{{ fmt(m.played_on) }}</div>
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
      <div v-if="expanded === m.id" class="border-t border-white/[0.06] px-4 py-3">
        <div class="grid grid-cols-2 gap-3">
          <!-- Side A -->
          <div :class="m.sideA.winner ? 'card-neon' : 'card'" class="p-3">
            <div class="text-[9px] uppercase tracking-widest mb-2 font-bold"
              :class="m.sideA.winner ? 'text-neon' : 'text-slate-500'">
              {{ m.sideA.winner ? '🏆 Winner' : 'Side A' }}
            </div>
            <div class="text-2xl font-extrabold mb-2"
              :class="m.sideA.winner ? 'text-neon' : 'text-slate-400'">
              {{ m.sideA.score }}
            </div>
            <div v-for="p in m.sideA.players" :key="p.name" class="flex justify-between items-center py-1">
              <span class="text-xs text-slate-200 truncate">{{ p.name }}</span>
              <span v-if="p.delta != null" class="text-[11px] font-semibold ml-2 shrink-0"
                :class="deltaColor(p.delta)">
                {{ deltaText(p.delta) }}
              </span>
            </div>
          </div>

          <!-- Side B -->
          <div :class="m.sideB.winner ? 'card-neon' : 'card'" class="p-3">
            <div class="text-[9px] uppercase tracking-widest mb-2 font-bold"
              :class="m.sideB.winner ? 'text-neon' : 'text-slate-500'">
              {{ m.sideB.winner ? '🏆 Winner' : 'Side B' }}
            </div>
            <div class="text-2xl font-extrabold mb-2"
              :class="m.sideB.winner ? 'text-neon' : 'text-slate-400'">
              {{ m.sideB.score }}
            </div>
            <div v-for="p in m.sideB.players" :key="p.name" class="flex justify-between items-center py-1">
              <span class="text-xs text-slate-200 truncate">{{ p.name }}</span>
              <span v-if="p.delta != null" class="text-[11px] font-semibold ml-2 shrink-0"
                :class="deltaColor(p.delta)">
                {{ deltaText(p.delta) }}
              </span>
            </div>
          </div>
        </div>

        <!-- Manager actions -->
        <div v-if="isManager() && renaming !== m.id" class="mt-2 flex justify-between items-center">
          <button class="text-[11px] text-slate-500 hover:text-neon transition px-2 py-1"
            @click="startRename(m)">✏️ Rename</button>
          <button class="text-[11px] text-rose-500/70 hover:text-rose-400 transition px-2 py-1 flex items-center gap-1"
            :disabled="deleting === m.id"
            @click="deleteMatch(m)">
            {{ deleting === m.id ? '⏳ Deleting…' : '🗑️ Delete match' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
