<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const route  = useRoute()
const router = useRouter()
const { user } = useAuth()
const { clubs } = useClub()

const clubId  = route.params.id
const club    = ref(null)
const ranking = ref(null)
const members = ref([])
const loading = ref(true)

const isMyClub = computed(() => clubs.value.some(c => c.club_id === clubId))
const myRole   = computed(() => clubs.value.find(c => c.club_id === clubId)?.role)
const isManager = computed(() => ['owner','manager'].includes(myRole.value))

async function load() {
  loading.value = true
  const [clubRes, rankRes, memberRes] = await Promise.all([
    supabase.from('clubs')
      .select('id, name, emirates, facility_name, facility_address, maps_url, description, created_at')
      .eq('id', clubId).single(),

    supabase.rpc('get_public_clubs'),

    supabase.rpc('get_club_players', { p_club_id: clubId })
  ])

  club.value    = clubRes.data
  members.value = memberRes.data ?? []

  // Find this club's ranking from the public list
  ranking.value = (rankRes.data ?? []).find(c => c.id === clubId) ?? null
  loading.value = false
}

onMounted(load)

const initials = name => (name ?? '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
const onlineColor = s => s === 'online' ? '#10b981' : s === 'recent' ? '#f59e0b' : '#475569'
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 4" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <div v-else-if="!club" class="card p-8 text-center text-slate-400">
    <p class="font-semibold mb-2">Club not found</p>
    <button class="btn-ghost px-6 text-sm mt-2" @click="router.back()">← Back</button>
  </div>

  <template v-else>
    <!-- Back -->
    <button class="flex items-center gap-1.5 text-xs text-slate-500 hover:text-neon transition mb-4"
      @click="router.back()">
      ← Back
    </button>

    <!-- Club header -->
    <div class="card-neon p-5 mb-4 fade-up">
      <div class="flex items-start gap-4">
        <!-- Club avatar -->
        <div class="w-16 h-16 rounded-2xl flex items-center justify-center text-xl font-black text-slate-950 shrink-0"
          style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
          {{ initials(club.name) }}
        </div>
        <div class="flex-1 min-w-0">
          <h2 class="font-display text-xl font-extrabold gradient-text leading-tight">{{ club.name }}</h2>
          <div class="flex flex-wrap gap-1.5 mt-1">
            <span v-if="club.emirates" class="badge-member text-[9px]">{{ club.emirates }}</span>
            <span v-if="isMyClub" class="badge-approved text-[9px]">{{ myRole }}</span>
          </div>
          <p v-if="club.description" class="text-xs text-slate-400 mt-2 leading-relaxed">{{ club.description }}</p>
        </div>
      </div>

      <!-- Manage button (for managers) -->
      <RouterLink v-if="isManager" to="/manage"
        class="mt-3 block text-center text-xs text-neon border border-cyan-500/25 rounded-xl py-2 hover:opacity-80 transition">
        ⚙️ Manage This Club
      </RouterLink>
    </div>

    <!-- Club score stats -->
    <div v-if="ranking" class="grid grid-cols-4 gap-2 mb-4 fade-up">
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-gold">#{{ ranking.club_rank }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Rank</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-neon">{{ ranking.club_score }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Score</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-slate-200">{{ ranking.total_members }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Members</div>
      </div>
      <div class="card p-3 text-center">
        <div class="text-lg font-extrabold text-violet">{{ ranking.matches_30d }}</div>
        <div class="text-[9px] text-slate-600 uppercase tracking-wider mt-0.5">Matches/mo</div>
      </div>
    </div>

    <!-- Facility info -->
    <div v-if="club.facility_name || club.facility_address || club.maps_url"
      class="card p-4 mb-4 fade-up">
      <div class="label">📍 Facility</div>
      <div v-if="club.facility_name" class="text-sm font-semibold text-slate-200 mb-0.5">{{ club.facility_name }}</div>
      <div v-if="club.facility_address" class="text-xs text-slate-400 mb-2">{{ club.facility_address }}</div>
      <a v-if="club.maps_url" :href="club.maps_url" target="_blank" rel="noopener"
        class="inline-flex items-center gap-1.5 text-xs text-neon hover:opacity-80 transition border border-cyan-500/20 rounded-lg px-3 py-1.5">
        🗺️ Open in Google Maps
      </a>
    </div>

    <!-- Members list -->
    <div class="card overflow-hidden fade-up">
      <div class="px-4 py-3 border-b border-white/[0.06] flex items-center justify-between">
        <span class="text-xs font-bold text-slate-200">
          Members ({{ members.filter(m => m.is_active).length }} active)
        </span>
        <RouterLink v-if="isManager" to="/players"
          class="text-xs text-neon hover:opacity-80 transition">
          + Add Member
        </RouterLink>
      </div>

      <div v-if="!members.length" class="px-4 py-6 text-center text-sm text-slate-500">
        No players yet.
      </div>

      <RouterLink v-for="(m, i) in members" :key="m.id" :to="'/player/' + m.id"
        class="flex items-center gap-3 px-4 py-3 border-b border-white/[0.04] last:border-0
               hover:bg-white/[0.02] transition-colors"
        :class="m.is_active ? '' : 'opacity-40'">

        <!-- Avatar with online dot -->
        <div class="relative shrink-0">
          <div class="w-9 h-9 rounded-xl flex items-center justify-center text-xs font-black text-slate-950"
            :style="m.is_active && i < 3
              ? 'background:linear-gradient(135deg,#00e5ff,#0099cc)'
              : 'background:rgba(255,255,255,0.08); color:#94a3b8'">
            {{ initials(m.display_name) }}
          </div>
          <!-- Online dot -->
          <span v-if="m.user_id && m.is_active" class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border border-slate-900"
            :style="'background:' + onlineColor(m.online_status)" />
        </div>

        <!-- Info -->
        <div class="flex-1 min-w-0">
          <div class="text-sm font-semibold text-slate-100 truncate">{{ m.display_name }}</div>
          <div class="text-[10px] text-slate-500">Elo {{ Math.round(m.elo) }}</div>
        </div>

        <!-- Inactive badge -->
        <span v-if="!m.is_active"
          class="text-[9px] text-slate-600 border border-slate-700 rounded-full px-1.5 py-0.5 shrink-0">
          Inactive
        </span>
        <span v-else class="text-slate-700 text-xs shrink-0">›</span>
      </RouterLink>
    </div>

  </template>
</template>
