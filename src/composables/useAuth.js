import { ref } from 'vue'
import { supabase } from '../lib/supabase'
const user = ref(null)
const ready = ref(false)
supabase.auth.getSession().then(({ data }) => { user.value = data.session?.user ?? null; ready.value = true })
// Store subscription — Supabase v2 returns { data: { subscription } }
const { data: { subscription: _authSub } } = supabase.auth.onAuthStateChange((_e, session) => {
  user.value = session?.user ?? null
})
export function useAuth() {
  const signInWithGoogle = () => supabase.auth.signInWithOAuth({
    provider: 'google', options: { redirectTo: window.location.origin } })
  // Sign in with Apple — required by App Store Guideline 4.8 since we offer
  // Google sign-in. Works once the Apple provider is enabled in Supabase Auth.
  const signInWithApple = () => supabase.auth.signInWithOAuth({
    provider: 'apple', options: { redirectTo: window.location.origin } })
  const signOut = () => supabase.auth.signOut()
  return { user, ready, signInWithGoogle, signInWithApple, signOut }
}
