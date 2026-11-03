// Kicks off real AI analysis: verifies the caller can manage the video, marks it 'analyzing',
// and dispatches it to the Modal GPU worker. The worker calls finalize_analysis()/fail_analysis()
// when done. Until MODAL_ANALYZE_URL + ANALYZE_SHARED_SECRET are set it returns 503 so the client
// can fall back to sample analysis.
//
// Secrets (set when Modal is ready): MODAL_ANALYZE_URL, ANALYZE_SHARED_SECRET.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const MODAL_URL = Deno.env.get('MODAL_ANALYZE_URL') ?? ''
const SECRET    = Deno.env.get('ANALYZE_SHARED_SECRET') ?? ''

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, 'content-type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const jwt = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    if (!jwt) return json({ error: 'unauthorized' }, 401)
    const supa = createClient(SUPA_URL, SERVICE)
    const { data: u } = await supa.auth.getUser(jwt)
    if (!u?.user) return json({ error: 'unauthorized' }, 401)
    const userId = u.user.id

    const { video_id } = await req.json()
    if (!video_id) return json({ error: 'bad request' }, 400)

    const { data: vid } = await supa.from('match_videos')
      .select('club_id, uploaded_by, tag_status').eq('id', video_id).maybeSingle()
    if (!vid) return json({ error: 'not found' }, 404)

    let ok = vid.uploaded_by === userId
    if (!ok) {
      const { data: mem } = await supa.from('club_members')
        .select('role').eq('club_id', vid.club_id).eq('user_id', userId).maybeSingle()
      ok = !!mem && (mem.role === 'owner' || mem.role === 'manager')
    }
    if (!ok) {
      const { data: adm } = await supa.from('app_roles')
        .select('role').eq('user_id', userId).eq('role', 'app_admin').maybeSingle()
      ok = !!adm
    }
    if (!ok) return json({ error: 'forbidden' }, 403)

    // Engine not wired yet → let the client fall back to sample analysis. Status is untouched.
    if (!MODAL_URL || !SECRET) return json({ error: 'engine_not_configured' }, 503)

    await supa.from('match_videos').update({ status: 'analyzing', error: null }).eq('id', video_id)

    // Dispatch (fire-and-forget on the worker side; it writes results + sets status when done).
    const resp = await fetch(MODAL_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-analyze-secret': SECRET },
      body: JSON.stringify({ video_id, secret: SECRET }),
    })
    if (!resp.ok) {
      const t = await resp.text()
      await supa.from('match_videos').update({ status: 'failed', error: `dispatch ${resp.status}` }).eq('id', video_id)
      return json({ error: 'dispatch_failed', detail: t.slice(0, 200) }, 502)
    }
    return json({ status: 'analyzing' })
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
