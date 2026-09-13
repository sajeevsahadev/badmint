import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Onboarding email lifecycle dispatcher — invoked daily by pg_cron. Sends the
// day-2 and monthly "you haven't created a club yet" nudges to eligible users
// (see get_pending_nudges), then logs each send so it never repeats. Access is
// gated by Supabase verify_jwt=true; the actual work uses the service role.

const RESEND = Deno.env.get('RESEND_API_KEY')
const URL_  = Deno.env.get('SUPABASE_URL')!
const SVC   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

const APP = 'https://badminton360.app'
const first = (name: string) => (name && name.trim() ? name.trim().split(/\s+/)[0] : 'there')

// Shared shell so both nudges look like the welcome email.
function shell(inner: string) {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Badminton 360</title></head>
<body style="margin:0;background:#eef4ff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a">
<div style="max-width:520px;margin:0 auto;padding:24px 16px">
  <div style="text-align:center;margin-bottom:18px">
    <div style="font-size:26px;font-weight:800;background:linear-gradient(90deg,#00b4d8,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent">Badminton 360</div>
    <div style="font-size:11px;letter-spacing:1px;color:#64748b;text-transform:uppercase">Your Club · Your Game · One App</div>
  </div>
  <div style="background:#fff;border-radius:18px;padding:26px 22px;box-shadow:0 8px 30px rgba(15,23,42,.08)">
    ${inner}
  </div>
  <p style="text-align:center;color:#94a3b8;font-size:11px;margin-top:16px;line-height:1.6">
    You're getting this because you signed up for Badminton 360.<br>
    Manage email preferences in the app · <a href="mailto:hello@badminton360.app" style="color:#0891b2">hello@badminton360.app</a>
  </p>
</div></body></html>`
}
function button(href: string, label: string) {
  return `<a href="${href}" style="display:inline-block;background:linear-gradient(90deg,#00b4d8,#8b5cf6);color:#fff;text-decoration:none;font-weight:700;padding:13px 26px;border-radius:12px;font-size:15px">${label}</a>`
}
function step(emoji: string, title: string, body: string) {
  return `<tr><td style="padding:8px 0;vertical-align:top;width:34px;font-size:20px">${emoji}</td>
    <td style="padding:8px 0"><b style="font-size:14px">${title}</b><br>
    <span style="font-size:13px;color:#475569">${body}</span></td></tr>`
}

function day2Html(name: string) {
  return shell(`
    <h1 style="font-size:20px;margin:0 0 6px">Ready to start your club, ${first(name)}? 🏸</h1>
    <p style="font-size:14px;color:#475569;margin:0 0 16px;line-height:1.6">
      You're one step away. Setting up your badminton group takes under 2 minutes — here's the whole flow:</p>
    <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
      ${step('🏟️', 'Create your club', 'Name it, tap Create — done. Your group is live instantly.')}
      ${step('📲', 'Invite your crew', 'Share one link on WhatsApp. Everyone joins with Google in a tap.')}
      ${step('🎯', 'Record matches', 'Pick 4 players, enter the score — Elo ratings update automatically.')}
      ${step('💰', 'Split the payments', 'Court fees split fairly with Split Pay + a shared Wallet. No more chasing.')}
    </table>
    <div style="text-align:center;margin:6px 0 4px">${button(APP + '/manage', 'Create my club →')}</div>
    <p style="text-align:center;font-size:12px;color:#94a3b8;margin:14px 0 0">
      Thousands of badminton players already track their games here.
      Need a hand? <a href="${APP}/dashboard?guide=1" style="color:#0891b2">See the app guide →</a></p>`)
}
function monthlyHtml(name: string) {
  return shell(`
    <h1 style="font-size:20px;margin:0 0 6px">Still here whenever you're ready, ${first(name)} 🏸</h1>
    <p style="font-size:14px;color:#475569;margin:0 0 16px;line-height:1.6">
      Your Badminton 360 account is all set — you just haven't created a club yet.
      Whenever your group is ready to ditch the WhatsApp scorekeeping, it's 2 minutes to set up:</p>
    <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
      ${step('🏆', 'Live Elo rankings', 'Settle "who\'s best" for good — updated after every match.')}
      ${step('💰', 'Fair cost splitting', 'Split court fees automatically and keep a shared wallet.')}
      ${step('📅', 'Schedule & polls', 'Plan match days, see who\'s coming, share a poll link.')}
    </table>
    <div style="text-align:center;margin:6px 0 4px">${button(APP + '/manage', 'Create my club →')}</div>
    <p style="text-align:center;font-size:12px;color:#94a3b8;margin:14px 0 0">
      Not sure where to start? <a href="${APP}/dashboard?guide=1" style="color:#0891b2">Open the app guide →</a>
      — it walks you through the whole thing.</p>`)
}

function welcomeHtml(name: string) {
  return shell(`
    <h1 style="font-size:20px;margin:0 0 6px">Welcome to Badminton 360, ${first(name)}! 🏸</h1>
    <p style="font-size:14px;color:#475569;margin:0 0 16px;line-height:1.6">
      You're in! Badminton 360 is the free, all-in-one home for your badminton crew — everything in one app:</p>
    <table style="width:100%;border-collapse:collapse;margin-bottom:20px">
      ${step('🏆', 'Live Elo rankings', 'Record matches and settle who is really the best.')}
      ${step('💰', 'Split Pay + Wallet', 'Divide court fees fairly and pre-fund a shared pool.')}
      ${step('📅', 'Schedule & polls', 'Plan match days and see who is coming.')}
      ${step('🥇', 'Tournaments', 'Run a proper bracket whenever you are ready.')}
    </table>
    <div style="text-align:center;margin:6px 0 4px">${button(APP, 'Open Badminton 360 →')}</div>
    <p style="text-align:center;font-size:12px;color:#94a3b8;margin:14px 0 0">
      New here? <a href="${APP}/dashboard?guide=1" style="color:#0891b2">Take the 2-minute app guide →</a></p>`)
}

async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  if (!RESEND) return false
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: 'Badminton 360 <hello@badminton360.app>', to: [to], subject, html }),
  })
  return r.ok
}

// Access is gated by Supabase verify_jwt=true (a valid project key is required);
// repeated calls are harmless because every send is logged and never repeats
// within its window (get_pending_nudges filters on the log).
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const reqUrl = new URL(req.url)

    // ?preview=<owner-email> sends one of each template to the owner for review.
    // Restricted to the owner address so it can never mail an arbitrary recipient;
    // does not touch lifecycle_email_log.
    const previewTo = reqUrl.searchParams.get('preview')
    if (previewTo) {
      const OWNER = 'sajeevsahadev@gmail.com'
      if (previewTo !== OWNER) return json({ error: 'preview restricted to owner' }, 403)
      const results = {
        welcome: await sendEmail(OWNER, '[Preview] Welcome to Badminton 360 🏸',            welcomeHtml('Sajeev')),
        day2:    await sendEmail(OWNER, '[Preview] Ready to start your badminton club? 🏸',  day2Html('Sajeev')),
        monthly: await sendEmail(OWNER, '[Preview] Your badminton club is 2 minutes away 🏸', monthlyHtml('Sajeev')),
      }
      return json({ ok: true, preview: true, sentTo: OWNER, results })
    }

    // ?dry=1 renders + counts without sending or logging (safe pipeline check).
    const dry = reqUrl.searchParams.get('dry') === '1'
    const admin = createClient(URL_, SVC)
    const { data: targets, error } = await admin.rpc('get_pending_nudges')
    if (error) return json({ error: error.message }, 500)

    let sent = 0, failed = 0
    const byKind: Record<string, number> = {}
    for (const t of (targets ?? [])) {
      let subject: string, html: string
      if (t.kind === 'welcome')      { subject = 'Welcome to Badminton 360 🏸';               html = welcomeHtml(t.name) }
      else if (t.kind === 'day2')    { subject = 'Ready to start your badminton club? 🏸';     html = day2Html(t.name) }
      else                           { subject = 'Your badminton club is 2 minutes away 🏸';   html = monthlyHtml(t.name) }
      byKind[t.kind] = (byKind[t.kind] ?? 0) + 1
      if (dry) { void subject; void html; continue }   // render only, no send
      const ok = await sendEmail(t.email, subject, html)
      if (ok) { await admin.rpc('log_lifecycle_email', { p_user_id: t.user_id, p_kind: t.kind }); sent++ }
      else failed++
    }
    return json({ ok: true, dry, considered: targets?.length ?? 0, byKind, sent, failed })
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})
