import { ref } from 'vue'

// Auto-detected country from the user's internet connection (IP geolocation).
// Cached in localStorage so we only hit the geo API once per device.
const country     = ref(localStorage.getItem('b360_country') || '')
const countryCode = ref(localStorage.getItem('b360_country_code') || '')
let pending = null

function flagEmoji(code) {
  if (!code || code.length !== 2) return '🌍'
  return String.fromCodePoint(...[...code.toUpperCase()].map(c => 0x1f1a5 + c.charCodeAt(0)))
}

async function detect() {
  if (country.value) return
  try {
    const res = await fetch('https://ipapi.co/json/', { signal: AbortSignal.timeout(5000) })
    if (res.ok) {
      const j = await res.json()
      if (j.country_name) {
        country.value     = j.country_name
        countryCode.value = j.country_code || ''
        localStorage.setItem('b360_country', country.value)
        localStorage.setItem('b360_country_code', countryCode.value)
        return
      }
    }
  } catch { /* offline or blocked — fall back to browser locale */ }
  const region = (Intl.DateTimeFormat().resolvedOptions().locale || navigator.language || '').split('-')[1]
  if (region && region.length === 2) {
    try {
      country.value     = new Intl.DisplayNames(['en'], { type: 'region' }).of(region) || ''
      countryCode.value = region.toUpperCase()
    } catch { /* very old browser — leave blank, UI shows Worldwide */ }
  }
}

export function useGeo() {
  function detectCountry() {
    if (!pending) pending = detect()
    return pending
  }
  return { country, countryCode, flagEmoji, detectCountry }
}
