<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useClub } from '../composables/useClub'
import { useGeo } from '../composables/useGeo'
import { CURRENCIES, suggestCurrency } from '../utils/currency'

const router = useRouter()
const { createClub, loadClubs } = useClub()
const { countryCode, currency: geoCurrency, detectCountry } = useGeo()

const name     = ref('')
const currency = ref('AED')
const busy     = ref(false)
const error    = ref(null)

// Suggest a currency from the creator's location (IP-detected currency first,
// else mapped from the country code). Owner can still change it.
onMounted(async () => {
  await detectCountry()
  currency.value = suggestCurrency(geoCurrency.value, countryCode.value)
})

async function submit() {
  if (!name.value.trim()) return
  busy.value = true; error.value = null
  try {
    await createClub(name.value.trim(), currency.value)
    await loadClubs()
    router.push('/dashboard')
  } catch (e) {
    error.value = e.message
    busy.value = false
  }
}
</script>

<template>
  <div class="max-w-sm mx-auto pt-2 fade-up">

    <!-- Back -->
    <button class="flex items-center gap-1.5 text-sm text-slate-500 hover:text-neon transition mb-6"
      @click="router.back()">
      ‹ Back
    </button>

    <div class="card-neon p-6">
      <div class="text-center mb-6">
        <div class="text-5xl mb-3" style="filter:drop-shadow(0 0 20px rgba(0,229,255,.4))">🏸</div>
        <h1 class="font-display text-2xl font-extrabold gradient-text mb-1">Create a Club</h1>
        <p class="text-sm text-slate-400 leading-relaxed">
          Your club gets its own private leaderboard, players list, and match history.
        </p>
      </div>

      <label class="label">Club Name</label>
      <input v-model="name" class="input mb-4" placeholder="e.g. Court Smashers, Friday Warriors…"
        maxlength="50" @keyup.enter="submit" autofocus />

      <label class="label">Currency</label>
      <select v-model="currency" class="input mb-1.5">
        <option v-for="c in CURRENCIES" :key="c.code" :value="c.code">{{ c.label }}</option>
      </select>
      <p class="text-xs text-slate-500 mb-5">
        Used for Split Pay and fees. Suggested from your location — change it if needed.
      </p>

      <button class="btn-primary w-full py-3.5 text-base"
        :disabled="busy || !name.trim()" @click="submit">
        {{ busy ? 'Creating…' : '➕ Create Club' }}
      </button>

      <p v-if="error" class="mt-3 text-xs text-rose-400 text-center rounded-xl px-3 py-2 bg-rose-500/10">
        {{ error }}
      </p>

      <p class="mt-4 text-center text-xs text-slate-600">
        Already have a club code?
        <RouterLink to="/join" class="text-neon underline ml-1">Join a club →</RouterLink>
      </p>
    </div>
  </div>
</template>
