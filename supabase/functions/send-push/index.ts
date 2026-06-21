import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'https://esm.sh/web-push@3.6.7'

webpush.setVapidDetails(
  'mailto:sajeevsahadev@gmail.com',
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!
)

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, content-type',
      }
    })
  }

  const { schedule_id, title, body, url } = await req.json()

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  const { data: sched } = await supabase
    .from('club_schedule')
    .select('club_id')
    .eq('id', schedule_id)
    .single()

  if (!sched) return new Response('Not found', { status: 404 })

  const { data: members } = await supabase
    .from('club_members')
    .select('user_id')
    .eq('club_id', sched.club_id)

  const memberIds = (members ?? []).map((m: { user_id: string }) => m.user_id)

  const { data: subs } = await supabase
    .from('push_subscriptions')
    .select('*')
    .in('user_id', memberIds)

  const results = await Promise.allSettled(
    (subs ?? []).map(s =>
      webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth_key } },
        JSON.stringify({ title, body, url, tag: schedule_id })
      ).catch(() => null)
    )
  )

  return new Response(
    JSON.stringify({ sent: results.filter(r => r.status === 'fulfilled').length }),
    { headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } }
  )
})
