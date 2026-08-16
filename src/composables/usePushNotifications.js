import { supabase } from '../lib/supabase'

// VAPID PUBLIC KEY — single source of truth.
// This MUST byte-for-byte match the VAPID_PUBLIC_KEY secret used by the
// send-push / notify-chat Edge Functions, whose private-key mate signs every
// push. If the browser subscribes with a different key than the server signs
// with, the push service rejects delivery with HTTP 403 ("VAPID credentials
// do not correspond to the subscription") and nothing arrives.
//
// It is deliberately hardcoded (NOT read from import.meta.env) so a stale or
// wrong VITE_VAPID_PUBLIC_KEY in the hosting dashboard can never silently
// re-break delivery. To rotate keys: change this constant AND the Edge
// Function secrets together, then existing clients auto re-key on next load.
const VAPID_PUBLIC_KEY = 'BFXI6DZ2xlvyg6UgtVvgs1WrRY7dbHAFBm5xje4RGvAXEStHaP-cLNDwuiwK07-df8K0J2j0aFHWGkjfyE0KAjk'

// Short fingerprint of the current key, stored in localStorage when we subscribe.
// This lets us detect a deliberate VAPID rotation on EVERY device — even the many
// browsers (Android/WebView especially) that return applicationServerKey:null on a
// retrieved subscription and so can't be verified by byte-comparison.
const KEY_TAG   = 'k' + VAPID_PUBLIC_KEY.slice(-12)
const TAG_STORE = 'bm_push_keytag'
// Stale only when a DIFFERENT tag was previously stored (a real rotation).
// A missing tag (existing users, first run after this fix) is NOT stale, so we
// never force a disruptive re-subscribe on everyone — we just record the tag.
function tagStale()  { try { const t = localStorage.getItem(TAG_STORE); return t !== null && t !== KEY_TAG } catch { return false } }
function markTag()   { try { localStorage.setItem(TAG_STORE, KEY_TAG) } catch { /* ignore */ } }

function urlBase64ToUint8Array(base64) {
  const pad = '='.repeat((4 - (base64.length % 4)) % 4)
  const b64 = (base64 + pad).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
}

// Returns true ONLY when we can positively prove the subscription uses a
// different key than we sign with. Crucially, when the browser doesn't expose
// applicationServerKey on a retrieved subscription (returns null — common on
// Android/WebView), we DO NOT claim a mismatch. Treating "unknown" as "stale"
// was the bug: it made a perfectly good subscription read as "not enabled"
// after reopening the app, and re-subscribed on every launch.
function keyDefinitelyDiffers(sub, wantBytes) {
  const buf = sub?.options?.applicationServerKey
  if (!buf) return false            // unknown → cannot conclude a mismatch
  const have = new Uint8Array(buf)
  if (have.length !== wantBytes.length) return true
  for (let i = 0; i < have.length; i++) if (have[i] !== wantBytes[i]) return true
  return false
}

export function usePushNotifications() {
  const isSupported = typeof window !== 'undefined' && 'PushManager' in window && 'serviceWorker' in navigator

  async function getPermission() {
    if (!('Notification' in window)) return 'unsupported'
    return Notification.permission
  }

  async function saveSubscription(sub) {
    const json = sub.toJSON()
    await supabase.rpc('save_push_subscription', {
      p_endpoint: json.endpoint,
      p_p256dh:   json.keys.p256dh,
      p_auth:     json.keys.auth,
    })
  }

  // Drop the local subscription + its DB row if it was made with a stale key.
  async function dropStale(sub) {
    const oldEndpoint = sub.endpoint
    try { await sub.unsubscribe() } catch { /* ignore */ }
    try { await supabase.from('push_subscriptions').delete().eq('endpoint', oldEndpoint) } catch { /* ignore */ }
  }

  async function subscribe() {
    if (!isSupported) throw new Error('Push not supported on this device.')
    const wantBytes = urlBase64ToUint8Array(VAPID_PUBLIC_KEY)

    const permission = await Notification.requestPermission()
    if (permission !== 'granted') throw new Error('Notification permission denied.')

    const reg = await navigator.serviceWorker.ready
    let sub = await reg.pushManager.getSubscription()

    // Re-key only when the key definitely differs, or a rotation is flagged.
    if (sub && (keyDefinitelyDiffers(sub, wantBytes) || tagStale())) {
      await dropStale(sub)
      sub = null
    }
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: wantBytes,
      })
    }

    await saveSubscription(sub)
    markTag()
    return sub
  }

  // True when a subscription exists and we cannot prove it's mis-keyed. (A
  // rotation flagged via tagStale is healed silently by resyncIfNeeded on boot,
  // so we still report enabled here rather than flapping the toggle off.)
  async function isSubscribed() {
    if (!isSupported) return false
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    return !!sub && !keyDefinitelyDiffers(sub, urlBase64ToUint8Array(VAPID_PUBLIC_KEY))
  }

  // Silent self-heal, safe to call on app boot. If the user already granted
  // permission but their subscription uses a stale key (or its DB row went
  // missing), transparently re-subscribe with the correct key. No prompt is
  // shown because permission is already 'granted'.
  async function resyncIfNeeded() {
    if (!isSupported) return false
    if (!('Notification' in window) || Notification.permission !== 'granted') return false
    try {
      const reg = await navigator.serviceWorker.ready
      const wantBytes = urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
      let sub = await reg.pushManager.getSubscription()
      // Re-key only on a proven mismatch or a flagged rotation — NOT on every
      // boot just because the browser hides the key.
      if (sub && (keyDefinitelyDiffers(sub, wantBytes) || tagStale())) {
        await dropStale(sub)
        sub = null
      }
      if (!sub) {
        sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: wantBytes })
      }
      // Idempotent upsert — also heals a DB row that went missing — plus record
      // the key tag so a future rotation is detected on this device.
      await saveSubscription(sub)
      markTag()
      return true
    } catch {
      return false
    }
  }

  return { isSupported, getPermission, subscribe, isSubscribed, resyncIfNeeded }
}
