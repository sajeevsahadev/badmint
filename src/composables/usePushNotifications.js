import { supabase } from '../lib/supabase'

// VAPID public key — not secret by design (that's the point of public-key
// crypto for Web Push). Hardcoded as the default so delivery works out of
// the box regardless of whether VITE_VAPID_PUBLIC_KEY is set in the hosting
// dashboard; an env var, if present, still overrides it.
// Matching private key lives ONLY in the send-push Edge Function's secrets.
const DEFAULT_VAPID_PUBLIC_KEY = 'BFXI6DZ2xlvyg6UgtVvgs1WrRY7dbHAFBm5xje4RGvAXEStHaP-cLNDwuiwK07-df8K0J2j0aFHWGkjfyE0KAjk'

export function usePushNotifications() {
  const isSupported = typeof window !== 'undefined' && 'PushManager' in window && 'serviceWorker' in navigator

  function urlBase64ToUint8Array(base64) {
    const pad = '='.repeat((4 - (base64.length % 4)) % 4)
    const b64 = (base64 + pad).replace(/-/g, '+').replace(/_/g, '/')
    const raw = atob(b64)
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)))
  }

  async function getPermission() {
    if (!('Notification' in window)) return 'unsupported'
    return Notification.permission
  }

  async function subscribe() {
    const vapidKey = import.meta.env.VITE_VAPID_PUBLIC_KEY || DEFAULT_VAPID_PUBLIC_KEY

    const permission = await Notification.requestPermission()
    if (permission !== 'granted') throw new Error('Notification permission denied.')

    const reg = await navigator.serviceWorker.ready
    let sub = await reg.pushManager.getSubscription()
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey)
      })
    }

    const json = sub.toJSON()
    await supabase.rpc('save_push_subscription', {
      p_endpoint: json.endpoint,
      p_p256dh:   json.keys.p256dh,
      p_auth:     json.keys.auth
    })
    return sub
  }

  async function isSubscribed() {
    if (!isSupported) return false
    const reg = await navigator.serviceWorker.ready
    const sub = await reg.pushManager.getSubscription()
    return !!sub
  }

  return { isSupported, getPermission, subscribe, isSubscribed }
}
