import { ref } from 'vue'
import { supabase } from '../lib/supabase'
const user = ref(null)
const ready = ref(false)
supabase.auth.getSession().then(({ data }) => { user.value = data.session?.user ?? null; ready.value = true })
supabase.auth.onAuthStateChange((_e, session) => { user.value = session?.user ?? null })
export function useAuth() {
  const signInWithGoogle = () => supabase.auth.signInWithOAuth({
    provider: 'google', options: { redirectTo: window.location.origin } })
  const signOut = () => supabase.auth.signOut()
  return { user, ready, signInWithGoogle, signOut }
}
