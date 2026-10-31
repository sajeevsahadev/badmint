import { ref } from 'vue'

const deferredPrompt = ref(null)
const canInstall     = ref(false)
const isInstalled    = ref(false)

const ua        = typeof navigator !== 'undefined' ? navigator.userAgent : ''
const isIOS     = /iPad|iPhone|iPod/.test(ua) && !('MSStream' in window)
const isAndroid = /Android/.test(ua)

// Badminton 360 is now published on the Google Play Store (TWA). Android users
// are sent there instead of being prompted to "Add to Home screen". The iOS
// App Store build is still on the way.
const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=app.badminton360.twa'

if (typeof window !== 'undefined') {
  isInstalled.value =
    window.navigator.standalone === true ||
    window.matchMedia('(display-mode: standalone)').matches

  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferredPrompt.value = e
    if (!isInstalled.value) canInstall.value = true
  })

  window.addEventListener('appinstalled', () => {
    canInstall.value    = false
    deferredPrompt.value = null
    isInstalled.value   = true
  })
}

export function useInstall() {
  async function promptInstall() {
    if (!deferredPrompt.value) return
    deferredPrompt.value.prompt()
    const { outcome } = await deferredPrompt.value.userChoice
    if (outcome === 'accepted') {
      canInstall.value    = false
      deferredPrompt.value = null
    }
  }
  return { canInstall, isIOS, isAndroid, isInstalled, promptInstall, PLAY_STORE_URL }
}
