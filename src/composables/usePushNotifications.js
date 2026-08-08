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

function urlBase64ToUint8Array(base64) {
  const pad = '='.repeat((4 - (base64.length % 4)) % 4)
  const b64 = (base64 + pad).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(b64)
  return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
}

// Does an existing browser subscription use the same applicationServerKey we
// sign with? If not, it was created with an old VAPID key and is undeliverable.
function subKeyMatches(sub, wantBytes) {
  const buf = sub?.options?.applicationServerKey
  if (!buf) return false
  const have = new Uint8Array(buf)
  if (have.length !== wantBytes.length) return false
  for (let i = 0; i < have.length; i++) if (have[i] !== wantBytes[i]) return false
  return true
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

    // Heal the exact bug that broke delivery: a subscription created with an
    // older VAPID key. Re-key it to the current one.
    if (sub && !subKeyMatches(sub, wantBytes)) {
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
    return sub
  }

  // Returns true only when a *deliverable* (correctly-keyed) subscription exists.
  async function isSubscribed() {
    if (!isSupported) return false
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    return !!sub && subKeyMatches(sub, urlBase64ToUint8Array(VAPID_PUBLIC_KEY))
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
      if (sub && !subKeyMatches(sub, wantBytes)) {
        await dropStale(sub)
        sub = null
      }
      if (!sub) {
        sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: wantBytes })
      }
      await saveSubscription(sub)
      return true
    } catch {
      return false
    }
  }

  return { isSupported, getPermission, subscribe, isSubscribed, resyncIfNeeded }
}
