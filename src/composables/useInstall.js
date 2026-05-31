import { ref } from 'vue'

const deferredPrompt = ref(null)
const canInstall     = ref(false)
const isInstalled    = ref(false)

const ua    = typeof navigator !== 'undefined' ? navigator.userAgent : ''
const isIOS = /iPad|iPhone|iPod/.test(ua) && !('MSStream' in window)

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
  return { canInstall, isIOS, isInstalled, promptInstall }
}
