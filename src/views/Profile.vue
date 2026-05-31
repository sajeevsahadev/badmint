<script setup>
import { ref, computed, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'
import { useClub } from '../composables/useClub'

const { user } = useAuth()
const { clubs } = useClub()

const profile  = ref(null)   // user_profiles row
const myStats  = ref([])     // leaderboard entries for all clubs this user is a player in
const loading  = ref(true)
const saving   = ref(false)
const saved    = ref(false)
const error    = ref(null)

// Edit form
const form = ref({ nickname: '', phone: '', bio: '' })

async function load() {
  if (!user.value) return
  loading.value = true

  const [{ data: prof }, { data: playerRows }] = await Promise.all([
    supabase.from('user_profiles').select('*').eq('user_id', user.value.id).maybeSingle(),
    supabase.from('players').select('id, display_name, elo, club_id').eq('user_id', user.value.id),
  ])

  profile.value = prof

  // Load leaderboard stats for each club this user is in
  if (playerRows?.length) {
    const playerIds = playerRows.map(p => p.id)
    const { data: lbRows } = await supabase
      .from('v_leaderboard')
      .select('id, club_id, display_name, elo, composite, club_rank, games, wins, win_pct, days_played')
      .in('id', playerIds)
    myStats.value = lbRows ?? []
  }

  // Pre-fill form
  form.value.nickname = prof?.nickname ?? user.value.user_metadata?.full_name ?? ''
  form.value.phone    = prof?.phone ?? ''
  form.value.bio      = prof?.bio ?? ''
  loading.value = false
}

onMounted(load)

async function save() {
  if (!form.value.nickname.trim()) { error.value = 'Nickname is required.'; return }
  saving.value = true; error.value = null; saved.value = false
  const { error: err } = await supabase.rpc('upsert_profile', {
    p_nickname: form.value.nickname.trim(),
    p_phone:    form.value.phone.trim() || null,
    p_bio:      form.value.bio.trim()   || null,
  })
  saving.value = false
  if (err) { error.value = err.message }
  else {
    saved.value = true
    if (!profile.value) profile.value = {}
    profile.value.nickname = form.value.nickname.trim()
    setTimeout(() => { saved.value = false }, 3000)
  }
}

const initials = computed(() => {
  const name = form.value.nickname || user.value?.email || '?'
  return name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase()
})

const clubName = (clubId) => clubs.value.find(c => c.club_id === clubId)?.clubs?.name ?? clubId
</script>

<template>
  <div v-if="loading" class="space-y-3">
    <div v-for="i in 3" :key="i" class="h-20 shimmer rounded-2xl" />
  </div>

  <template v-else>
    <!-- Avatar + header -->
    <div class="flex items-center gap-4 mb-6 fade-up">
      <div class="w-16 h-16 rounded-2xl flex items-center justify-center text-xl font-black text-slate-950 shrink-0"
        style="background:linear-gradient(135deg,#00e5ff,#a855f7)">
        {{ initials }}
      </div>
      <div>
        <h2 class="font-display text-xl font-bold gradient-text leading-tight">
          {{ profile?.nickname || 'Set your nickname' }}
        </h2>
        <p class="text-xs text-slate-500 mt-0.5">{{ user?.email }}</p>
        <p class="text-[10px] text-slate-600 mt-0.5">{{ clubs.length }} club{{ clubs.length !== 1 ? 's' : '' }}</p>
      </div>
    </div>

    <!-- Edit form -->
    <div class="card p-4 mb-4 fade-up">
      <div class="label">Edit Profile</div>

      <div class="space-y-3">
        <div>
          <label class="label">Nickname / Public Name <span class="text-rose-400">*</span></label>
          <input v-model="form.nickname" class="input" placeholder="How others see you (e.g. Flash)" maxlength="30" />
          <p class="text-[10px] text-slate-500 mt-1">This name appears publicly on leaderboards and explore page.</p>
        </div>
        <div>
          <label class="label">Phone Number <span class="text-slate-600">(optional)</span></label>
          <input v-model="form.phone" class="input" type="tel" placeholder="+971 50 123 4567" />
        </div>
        <div>
          <label class="label">Bio <span class="text-slate-600">(optional)</span></label>
          <textarea v-model="form.bio" class="input resize-none" rows="2"
            placeholder="Tell the court about yourself…" maxlength="120" />
        </div>
      </div>

      <p v-if="error" class="mt-3 text-xs text-rose-400">{{ error }}</p>
      <p v-if="saved" class="mt-3 text-xs text-emerald-400">✅ Profile saved!</p>

      <button class="btn-primary w-full mt-4" :disabled="saving" @click="save">
        {{ saving ? 'Saving…' : 'Save Profile' }}
      </button>
    </div>

    <!-- Club stats -->
    <div v-if="myStats.length" class="card overflow-hidden mb-4 fade-up">
      <div class="px-4 py-3 border-b border-white/[0.06]">
        <div class="text-xs font-bold text-slate-200">My Club Rankings</div>
      </div>
      <div v-for="s in myStats" :key="s.id"
        class="flex items-center justify-between px-4 py-3 border-b border-white/[0.04] last:border-0">
        <div>
          <div class="text-sm font-semibold text-slate-100">{{ s.display_name }}</div>
          <div class="text-[11px] text-slate-500">{{ clubName(s.club_id) }}</div>
        </div>
        <div class="text-right">
          <div class="text-sm font-extrabold text-neon">Rank #{{ s.club_rank }}</div>
          <div class="text-[11px] text-slate-500">Elo {{ s.elo }} · {{ s.games }}G · {{ s.win_pct }}% W</div>
        </div>
      </div>
    </div>

    <!-- No stats yet -->
    <div v-else class="card p-6 text-center text-slate-400 text-sm fade-up">
      <div class="text-2xl mb-2">🎯</div>
      <p>No match stats yet. Ask your manager to link your account to a player.</p>
    </div>
  </template>
</template>
