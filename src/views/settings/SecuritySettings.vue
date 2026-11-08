<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../composables/useAuth'
import { useBiometricLock } from '../../composables/useBiometricLock'
import ToggleSwitch from '../../components/ToggleSwitch.vue'

const router = useRouter()
const { user } = useAuth()
const { isEnabled, hasCredentialOnThisDevice, timeoutMs, isPlatformAvailable, register, disable, forgetThisDevice, setTimeout: setLockTimeout } = useBiometricLock()

const platformAvailable = ref(false)
const busy              = ref(false)
const err               = ref('')
const devices           = ref([])
const loadingDevices    = ref(true)
const thisCredentialId  = localStorage.getItem('b360_webauthn_cred_id')

const TIMEOUTS = [
  { ms: 0,        label: 'Immediately' },
  { ms: 60_000,   label: 'After 1 minute' },
  { ms: 300_000,  label: 'After 5 minutes' },
  { ms: 1_800_000, label: 'After 30 minutes' },
]

async function loadDevices() {
  loadingDevices.value = true
  const { data } = await supabase
    .from('webauthn_credentials')
    .select('id, credential_id, device_label, created_at, last_used_at')
    .order('created_at', { ascending: false })
  devices.value = data ?? []
  loadingDevices.value = false
}

onMounted(async () => {
  loadFaceId()
  platformAvailable.value = await isPlatformAvailable()
  await loadDevices()
})

// Opt-in face recognition for match-video tagging (biometric data — explicit consent, off by default).
const faceId     = ref({ consent: false, samples: 0 })
const faceBusy   = ref(false)
const faceErr    = ref('')
const faceAsk    = ref(false)   // showing the "are you sure" explanation before turning on
async function loadFaceId() {
  const { data } = await supabase.rpc('get_face_id_status')
  if (data) faceId.value = data
}
async function setFaceId(on) {
  faceErr.value = ''
  if (on && !faceAsk.value) { faceAsk.value = true; return }
  faceBusy.value = true
  const { error } = await supabase.rpc('set_face_id_consent', { p_on: on })
  if (error) faceErr.value = error.message
  faceAsk.value = false
  await loadFaceId()
  faceBusy.value = false
}

async function onToggle(value) {
  err.value = ''
  if (value) {
    busy.value = true
    try {
      await register(user.value.id, user.value.user_metadata?.full_name || user.value.email)
      await loadDevices()
    } catch (e) {
      err.value = e.message || 'Could not set up biometric unlock on this device.'
    }
    busy.value = false
  } else {
    disable()
  }
}

async function removeDevice(row) {
  busy.value = true
  await supabase.from('webauthn_credentials').delete().eq('id', row.id)
  if (row.credential_id === thisCredentialId) await forgetThisDevice()
  await loadDevices()
  busy.value = false
}

function fmtDate(d) {
  return d ? new Date(d).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' }) : '—'
}
</script>

