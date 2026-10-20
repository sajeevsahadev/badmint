import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Daily match-day digest — one email per member at noon (Asia/Dubai) summarising
// the matches their club recorded that day. Replaces the old per-match email.
// Invoked by pg_cron (08:00 UTC = 12:00 Dubai). Recipients are pre-filtered by
// get_today_match_digests (member + match_digest pref on + not deactivated/
// suppressed). Carries a one-click, no-login Unsubscribe link. verify_jwt=true;
// work runs under the service role.

const RESEND = Deno.env.get('RESEND_API_KEY')
const URL_   = Deno.env.get('SUPABASE_URL')!
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
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(msg))
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('')
}
async function unsubUrl(email: string): Promise<string> {
  return `${URL_}/functions/v1/unsubscribe?e=${encodeURIComponent(email)}&t=${await hmacHex(email.toLowerCase(), SVC)}`
}

interface Side { side: string; score: number; is_winner: boolean; players: string[] }
interface Match { display_name: string | null; sides: Side[] }

function matchRow(m: Match): string {
  const a = m.sides.find((s) => s.side === 'A') || m.sides[0]
  const b = m.sides.find((s) => s.side === 'B') || m.sides[1]
  const names = (s?: Side) => (s?.players || []).map(esc).join(' &amp; ') || '—'
  const w = (s?: Side) => (s?.is_winner ? 'color:#16a34a;font-weight:800' : 'color:#0f172a')
  return `<tr style="border-bottom:1px solid #f1f5f9">
    <td style="padding:9px 10px;font-size:13px;${w(a)}">${names(a)}</td>
    <td style="padding:9px 6px;text-align:center;font-weight:800;color:#0f172a;white-space:nowrap">${a?.score ?? ''}–${b?.score ?? ''}</td>
    <td style="padding:9px 10px;font-size:13px;text-align:right;${w(b)}">${names(b)}</td>
  </tr>`
}

function digestHtml(name: string, clubName: string, dateLabel: string, matches: Match[], unsub: string): string {
  const rows = matches.map(matchRow).join('')
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Today's matches</title></head>
<body style="margin:0;background:#eef4ff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a">
<div style="max-width:540px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:16px">
    <div style="font-size:24px;font-weight:800;background:linear-gradient(90deg,#00b4d8,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent">Badminton 360</div>
    <div style="font-size:11px;letter-spacing:1px;color:#64748b;text-transform:uppercase">${esc(clubName)} · ${esc(dateLabel)}</div>
  </div>
  <div style="background:#fff;border-radius:18px;padding:22px;box-shadow:0 8px 30px rgba(15,23,42,.08)">
    <h1 style="font-size:19px;margin:0 0 4px">🏸 Today's matches</h1>
    <p style="font-size:13px;color:#475569;margin:0 0 16px">Hi ${esc(name)}, here's what was played in <b>${esc(clubName)}</b> today — ${matches.length} match${matches.length === 1 ? '' : 'es'}. Winners in green.</p>
    <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden">${rows}</table>
    <div style="text-align:center;margin:20px 0 4px">
      <a href="${APP}/dashboard" style="display:inline-block;background:linear-gradient(90deg,#00b4d8,#8b5cf6);color:#fff;text-decoration:none;font-weight:700;padding:12px 26px;border-radius:12px;font-size:14px">View full leaderboard →</a>
    </div>
  </div>
  <p style="text-align:center;color:#94a3b8;font-size:11px;margin-top:16px;line-height:1.7">
    Daily match summary from Badminton 360.<br>
    <a href="${unsub}" style="color:#0891b2">Unsubscribe</a> ·
    <a href="${APP}/settings/email" style="color:#0891b2">Email preferences</a>
  </p>
</div></body></html>`
}

async function sendEmail(to: string, subject: string, html: string, unsub: string): Promise<boolean> {
  if (!RESEND) return false
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: 'Badminton 360 <hello@badminton360.app>', to: [to], subject, html,
      headers: { 'List-Unsubscribe': `<${unsub}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
    }),
  })
  return r.ok
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const u = new URL(req.url)
    const dry = u.searchParams.get('dry') === '1'
    // "Today" in Asia/Dubai, overridable with ?day=YYYY-MM-DD
    const day = u.searchParams.get('day') ||
      new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dubai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
    const dateLabel = new Date(day + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'long' })

    const admin = createClient(URL_, SVC)
    const { data: clubs, error } = await admin.rpc('get_today_match_digests', { p_day: day })
    if (error) return json({ error: error.message }, 500)

    let sent = 0, failed = 0, clubsWithMatches = 0, recipients = 0
    for (const c of (clubs ?? [])) {
      const matches = (c.matches ?? []) as Match[]
      const recips = (c.recipients ?? []) as { email: string; name: string }[]
      if (!matches.length || !recips.length) continue
      clubsWithMatches++
      recipients += recips.length
      if (dry) continue
      for (const r of recips) {
        const unsub = await unsubUrl(r.email)
        const html = digestHtml(r.name, c.club_name, dateLabel, matches, unsub)
        const ok = await sendEmail(r.email, `🏸 ${matches.length} match${matches.length === 1 ? '' : 'es'} today — ${c.club_name}`, html, unsub)
        if (ok) sent++; else failed++
      }
    }
    return json({ ok: true, dry, day, clubs: clubsWithMatches, recipients, sent, failed })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
