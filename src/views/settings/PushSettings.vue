<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../composables/useAuth'
import { usePushNotifications } from '../../composables/usePushNotifications'
import ToggleSwitch from '../../components/ToggleSwitch.vue'

const router = useRouter()
const { user } = useAuth()
const { isSupported, subscribe, isSubscribed } = usePushNotifications()

const loading       = ref(true)
const saving        = ref(false)
const saved         = ref(false)
const subscribed    = ref(false)
const subscribing   = ref(false)
const subscribeErr  = ref('')

const prefs = ref({
  chat_messages: true,
  reactions: true,
  invites: true,
  match_recorded: true,
  schedule_polls: true,
  payment_reminders: true,
})

const ITEMS = [
  { key: 'chat_messages',     label: 'Club chat messages' },
  { key: 'reactions',         label: 'Reactions to your messages' },
  { key: 'invites',           label: 'Club invites' },
  { key: 'match_recorded',    label: 'Match recorded' },
  { key: 'schedule_polls',    label: "Who's Playing? poll reminders" },
  { key: 'payment_reminders', label: 'Payment reminders & balance due' },
]

onMounted(async () => {
  const [{ data }, subbed] = await Promise.all([
    supabase.from('user_profiles').select('push_prefs').eq('user_id', user.value.id).maybeSingle(),
    isSupported ? isSubscribed() : Promise.resolve(false),
  ])
  if (data?.push_prefs) prefs.value = { ...prefs.value, ...data.push_prefs }
  subscribed.value = subbed
  loading.value = false
})

async function enablePush() {
  subscribing.value = true
  subscribeErr.value = ''
  try {
    await subscribe()
    subscribed.value = true
  } catch (e) {
    subscribeErr.value = e.message
  }
  subscribing.value = false
}

async function save() {
  saving.value = true
  const { error } = await supabase.rpc('update_notification_prefs', { p_push_prefs: prefs.value })
  saving.value = false
  if (!error) {
    saved.value = true
    setTimeout(() => { saved.value = false }, 2500)
  }
}
</script>

<template>
  <div class="max-w-sm mx-auto pt-2 fade-up">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-6" @click="router.back()">‹ Back</button>

    <h1 class="font-display text-xl font-extrabold gradient-text mb-1">🔔 Device & Push Notifications</h1>
    <p class="text-sm text-slate-400 mb-5">Get a nudge on your phone or laptop, not just an email.</p>

    <div v-if="loading" class="space-y-3">
      <div v-for="i in 2" :key="i" class="h-16 shimmer rounded-2xl" />
    </div>

    <div v-else class="space-y-4">

      <div v-if="!isSupported" class="rounded-2xl px-4 py-3 text-xs text-slate-500 leading-relaxed" style="background:rgba(15,23,42,.05); border:1px solid rgba(15,23,42,.1)">
        This browser doesn't support push notifications.
      </div>

      <div v-else class="card p-4">
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <div class="text-sm font-semibold text-slate-700">Push notifications on this device</div>
            <div class="text-xs text-slate-400 mt-0.5">
              {{ subscribed ? 'Enabled for all your clubs' : 'Not enabled yet' }}
            </div>
          </div>
          <button v-if="!subscribed" class="btn-primary text-xs px-3 py-1.5 shrink-0" :disabled="subscribing" @click="enablePush">
            {{ subscribing ? 'Enabling…' : 'Enable' }}
          </button>
          <span v-else class="text-xs font-bold text-emerald-600 shrink-0">✓ On</span>
        </div>
        <p v-if="subscribeErr" class="text-xs text-rose-500 mt-2">⚠ {{ subscribeErr }}</p>
        <p class="text-[11px] text-slate-400 mt-3 leading-relaxed">
          Notifications work across all your clubs on this device.
        </p>
      </div>

      <div class="card p-4">
        <div class="label mb-3">Notify Me About</div>
        <div class="space-y-4">
          <div v-for="item in ITEMS" :key="item.key" class="flex items-center justify-between gap-3">
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
