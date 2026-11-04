// Sends a Web Push to the person who ran an analysis, when their report is ready.
// Called by the Modal worker (shared-secret auth) after finalize_analysis(). No user JWT.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'https://esm.sh/web-push@3.6.7'

webpush.setVapidDetails(
  'mailto:sajeevsahadev@gmail.com',
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!,
)

const SECRET = Deno.env.get('ANALYZE_SHARED_SECRET') ?? ''
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey, x-analyze-secret' }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  try {
    const body = await req.json()
    const given = req.headers.get('x-analyze-secret') || body.secret || ''
    if (!SECRET || given !== SECRET) return new Response('forbidden', { status: 403, headers: CORS })

    const video_id = body.video_id
    if (!video_id) return new Response('missing video_id', { status: 400, headers: CORS })

    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const { data: vid } = await supabase.from('match_videos').select('uploaded_by, title').eq('id', video_id).maybeSingle()
    if (!vid?.uploaded_by) return new Response(JSON.stringify({ sent: 0 }), { headers: { ...CORS, 'Content-Type': 'application/json' } })

    const { data: subs } = await supabase.from('push_subscriptions').select('*').eq('user_id', vid.uploaded_by)
    const payload = JSON.stringify({
      title: 'Match analysis ready 🎥',
      body: `${vid.title || 'Your match'} — your coaching report is ready to view.`,
      url: `/ai/video/${video_id}`,
      tag: `analysis-${video_id}`,
    })
    const results = await Promise.allSettled(
      (subs ?? []).map((s: any) =>
        webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } }, payload).catch(() => null)),
    )
    return new Response(JSON.stringify({ sent: results.filter(r => r.status === 'fulfilled').length }),
      { headers: { ...CORS, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...CORS, 'Content-Type': 'application/json' } })
  }
})
