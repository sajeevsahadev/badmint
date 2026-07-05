<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../composables/useAuth'
import ToggleSwitch from '../../components/ToggleSwitch.vue'

const router = useRouter()
const { user } = useAuth()

const loading = ref(true)
const saving  = ref(false)
const saved   = ref(false)
const prefs = ref({
  invites: true,
  match_recorded: false,
  weekly_digest: true,
  payment_reminders: true,
  news: true,
})
let savedTimer = null

const GROUPS = [
  {
    label: 'Club Activity',
    items: [
      { key: 'invites',        label: "When you're invited to a club" },
      { key: 'match_recorded', label: 'When a match is recorded' },
    ],
  },
  {
    label: 'Split Pay',
    items: [
      { key: 'payment_reminders', label: 'Payment reminders & balance due' },
    ],
  },
  {
    label: 'News & Updates',
    items: [
      { key: 'weekly_digest', label: 'Weekly ranking digest' },
      { key: 'news',          label: 'Badminton 360 announcements' },
    ],
  },
]

onMounted(async () => {
  const { data } = await supabase.from('user_profiles').select('email_prefs').eq('user_id', user.value.id).maybeSingle()
  if (data?.email_prefs) prefs.value = { ...prefs.value, ...data.email_prefs }
  loading.value = false
})

async function save() {
  saving.value = true
  const { error } = await supabase.rpc('update_notification_prefs', { p_email_prefs: prefs.value })
  saving.value = false
  if (!error) {
    saved.value = true
    clearTimeout(savedTimer)
    savedTimer = setTimeout(() => { saved.value = false }, 2500)
  }
}
</script>

<template>
  <div class="max-w-sm mx-auto pt-2 fade-up">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-6" @click="router.back()">‹ Back</button>

    <h1 class="font-display text-xl font-extrabold gradient-text mb-1">📧 Email Settings</h1>
    <p class="text-sm text-slate-400 mb-5">Choose what Badminton 360 emails you about.</p>

    <div class="rounded-2xl px-4 py-3 mb-5 text-xs text-slate-500 leading-relaxed" style="background:rgba(0,168,204,.06); border:1px solid rgba(0,168,204,.15)">
      ⚙️ Your choices here are saved. Club invite emails always send today since
      that's how invites work; the other categories will start respecting these
      preferences as each notification type goes live.
    </div>

    <div v-if="loading" class="space-y-3">
      <div v-for="i in 3" :key="i" class="h-16 shimmer rounded-2xl" />
    </div>

    <div v-else class="space-y-4">
      <div v-for="group in GROUPS" :key="group.label" class="card p-4">
        <div class="label mb-3">{{ group.label }}</div>
        <div class="space-y-4">
          <div v-for="item in group.items" :key="item.key" class="flex items-center justify-between gap-3">
            <div class="text-sm font-medium text-slate-700 min-w-0">{{ item.label }}</div>
            <ToggleSwitch v-model="prefs[item.key]" />
          </div>
        </div>
      </div>

      <button class="btn-primary w-full py-3" :disabled="saving" @click="save">
        {{ saving ? 'Saving…' : 'Save Changes' }}
      </button>
      <p v-if="saved" class="text-center text-xs text-emerald-500">✅ Saved!</p>
    </div>
  </div>
</template>
