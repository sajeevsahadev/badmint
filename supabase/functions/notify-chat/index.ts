import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'https://esm.sh/web-push@3.6.7'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

webpush.setVapidDetails(
  'mailto:sajeevsahadev@gmail.com',
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!,
)

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!
    const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
    const SERVICE_KEY       = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const authHeader = req.headers.get('authorization') ?? ''
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    // Verify the caller
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

    const { club_id, body } = await req.json()
    if (!club_id || !body) return json({ error: 'Missing fields' }, 400)

    const admin = createClient(SUPABASE_URL, SERVICE_KEY)

    // Caller must be a member of the club they're notifying
    const { data: membership } = await admin
      .from('club_members').select('user_id').eq('club_id', club_id).eq('user_id', user.id).maybeSingle()
    if (!membership) return json({ error: 'Not a member' }, 403)

    const [{ data: club }, { data: profile }, { data: members }] = await Promise.all([
      admin.from('clubs').select('name').eq('id', club_id).single(),
      admin.from('user_profiles').select('nickname, full_name').eq('user_id', user.id).maybeSingle(),
      admin.from('club_members').select('user_id').eq('club_id', club_id),
    ])

    const senderName = profile?.nickname || profile?.full_name || 'Someone'
    const clubName   = club?.name || 'Your club'
    // Notify everyone except the sender
    let recipientIds = (members ?? []).map((m: { user_id: string }) => m.user_id).filter((id: string) => id !== user.id)
    if (!recipientIds.length) return json({ sent: 0 })

    // Respect the per-user "Club chat messages" push preference. push_prefs is
    // a jsonb column; treat a missing key as opted-in, only skip explicit false.
    const { data: prefRows } = await admin
      .from('user_profiles').select('user_id, push_prefs').in('user_id', recipientIds)
    const optedOut = new Set(
      (prefRows ?? [])
        .filter((r: { push_prefs: Record<string, unknown> | null }) => r.push_prefs?.chat_messages === false)
        .map((r: { user_id: string }) => r.user_id),
    )
    recipientIds = recipientIds.filter((id: string) => !optedOut.has(id))
    if (!recipientIds.length) return json({ sent: 0 })

    const { data: subs } = await admin
      .from('push_subscriptions').select('*').in('user_id', recipientIds)

    const preview = String(body).replace(/\s+/g, ' ').trim().slice(0, 120)
    const payload = JSON.stringify({
      title: `💬 ${clubName}`,
      body: `${senderName}: ${preview}`,
      url: '/chat',
      tag: `chat-${club_id}`,   // collapse repeated chat pushes for the same club
    })

    const dead: string[] = []
    const results = await Promise.allSettled(
      (subs ?? []).map(async s => {
        try {
          await webpush.sendNotification(
            { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
            payload,
          )
          return true
        } catch (e) {
          const code = (e as { statusCode?: number }).statusCode
          // 404/410 = subscription gone; 403 = wrong VAPID key. All undeliverable —
          // remove so the table self-heals and future sends are cheaper.
          if (code === 404 || code === 410 || code === 403) dead.push(s.endpoint)
          throw e
        }
      }),
    )
    if (dead.length) {
      await admin.from('push_subscriptions').delete().in('endpoint', dead)
    }
    return json({
      sent: results.filter(r => r.status === 'fulfilled').length,
      pruned: dead.length,
    })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }

  function json(obj: unknown, status = 200) {
    return new Response(JSON.stringify(obj), {
      status, headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }
})
