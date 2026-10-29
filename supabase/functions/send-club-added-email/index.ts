import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Sent when an admin links a guest player to an existing account: tells that user
// they've been added to the club. Respects the "invites" email pref + deactivation
// + suppression (via get_club_link_notice) and carries a no-login unsubscribe link.
// verify_jwt=true (called from the app by the linking admin); work via service role.

const RESEND = Deno.env.get('RESEND_API_KEY')
const URL_   = Deno.env.get('SUPABASE_URL')!
const ANON   = Deno.env.get('SUPABASE_ANON_KEY')!
const SVC    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const APP    = 'https://badminton360.app'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
const esc = (s: string) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

async function hmacHex(msg: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(msg))
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function html(name: string, clubName: string, unsub: string): string {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Added to ${esc(clubName)}</title></head>
<body style="margin:0;background:#eef4ff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:18px">
    <div style="font-size:26px;font-weight:800;background:linear-gradient(90deg,#00b4d8,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent">Badminton 360</div>
    <div style="font-size:11px;letter-spacing:1px;color:#64748b;text-transform:uppercase">Your Club · Your Game · One App</div>
  </div>
  <div style="background:#fff;border-radius:18px;padding:26px 22px;box-shadow:0 8px 30px rgba(15,23,42,.08)">
    <h1 style="font-size:20px;margin:0 0 6px">You're in ${esc(clubName)}! 🏸</h1>
    <p style="font-size:14px;color:#475569;margin:0 0 16px;line-height:1.6">
      Hi ${esc(name)}, you've been added to <b>${esc(clubName)}</b> on Badminton 360. Your match history,
      Elo ranking and Split Pay are now linked to your account — nothing more to do.</p>
    <div style="text-align:center;margin:6px 0 4px">
      <a href="${APP}/dashboard" style="display:inline-block;background:linear-gradient(90deg,#00b4d8,#8b5cf6);color:#fff;text-decoration:none;font-weight:700;padding:13px 26px;border-radius:12px;font-size:15px">Open ${esc(clubName)} →</a>
    </div>
    <p style="text-align:center;font-size:12px;color:#94a3b8;margin:14px 0 0">See your ranking, record matches and split court fees with your crew.</p>
  </div>
  <p style="text-align:center;color:#94a3b8;font-size:11px;margin-top:16px;line-height:1.7">
    You're getting this because you were added to a club on Badminton 360.<br>
    <a href="${unsub}" style="color:#0891b2">Unsubscribe</a> ·
    <a href="${APP}/settings/email" style="color:#0891b2">Email preferences</a>
  </p>
</div></body></html>`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authHeader = req.headers.get('authorization')
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)
    const userClient = createClient(URL_, ANON, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) return json({ error: 'Unauthorized' }, 401)

    const { player_id } = await req.json().catch(() => ({}))
    if (!player_id) return json({ error: 'player_id required' }, 400)

    const admin = createClient(URL_, SVC)
    const { data: notice } = await admin.rpc('get_club_link_notice', { p_player_id: player_id })
    if (!notice?.email) return json({ ok: true, sent: 0 })   // no email / opted out / suppressed

    const unsub = `${URL_}/functions/v1/unsubscribe?e=${encodeURIComponent(notice.email)}&t=${await hmacHex(String(notice.email).toLowerCase(), SVC)}`
    if (!RESEND) return json({ ok: true, sent: 0 })
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Badminton 360 <hello@badminton360.app>',
        to: [notice.email], subject: `🏸 You've been added to ${notice.club_name}`,
        html: html(notice.name, notice.club_name, unsub),
        headers: { 'List-Unsubscribe': `<${unsub}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
      }),
    })
    return json({ ok: r.ok, sent: r.ok ? 1 : 0 })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
