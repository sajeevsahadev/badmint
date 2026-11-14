// Kicks off work on the Modal worker:
//   mode 'simple' | 'deep' — creates a NEW analysis version (analysis_runs row; earlier versions are
//                            kept) and dispatches it. Uploader / club manager / app admin only.
//   mode 'both'            — ONE pass over the video that fills a Quick Report version and a Deep
//                            Coaching version together (no second analysis of the same video).
//   mode 'index'           — quick people-detection pass that produces each player's photo.
//                            Any member of the video's club may trigger it.
// Returns 503 until MODAL_ANALYZE_URL + ANALYZE_SHARED_SECRET are set (client falls back to samples).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const SUPA_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const MODAL_URL = Deno.env.get('MODAL_ANALYZE_URL') ?? ''
const SECRET    = Deno.env.get('ANALYZE_SHARED_SECRET') ?? ''
const ENGINE    = 'pose-v2'

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

    const body = await req.json()
    const video_id = body.video_id
    const mode: 'simple' | 'deep' | 'both' | 'index' = body.mode === 'index' ? 'index' : body.mode === 'both' ? 'both'
      : (body.deep || body.mode === 'deep') ? 'deep' : 'simple'
    if (!video_id) return json({ error: 'bad request' }, 400)

    const { data: vid } = await supa.from('match_videos')
      .select('club_id, uploaded_by, index_status').eq('id', video_id).maybeSingle()
    if (!vid) return json({ error: 'not found' }, 404)

    const { data: mem } = await supa.from('club_members')
      .select('role').eq('club_id', vid.club_id).eq('user_id', userId).maybeSingle()
    const { data: adm } = await supa.from('app_roles')
      .select('role').eq('user_id', userId).eq('role', 'app_admin').maybeSingle()
    const canManage = vid.uploaded_by === userId || !!adm || (!!mem && (mem.role === 'owner' || mem.role === 'manager'))
    const canView = canManage || !!mem
    if (mode === 'index' ? !canView : !canManage) return json({ error: 'forbidden' }, 403)

    if (!MODAL_URL || !SECRET) return json({ error: 'engine_not_configured' }, 503)

    let run_id: string | null = null
    let quick_run_id: string | null = null
    if (mode === 'both') {
      const q = await supa.rpc('start_analysis_run',
        { p_video_id: video_id, p_kind: 'simple', p_is_mock: false, p_engine: ENGINE, p_user_id: userId })
      if (q.error) return json({ error: 'could not start run', detail: q.error.message }, 500)
      quick_run_id = q.data as string
      const d = await supa.rpc('start_analysis_run',
        { p_video_id: video_id, p_kind: 'deep', p_is_mock: false, p_engine: ENGINE, p_user_id: userId })
      if (d.error) {
        await supa.rpc('fail_analysis', { p_video_id: video_id, p_error: 'could not start', p_run_id: quick_run_id })
        return json({ error: 'could not start run', detail: d.error.message }, 500)
      }
      run_id = d.data as string
    } else if (mode === 'index') {
      if (vid.index_status === 'indexing') return json({ status: 'indexing' })
      await supa.from('match_videos').update({ index_status: 'indexing' }).eq('id', video_id)
    } else {
      const { data: rid, error: re } = await supa.rpc('start_analysis_run',
        { p_video_id: video_id, p_kind: mode, p_is_mock: false, p_engine: ENGINE, p_user_id: userId })
      if (re) return json({ error: 'could not start run', detail: re.message }, 500)
      run_id = rid as string
    }

    const resp = await fetch(MODAL_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-analyze-secret': SECRET },
      body: JSON.stringify({ video_id, run_id, quick_run_id, mode, user_id: userId, secret: SECRET }),
    })
    if (!resp.ok) {
      const t = await resp.text()
      if (mode === 'index') await supa.from('match_videos').update({ index_status: 'failed' }).eq('id', video_id)
      else if (mode === 'both') {
        await supa.rpc('fail_analysis', { p_video_id: video_id, p_error: `dispatch ${resp.status}`, p_run_id: quick_run_id })
        await supa.rpc('fail_deep', { p_video_id: video_id, p_error: `dispatch ${resp.status}`, p_run_id: run_id })
      } else await supa.rpc(mode === 'deep' ? 'fail_deep' : 'fail_analysis',
        { p_video_id: video_id, p_error: `dispatch ${resp.status}`, p_run_id: run_id })
      return json({ error: 'dispatch_failed', detail: t.slice(0, 200) }, 502)
    }
    return json({ status: mode === 'index' ? 'indexing' : 'analyzing', mode, run_id, quick_run_id })
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500)
  }
})
