import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Public, anonymous tournament team registration (Google-Form style).
// Verifies Cloudflare Turnstile when TURNSTILE_SECRET is set, inserts the
// registration via the service role, and emails the tournament admins.
// Deployed with verify_jwt = false.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

async function verifyTurnstile(token: string, ip: string | null): Promise<boolean> {
  const secret = Deno.env.get('TURNSTILE_SECRET')
  if (!secret) return true // not configured yet → skip the check (see pending memory)
  if (!token) return false
  const body = new FormData()
  body.append('secret', secret)
  body.append('response', token)
  if (ip) body.append('remoteip', ip)
  try {
    const r = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body })
    const d = await r.json()
    return !!d.success
  } catch { return false }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const URL = Deno.env.get('SUPABASE_URL')!
    const SVC = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const RESEND = Deno.env.get('RESEND_API_KEY')
    const admin = createClient(URL, SVC)

    const b = await req.json()
    const code = String(b.code ?? '').trim()
    if (!code) return json({ error: 'Missing tournament' }, 400)

    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null
    const okBot = await verifyTurnstile(String(b.turnstile_token ?? ''), ip)
    if (!okBot) return json({ error: 'Bot check failed. Please try again.' }, 400)

    // Resolve the tournament by slug / share_code / id.
    const { data: tour } = await admin
      .from('tournaments').select('id')
      .or(`slug.eq.${code},share_code.eq.${code}`)
      .maybeSingle()
    let tid = tour?.id
    if (!tid) {
      const byId = await admin.from('tournaments').select('id').eq('id', code).maybeSingle()
      tid = byId.data?.id
    }
    if (!tid) return json({ error: 'Tournament not found' }, 404)

    const { data: res, error } = await admin.rpc('insert_public_registration', {
      p_tournament_id: tid, p_team_name: b.team_name ?? null,
      p_a_name: b.a_name ?? '', p_a_phone: b.a_phone ?? null, p_a_email: b.a_email ?? null,
      p_b_name: b.b_name ?? '', p_b_phone: b.b_phone ?? null, p_b_email: b.b_email ?? null,
    })
    if (error) return json({ error: error.message }, 400)

    // Notify the tournament admins (best effort).
    if (RESEND) {
      try {
        const { data: info } = await admin.rpc('get_tournament_admin_emails', { p_tournament_id: tid })
        const emails: string[] = (info?.emails ?? []).filter(Boolean)
        if (emails.length) {
          const tname = info?.name ?? 'your tournament'
          const link = `https://badminton360.app/tournament/${tid}/manage`
          const html = `<div style="font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:auto">
            <h2 style="color:#0f172a">🏸 New tournament registration</h2>
            <p>You have the <b>#${res.sequence}</b> registration for <b>${tname}</b> — awaiting your approval.</p>
            <p><b>Team:</b> ${res.team_name}<br><b>Players:</b> ${b.a_name} &amp; ${b.b_name}</p>
            <p><a href="${link}" style="background:#00b4d8;color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none">Review &amp; approve →</a></p>
            <p style="color:#94a3b8;font-size:12px">Badminton 360 · badminton360.app</p></div>`
          await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              from: 'Badminton 360 <hello@badminton360.app>', to: emails,
              subject: `New registration #${res.sequence} — ${tname}`, html,
            }),
          })
        }
      } catch { /* email failure must not fail the registration */ }
    }
    return json({ ok: true, status: res.status, team_name: res.team_name, sequence: res.sequence })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
