// Premium-feature entitlements. Phase 1: access is gated by the `early_access` app role
// (admins implicitly have it). Phase 2 will fold in paid subscriptions, so callers should
// keep using `hasEarlyAccess` / `canUseAi` rather than checking roles directly.
import { ref } from 'vue'
import { supabase } from '../lib/supabase'

const roles          = ref([])
const loaded         = ref(false)
const hasEarlyAccess = ref(false)
const isAppAdmin     = ref(false)

export function useEntitlements() {
  async function loadEntitlements(force = false) {
    if (loaded.value && !force) return
    try {
      const { data } = await supabase.rpc('get_my_roles')
      roles.value = data ?? []
      const set = new Set(roles.value.map(r => r.role))
      isAppAdmin.value     = set.has('app_admin')
      hasEarlyAccess.value = set.has('early_access') || set.has('app_admin')
    } catch {
      roles.value = []; hasEarlyAccess.value = false; isAppAdmin.value = false
    }
    loaded.value = true
  }

  function resetEntitlements() {
    loaded.value = false; roles.value = []
    hasEarlyAccess.value = false; isAppAdmin.value = false
  }

  // Alias kept deliberately so Phase 2 can widen it (early access OR active subscription).
  const canUseAi = hasEarlyAccess

  return { roles, loaded, hasEarlyAccess, isAppAdmin, canUseAi, loadEntitlements, resetEntitlements }
}
