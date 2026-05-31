<script setup>
import { ref, watch, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useClub } from '../composables/useClub'
import PageHeader from '../components/PageHeader.vue'

const { currentClub, isManager } = useClub()
const players = ref([])
const newName = ref('')
const busy    = ref(false)
const msg     = ref(null)

async function load() {
  if (!currentClub.value) return
  const { data } = await supabase.from('players')
    .select('id, display_name, elo, created_at').eq('club_id', currentClub.value.club_id)
    .order('elo', { ascending: false })
  players.value = data ?? []
}
onMounted(load)
watch(currentClub, load)

async function add() {
  if (!newName.value.trim()) return
  busy.value = true; msg.value = null
  const { error } = await supabase.from('players').insert({
    club_id: currentClub.value.club_id,
    display_name: newName.value.trim()
  })
  busy.value = false
  if (error) { msg.value = error.message; return }
  newName.value = ''; load()
}

async function remove(id, name) {
  if (!confirm(`Remove "${name}" from the roster?\n\nTheir match history and stats will be preserved.`)) return
  await supabase.from('players').delete().eq('id', id)
  load()
}

const eloColor = elo => elo >= 1100 ? 'text-teal-400' : elo <= 900 ? 'text-rose-400' : 'text-slate-300'
const eloLabel = elo => elo >= 1100 ? 'Strong' : elo >= 1000 ? 'Average' : 'Developing'
</script>

<template>
  <PageHeader icon="👥" title="Players" subtitle="Your club's roster — add members before recording matches">
    <template #help>
      <div class="text-xs space-y-1.5">
        <p><strong class="text-white">Add players</strong> before recording any match. Each player needs to be in the roster.</p>
        <p><strong class="text-white">Guest players</strong> (without Google login) are fully supported — just add their name here. They can claim their account later by logging in.</p>
        <p><strong class="text-white">Elo rating</strong> starts at 1,000 for everyone. It updates automatically after each match they play in.</p>
        <p><strong class="text-white">Removing a player</strong> removes them from the roster but keeps all their match history and stats intact.</p>
      </div>
    </template>
  </PageHeader>

  <!-- Add form (managers only) -->
  <div v-if="isManager()" class="card mb-4 p-4">
    <div class="label">Add a player</div>
    <div class="flex gap-2">
      <input v-model="newName" class="input" placeholder="Player's name (e.g. Ahmed Khan)"
        @keyup.enter="add" maxlength="40" />
      <button class="btn-primary shrink-0 px-5" :disabled="busy || !newName.trim()" @click="add">
        Add
      </button>
    </div>
    <p class="mt-2 text-[11px] text-slate-500">
      They don't need to have logged in yet. Just add their name and start recording matches.
    </p>
    <p v-if="msg" class="mt-2 text-xs text-rose-400">{{ msg }}</p>
  </div>

  <!-- Roster list -->
  <div v-if="players.length" class="card overflow-hidden">
    <div class="px-3 py-2 border-b border-white/5 text-xs text-slate-500">
      {{ players.length }} player{{ players.length !== 1 ? 's' : '' }} · sorted by Elo
    </div>
    <div v-for="(p, i) in players" :key="p.id"
      class="flex items-center justify-between px-3 py-2.5 border-b border-white/[0.04] last:border-0">
      <div class="flex items-center gap-2.5">
        <div class="w-7 h-7 rounded-full bg-white/10 flex items-center justify-center text-xs font-bold text-slate-400">
          {{ i + 1 }}
        </div>
        <div>
          <div class="font-medium text-sm text-slate-200">{{ p.display_name }}</div>
          <div class="text-[11px]" :class="eloColor(Math.round(p.elo))">
            Elo {{ Math.round(p.elo) }} · {{ eloLabel(Math.round(p.elo)) }}
          </div>
        </div>
      </div>
      <button v-if="isManager()" class="text-[11px] text-slate-600 hover:text-rose-400 transition px-2 py-1"
        @click="remove(p.id, p.display_name)">Remove</button>
    </div>
  </div>

  <div v-else class="card p-8 text-center text-slate-400">
    <div class="text-3xl mb-3">👤</div>
    <p class="font-medium mb-1">No players yet</p>
    <p class="text-sm">{{ isManager() ? 'Add your first player above.' : 'Ask your manager to add players.' }}</p>
  </div>
</template>
