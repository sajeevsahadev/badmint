import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Approve a tournament registration (respects capacity via approve_registration)
// and email the team a confirmation with the admin's (editable) message.
// Deployed with verify_jwt = true.
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
const esc = (s: string) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const URL = Deno.env.get('SUPABASE_URL')!
    const ANON = Deno.env.get('SUPABASE_ANON_KEY')!
    const SVC = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const RESEND = Deno.env.get('RESEND_API_KEY')
    const authHeader = req.headers.get('authorization') ?? ''
    if (!authHeader) return json({ error: 'Unauthorized' }, 401)

    const { reg_id, message } = await req.json()
    if (!reg_id) return json({ error: 'Missing reg_id' }, 400)

    // Approve as the calling user (approve_registration checks manage rights + capacity).
    const userClient = createClient(URL, ANON, { global: { headers: { Authorization: authHeader } } })
    const { error: aerr } = await userClient.rpc('approve_registration', { p_reg_id: reg_id })
    if (aerr) return json({ error: aerr.message }, 400)

    // Email the team (service role → read contacts).
    const admin = createClient(URL, SVC)
    const { data: reg } = await admin
      .from('tournament_registrations')
      .select('team_name, contact_email, player_a_email, player_b_email, tournament_id')
      .eq('id', reg_id).maybeSingle()
    const to = [...new Set([reg?.contact_email, reg?.player_a_email, reg?.player_b_email]
      .filter((e) => e && /.+@.+\..+/.test(e)))] as string[]
    let emailed = false
    if (RESEND && reg && to.length) {
      const { data: tour } = await admin.from('tournaments').select('name, slug').eq('id', reg.tournament_id).maybeSingle()
      const tname = tour?.name ?? 'the tournament'
      const link = `https://badminton360.app/tournaments/${tour?.slug ?? reg.tournament_id}`
      const msg = (message && String(message).trim()) || `Your request to ${tname} is approved.`
      const html = `<div style="font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:auto">
        <h2 style="color:#0f172a">✅ You're in — ${esc(tname)}</h2>
        <p><b>Team:</b> ${esc(reg.team_name)}</p>
        <p style="background:#ecfdf5;border:1px solid #a7f3d0;border-radius:10px;padding:12px 14px">${esc(msg)}</p>
        <p><a href="${link}" style="background:#00b4d8;color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none">View the tournament →</a></p>
        <p style="color:#94a3b8;font-size:12px">Badminton 360 · badminton360.app</p></div>`
      try {
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: 'Badminton 360 <hello@badminton360.app>', to, subject: `Confirmed — ${tname}`, html }),
        })
        emailed = r.ok
      } catch { /* ignore email errors */ }
    }
    return json({ ok: true, emailed, recipients: to.length })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
