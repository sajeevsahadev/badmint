import { ref } from 'vue'
import { supabase } from '../lib/supabase'

// App-lock only (never a login replacement — see CLAUDE.md Security section).
// A successful navigator.credentials.get() proves the platform authenticator
// (Face ID / Touch ID / Windows Hello / Android fingerprint) matched on THIS
// device — that's sufficient to re-reveal an ALREADY-valid Supabase session.
// No signature is verified server-side; the only server round-trip is an
// optional best-effort "was this device's credential removed remotely?"
// check, skipped gracefully when offline so the PWA still unlocks.
const LOCK_KEY        = 'b360_biometric_lock'    // '1' if enabled on this device
const CRED_KEY        = 'b360_webauthn_cred_id'  // this device's credential id (base64url)
const TIMEOUT_KEY     = 'b360_lock_timeout_ms'
const HIDDEN_AT_KEY   = 'b360_hidden_at'

const isEnabled = ref(localStorage.getItem(LOCK_KEY) === '1')
const timeoutMs = ref(Number(localStorage.getItem(TIMEOUT_KEY)) || 5 * 60 * 1000)
const isLocked  = ref(false)
const hasCredentialOnThisDevice = ref(!!localStorage.getItem(CRED_KEY))

function bufToBase64url(buf) {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}
function base64urlToBuf(b64url) {
  const pad = '='.repeat((4 - (b64url.length % 4)) % 4)
  const b64 = (b64url + pad).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
}
function guessDeviceLabel() {
  const ua = navigator.userAgent
  const os = /iPhone|iPad/.test(ua) ? 'iOS' : /Android/.test(ua) ? 'Android' : /Mac/.test(ua) ? 'Mac' : /Win/.test(ua) ? 'Windows' : 'Device'
  const browser = /Edg/.test(ua) ? 'Edge' : /Chrome/.test(ua) ? 'Chrome' : /Safari/.test(ua) ? 'Safari' : /Firefox/.test(ua) ? 'Firefox' : 'Browser'
  return `${browser} on ${os}`
}

// Lock automatically once the tab has been hidden longer than the timeout.
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      localStorage.setItem(HIDDEN_AT_KEY, String(Date.now()))
    } else if (isEnabled.value && hasCredentialOnThisDevice.value) {
      const hiddenAt = Number(localStorage.getItem(HIDDEN_AT_KEY)) || 0
      if (hiddenAt && Date.now() - hiddenAt > timeoutMs.value) isLocked.value = true
    }
  })
}

export function useBiometricLock() {
  async function isPlatformAvailable() {
    if (!window.PublicKeyCredential?.isUserVerifyingPlatformAuthenticatorAvailable) return false
    try { return await window.PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable() }
    catch { return false }
  }

  // Lock on cold boot whenever it's enabled — closing the tab/app always re-locks.
  function armOnBoot() {
    if (isEnabled.value && hasCredentialOnThisDevice.value) isLocked.value = true
  }

  async function register(userId, userLabel) {
    const challenge = crypto.getRandomValues(new Uint8Array(32))
    const cred = await navigator.credentials.create({
      publicKey: {
        challenge,
        rp: { name: 'Badminton 360' },
        user: {
          id: new TextEncoder().encode(userId),
          name: userLabel,
          displayName: userLabel,
        },
        pubKeyCredParams: [{ alg: -7, type: 'public-key' }, { alg: -257, type: 'public-key' }],
        authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'required' },
        timeout: 60000,
      },
    })
    if (!cred) throw new Error('Registration was cancelled')

    const credentialId = bufToBase64url(cred.rawId)
    const { error } = await supabase.from('webauthn_credentials').insert({
      user_id: userId, credential_id: credentialId, device_label: guessDeviceLabel(),
    })
    if (error) throw new Error(error.message)

    localStorage.setItem(CRED_KEY, credentialId)
    localStorage.setItem(LOCK_KEY, '1')
    hasCredentialOnThisDevice.value = true
    isEnabled.value = true
  }

  // Turn the gate off on this device without forgetting the registered
  // credential — re-enabling later just flips the flag back on.
  function disable() {
    localStorage.removeItem(LOCK_KEY)
    isEnabled.value = false
    isLocked.value = false
  }

  // Fully forgets this device: removes the local credential AND its server
  // record, so it drops off the Trusted Devices list everywhere.
  async function forgetThisDevice() {
    const credId = localStorage.getItem(CRED_KEY)
    if (credId) await supabase.from('webauthn_credentials').delete().eq('credential_id', credId)
    localStorage.removeItem(CRED_KEY)
    localStorage.removeItem(LOCK_KEY)
    hasCredentialOnThisDevice.value = false
    isEnabled.value = false
    isLocked.value = false
  }

  function setTimeout_(ms) {
    timeoutMs.value = ms
    localStorage.setItem(TIMEOUT_KEY, String(ms))
  }

  async function verify() {
    const credId = localStorage.getItem(CRED_KEY)
    if (!credId) throw new Error('No biometric credential registered on this device')

    const challenge = crypto.getRandomValues(new Uint8Array(32))
    const assertion = await navigator.credentials.get({
      publicKey: {
        challenge,
        allowCredentials: [{ id: base64urlToBuf(credId), type: 'public-key' }],
        userVerification: 'required',
        timeout: 60000,
      },
    })
    if (!assertion) throw new Error('Verification failed')

    // Best-effort remote revocation check — if this device was removed from
    // Trusted Devices (e.g. reported lost) and we're online, honour that.
    try {
      const { data, error } = await supabase
        .from('webauthn_credentials').select('id').eq('credential_id', credId).maybeSingle()
      if (!error && !data) { await forgetThisDevice(); throw new Error('This device was removed from Trusted Devices') }
      if (!error && data) supabase.from('webauthn_credentials').update({ last_used_at: new Date().toISOString() }).eq('credential_id', credId).then(() => {})
    } catch { /* offline — fall back to the local WebAuthn success */ }

    return true
  }

  async function unlock() {
    await verify()
    isLocked.value = false
  }

  return {
    isEnabled, isLocked, hasCredentialOnThisDevice, timeoutMs,
    isPlatformAvailable, armOnBoot, register, disable, forgetThisDevice, setTimeout: setTimeout_, verify, unlock,
  }
}