<template>
  <div class="max-w-sm mx-auto pt-2 fade-up">
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-6" @click="router.back()">‹ Back</button>

    <h1 class="font-display text-xl font-extrabold gradient-text mb-1">🔒 Security</h1>
    <p class="text-sm text-slate-400 mb-5">Badminton 360 signs in with Google only. Biometrics just re-lock the app on this device.</p>

    <div class="rounded-2xl px-4 py-3 mb-5 text-xs text-slate-500 leading-relaxed" style="background:rgba(0,168,204,.06); border:1px solid rgba(0,168,204,.15)">
      ℹ️ A fingerprint or Face ID can only re-open a session that's already signed in on
      this device. It can never sign in as you — after a real Sign Out, Google sign-in
      is always required, on any device.
    </div>

    <div v-if="!platformAvailable" class="card p-4 text-sm text-slate-500">
      This device or browser doesn't support biometric unlock (Face ID, Touch ID, or Windows Hello).
    </div>

    <template v-else>
      <div class="card p-4 mb-4">
        <div class="flex items-center justify-between gap-3">
          <div class="min-w-0">
            <div class="text-sm font-semibold text-slate-700">Require biometric to open Badminton 360</div>
            <div class="text-xs text-slate-400 mt-0.5">Applies to this device only</div>
          </div>
          <ToggleSwitch :model-value="isEnabled" :disabled="busy" @update:model-value="onToggle" />
        </div>
        <p v-if="err" class="text-xs text-rose-500 mt-2">⚠ {{ err }}</p>
      </div>

      <div v-if="isEnabled" class="card p-4 mb-4">
        <div class="label mb-3">Lock Timeout</div>
        <div class="grid grid-cols-2 gap-2">
          <button v-for="t in TIMEOUTS" :key="t.ms"
            @click="setLockTimeout(t.ms)"
            class="px-3 py-2 rounded-xl text-xs font-semibold border transition"
            :class="timeoutMs === t.ms ? 'text-white border-transparent' : 'text-slate-600 border-slate-200 hover:border-cyan-300'"
            :style="timeoutMs === t.ms ? 'background:linear-gradient(135deg,#00b4d8,#0077a8)' : ''"
          >
            {{ t.label }}
          </button>
        </div>
        <p class="text-[11px] text-slate-400 mt-3 leading-relaxed">
          Reopening the app before the timeout won't ask again.
        </p>
      </div>
    </template>

    <div class="card p-4 mb-4">
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <div class="text-sm font-semibold text-slate-700">Recognise me in match videos</div>
          <div class="text-xs text-slate-400 mt-0.5">Auto-tags you in AI Match Analysis · off by default</div>
        </div>
        <ToggleSwitch :model-value="faceId.consent || faceAsk" :disabled="faceBusy" @update:model-value="setFaceId" />
      </div>
      <div v-if="faceAsk" class="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs leading-relaxed text-slate-600">
        <p class="font-semibold text-slate-800">Before you turn this on</p>
        <ul class="mt-1 list-disc space-y-1 pl-4">
          <li>When you're tagged in a match video, we save a <b>face signature</b> (a list of numbers made from your face — not a photo).</li>
          <li>Next time, the app uses it to suggest your name automatically. Someone still checks it before saving.</li>
          <li>This is biometric data. Only you can see how many we hold, and nobody else can download it.</li>
          <li>Turn it off any time — everything we saved is deleted straight away.</li>
        </ul>
        <div class="mt-3 flex gap-2">
          <button class="btn-primary flex-1 py-2 text-xs" :disabled="faceBusy" @click="setFaceId(true)">I agree — turn on</button>
          <button class="btn-ghost px-3 py-2 text-xs" @click="faceAsk = false">Cancel</button>
        </div>
      </div>
      <p v-else-if="faceId.consent" class="mt-2 text-[11px] text-slate-400">
        On since {{ fmtDate(faceId.since) }} · {{ faceId.samples }} face signature{{ faceId.samples === 1 ? '' : 's' }} saved.
        Turning it off deletes them all.
      </p>
      <p v-if="faceErr" class="text-xs text-rose-500 mt-2">⚠ {{ faceErr }}</p>
    </div>

    <div class="card p-4">
      <div class="label mb-3">Trusted Devices</div>
      <div v-if="loadingDevices" class="space-y-2">
        <div v-for="i in 2" :key="i" class="h-12 shimmer rounded-xl" />
      </div>
      <p v-else-if="!devices.length" class="text-sm text-slate-400">No devices have biometric unlock set up yet.</p>
      <div v-else class="space-y-2">
        <div v-for="d in devices" :key="d.id" class="flex items-center justify-between gap-3 px-3 py-2.5 rounded-xl" style="background:#fafafa; border:1px solid rgba(15,23,42,.06)">
          <div class="min-w-0">
            <div class="text-sm font-medium text-slate-700 flex items-center gap-1.5">
              {{ d.device_label || 'Unknown device' }}
              <span v-if="d.credential_id === thisCredentialId" class="badge-member">This device</span>
            </div>
            <div class="text-[11px] text-slate-400 mt-0.5">
              Added {{ fmtDate(d.created_at) }} · Last used {{ fmtDate(d.last_used_at) }}
            </div>
          </div>
          <button class="text-xs text-rose-500 hover:text-rose-600 shrink-0 px-1" :disabled="busy" @click="removeDevice(d)">Remove</button>
        </div>
      </div>
    </div>
  </div>
</template>
