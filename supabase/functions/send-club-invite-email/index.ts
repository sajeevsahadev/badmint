import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Sent when a manager links a guest player to an email that has NO account yet.
// Tells that address they've been added to the club and to sign in with this Gmail
// to claim the profile (their pending link auto-attaches on first sign-in). Includes
// the 7-day /join?token= shortcut when one was generated.
//
// Authz: only a manager/admin of the club may trigger it (get_club_invite_notice
// raises otherwise) — so a logged-in user can't spam "you've been added to X" mails.
// Respects the email_suppression list and carries a no-login unsubscribe link.
// verify_jwt=true (called from the app by the linking manager); work via service role.

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

function html(playerName: string, clubName: string, email: string, joinUrl: string, unsub: string): string {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Join ${esc(clubName)}</title></head>
<body style="margin:0;background:#eef4ff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:18px">
    <div style="font-size:26px;font-weight:800;background:linear-gradient(90deg,#00b4d8,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent">Badminton 360</div>
    <div style="font-size:11px;letter-spacing:1px;color:#64748b;text-transform:uppercase">Your Club · Your Game · One App</div>
  </div>
  <div style="background:#fff;border-radius:18px;padding:26px 22px;box-shadow:0 8px 30px rgba(15,23,42,.08)">
    <h1 style="font-size:20px;margin:0 0 6px">You've been added to ${esc(clubName)}! 🏸</h1>
    <p style="font-size:14px;color:#475569;margin:0 0 16px;line-height:1.6">
      Hi ${esc(playerName)}, your manager added you to <b>${esc(clubName)}</b> on Badminton 360 —
      the smart ranking app for badminton teams. Sign in with <b>${esc(email)}</b> and your player
      profile, Elo ranking and match history link to your account automatically — no approval needed.</p>
    <div style="text-align:center;margin:6px 0 4px">
      <a href="${joinUrl}" style="display:inline-block;background:linear-gradient(90deg,#00b4d8,#8b5cf6);color:#fff;text-decoration:none;font-weight:700;padding:13px 26px;border-radius:12px;font-size:15px">Join ${esc(clubName)} →</a>
    </div>
    <p style="text-align:center;font-size:12px;color:#94a3b8;margin:14px 0 0">
      Just sign in at <a href="${APP}/login" style="color:#0891b2">badminton360.app</a> with ${esc(email)} and you're in.</p>
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

    const { club_id, player_id, email, token } = await req.json().catch(() => ({}))
    if (!club_id || !player_id || !email) return json({ error: 'club_id, player_id, email required' }, 400)
    const to = String(email).toLowerCase().trim()

    // Authz + club/player names in one shot (RPC raises if caller isn't manager/admin).
    const { data: notice, error: nErr } = await userClient.rpc('get_club_invite_notice', {
      p_club_id: club_id, p_player_id: player_id,
    })
    if (nErr || !notice?.club_name) return json({ error: nErr?.message ?? 'Not authorized' }, 403)

    // Respect unsubscribes.
    const admin = createClient(URL_, SVC)
    const { data: supp } = await admin.from('email_suppression').select('email').eq('email', to).maybeSingle()
    if (supp) return json({ ok: true, sent: 0 })   // opted out

    const joinUrl = token ? `${APP}/join?token=${encodeURIComponent(token)}` : `${APP}/login`
    const unsub   = `${URL_}/functions/v1/unsubscribe?e=${encodeURIComponent(to)}&t=${await hmacHex(to, SVC)}`
    if (!RESEND) return json({ ok: true, sent: 0 })
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Badminton 360 <hello@badminton360.app>',
        to: [to], subject: `🏸 You've been added to ${notice.club_name}`,
        html: html(notice.player_name ?? 'there', notice.club_name, to, joinUrl, unsub),
        headers: { 'List-Unsubscribe': `<${unsub}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
      }),
    })
    return json({ ok: r.ok, sent: r.ok ? 1 : 0 })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
