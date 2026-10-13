import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Admin-initiated full account erasure (GDPR). The caller must be an app_admin.
// Flow: verify caller is admin (their JWT) → admin_erase_user(target) runs the
// block checks + wipes all public data → auth.admin.deleteUser(target) removes the
// login. Mirrors the self-service delete-account function but for a different user.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authHeader = req.headers.get('authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    const URL_ = Deno.env.get('SUPABASE_URL')!
    const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
    const SVC  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // 1. Identify caller + confirm they are an app admin
    const userClient = createClient(URL_, ANON, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

    const { data: isAdmin, error: adminErr } = await userClient.rpc('is_app_admin')
    if (adminErr) return json({ error: adminErr.message }, 400)
    if (!isAdmin) return json({ error: 'Admin only' }, 403)

    // 2. Target
    const body = await req.json().catch(() => ({}))
    const targetId = (body.user_id || '').trim()
    if (!targetId) return json({ error: 'user_id required' }, 400)
    if (targetId === user.id) return json({ error: "Use Profile → Delete account to delete your own account." }, 400)

    const admin = createClient(URL_, SVC)

    // 3. Erase public data (runs block checks; returns block reason if not deletable)
    const { data: eraseResult, error: eraseErr } = await admin.rpc('admin_erase_user', { p_user_id: targetId })
    if (eraseErr) return json({ error: eraseErr.message }, 400)
    if (!eraseResult?.can_delete) {
      return json({ error: eraseResult?.details ?? 'This user cannot be deleted yet.', reason: eraseResult?.reason }, 422)
    }

    // 4. Remove the auth.users row
    const { error: delErr } = await admin.auth.admin.deleteUser(targetId)
    if (delErr) {
      console.error('admin auth deletion failed:', delErr.message)
      return json({ error: 'Data removed but auth deletion failed. Contact support.' }, 500)
    }

    return json({ ok: true })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
