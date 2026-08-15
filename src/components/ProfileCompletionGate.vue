<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../composables/useAuth'

// Blocking overlay shown to any signed-in user who has no phone number on file.
// Phone is mandatory for everyone (not just new joiners) — see Feature A.
// Preserves every other profile field so saving here never wipes an existing
// nickname/bio/region/gender.
const emit = defineEmits(['done'])
const { user, signOut } = useAuth()

const loading = ref(true)
const busy    = ref(false)
const err     = ref('')
const errors  = ref({})

// Existing row is loaded so upsert_profile can round-trip untouched fields.
const existing = ref({ nickname: '', full_name: '', bio: '', emirate: '', country: '', gender: null })
const form = ref({ fullName: '', phone: '' })

onMounted(async () => {
  const { data } = await supabase
    .from('user_profiles')
    .select('nickname, full_name, phone, bio, emirate, country, gender')
    .eq('user_id', user.value.id)
    .maybeSingle()
  existing.value = {
    nickname: data?.nickname || '',
    full_name: data?.full_name || '',
    bio: data?.bio || '',
    emirate: data?.emirate || '',
    country: data?.country || '',
    gender: data?.gender ?? null,
  }
  // Prefill name from existing profile or the Google account
  form.value.fullName = data?.full_name || user.value.user_metadata?.full_name || ''
  form.value.phone    = data?.phone || ''
  loading.value = false
})

function validate() {
  errors.value = {}
  if (!form.value.fullName.trim()) errors.value.fullName = 'Your name is required'
  if (!form.value.phone.trim())    errors.value.phone    = 'Phone number is required'
  return Object.keys(errors.value).length === 0
}

async function save() {
  if (!validate()) return
  busy.value = true; err.value = ''
  // Keep an existing nickname; otherwise seed it from the first name so the
  // leaderboard has something to show.
  const nickname = existing.value.nickname?.trim()
    || form.value.fullName.trim().split(/\s+/)[0]
    || 'Player'
  const { error } = await supabase.rpc('upsert_profile', {
    p_nickname:  nickname,
    p_full_name: form.value.fullName.trim(),
    p_phone:     form.value.phone.trim(),
    p_bio:       existing.value.bio      || null,
    p_emirate:   existing.value.emirate  || null,
    p_country:   existing.value.country  || null,
    p_gender:    existing.value.gender   || null,
  })
  busy.value = false
  if (error) { err.value = error.message; return }
  emit('done')
}

async function bail() {
  await signOut()
  window.location.href = '/login'
}
</script>

<template>
  <div class="fixed inset-0 z-[350] flex items-center justify-center px-5"
    style="background:rgba(3,8,20,.82); backdrop-filter:blur(6px)">
    <div class="w-full max-w-sm rounded-2xl p-6"
      style="background:#0d1a2e; border:1px solid rgba(0,229,255,.2); box-shadow:0 8px 40px rgba(0,0,0,.6)">

      <div v-if="loading" class="text-center py-6">
        <div class="text-3xl mb-2 animate-pulse">🏸</div>
        <p class="text-slate-400 text-sm">Loading your profile…</p>
      </div>

      <template v-else>
        <div class="text-center mb-5">
          <div class="text-4xl mb-2" style="filter:drop-shadow(0 0 16px rgba(0,229,255,.5))">👋</div>
          <h2 class="font-display text-xl font-extrabold gradient-text mb-1">One quick thing</h2>
          <p class="text-slate-400 text-sm">Confirm your name and add a phone number to continue.</p>
        </div>

        <div class="space-y-4">
          <div>
            <label class="label">Your Name <span class="text-rose-400">*</span></label>
            <input v-model="form.fullName" class="input" placeholder="e.g. Ahmed Al Mansouri" maxlength="60" />
            <p v-if="errors.fullName" class="text-[11px] text-rose-400 mt-1">{{ errors.fullName }}</p>
          </div>
          <div>
            <label class="label">Phone Number <span class="text-rose-400">*</span></label>
            <input v-model="form.phone" class="input" type="tel" placeholder="+971 50 123 4567" />
            <p class="text-[10px] text-slate-500 mt-1">Only visible to your club managers — never shown publicly.</p>
            <p v-if="errors.phone" class="text-[11px] text-rose-400 mt-1">{{ errors.phone }}</p>
          </div>
        </div>

        <p v-if="err" class="text-xs text-rose-400 mt-3">{{ err }}</p>

        <button class="btn-primary w-full mt-5 py-3.5 text-base" :disabled="busy" @click="save">
          {{ busy ? 'Saving…' : 'Save & Continue' }}
        </button>
        <button class="w-full mt-2 py-2 text-xs text-slate-500 hover:text-slate-300 transition" @click="bail">
          Sign out instead
        </button>
      </template>
    </div>
  </div>
</template>
