<script setup>
// Subscription & billing (Phase 2). Shows the current plan and available plans. Card payments
// are not wired yet (provider + company registration pending) — AI access today is via the
// early-access list, so the page points there.
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../lib/supabase'
import { useEntitlements } from '../../composables/useEntitlements'
import PageHeader from '../../components/PageHeader.vue'

const router = useRouter()
const { hasEarlyAccess, loadEntitlements } = useEntitlements()

const current = ref(null)
const plans   = ref([])
const loading = ref(true)

onMounted(async () => {
  await loadEntitlements()
  const [{ data: sub }, { data: pl }] = await Promise.all([
    supabase.rpc('get_my_subscription'),
    supabase.rpc('get_subscription_plans'),
  ])
  current.value = (sub && sub[0]) || null
  plans.value = pl ?? []
  loading.value = false
})

const money = (c, cur) => `${(c / 100).toFixed(0)} ${cur || 'AED'}`
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 pb-28 pt-4">
    <PageHeader icon="💳" title="Subscription"
      subtitle="Your plan and what's included. Premium unlocks AI Match Analysis." />

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading…</div>

    <div v-if="!loading">
      <!-- Current plan -->
      <div class="card p-4 mb-4">
        <div class="text-xs font-bold uppercase tracking-wide text-slate-500 mb-1">Current plan</div>
        <div class="flex items-center justify-between">
          <div>
            <div class="text-lg font-bold text-slate-800">{{ current?.plan_name || 'Free' }}</div>
            <div class="text-xs text-slate-400">
              <span v-if="current">{{ current.status }}<span v-if="current.current_period_end"> · renews {{ new Date(current.current_period_end).toLocaleDateString() }}</span></span>
              <span v-else>No paid plan</span>
            </div>
          </div>
          <span v-if="hasEarlyAccess" class="badge-pending">✨ AI Early Access</span>
        </div>
      </div>

      <!-- Plans -->
      <div class="grid gap-3 sm:grid-cols-3 mb-4">
        <div v-for="p in plans" :key="p.code" class="card p-4 text-center"
          :class="current?.plan_code === p.code ? 'card-neon' : ''">
          <div class="font-display font-bold text-slate-800">{{ p.name }}</div>
          <div class="text-neon font-bold text-lg my-1">{{ p.price_cents ? money(p.price_cents, p.currency) : 'Free' }}
            <span v-if="p.price_cents" class="text-xs text-slate-400 font-normal">/mo</span>
          </div>
          <div class="text-xs text-slate-500">{{ p.features?.ai_analysis ? '✨ AI Match Analysis' : 'Core features' }}</div>
          <div v-if="p.features?.analyses_per_month" class="text-[11px] text-slate-400 mt-0.5">
            {{ p.features.analyses_per_month }} analyses / month
          </div>
        </div>
      </div>

      <!-- Billing — coming soon -->
      <div class="card card-amber p-4">
        <div class="text-sm font-bold text-slate-800 mb-1">💳 Card payments — coming soon</div>
        <p class="text-sm text-slate-600">
          Online card billing is being set up. In the meantime, AI Match Analysis is rolling out through
          the <b>early-access programme</b>.
        </p>
        <button class="btn-primary w-full py-2.5 text-sm mt-3" @click="router.push('/ai')">
          {{ hasEarlyAccess ? 'Open AI Match Analysis' : 'See AI Match Analysis' }}
        </button>
      </div>
    </div>
  </div>
</template>
