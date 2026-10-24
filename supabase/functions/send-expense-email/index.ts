import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

async function hmacHex(msg: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg))
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, "0")).join("")
}

const esc = (s: string) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

function buildExpenseHtml(opts: {
  title: string; amount: number; paid_by_name: string; participant_count: number;
  club_name: string; currency: string; share: number; unsub: string;
}): string {
  const { title, amount, paid_by_name, participant_count, club_name, currency, share, unsub } = opts
  const fmt = (n: number) => Number(n).toFixed(2)
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>New expense — ${esc(title)}</title></head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:480px;" cellpadding="0" cellspacing="0">
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:13px;font-weight:600;color:rgba(168,85,247,.8);letter-spacing:2px;text-transform:uppercase;margin-bottom:6px;">New Expense</div>
    <div style="font-size:22px;font-weight:800;color:#a855f7;letter-spacing:-0.5px;">💰 ${esc(title)}</div>
    <div style="font-size:12px;color:rgba(255,255,255,.45);margin-top:6px;">${esc(club_name)}</div>
  </td></tr>
  <tr><td style="background:#fff;padding:32px;border-radius:0 0 16px 16px;">
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
      <tr>
        <td style="background:#faf5ff;border:1px solid #e9d5ff;border-radius:12px;padding:20px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr><td style="padding-bottom:12px;border-bottom:1px solid #e9d5ff;">
              <div style="font-size:12px;color:#7c3aed;font-weight:600;text-transform:uppercase;letter-spacing:1px;margin-bottom:4px;">Total</div>
              <div style="font-size:30px;font-weight:900;color:#0f172a;">${esc(currency)} ${fmt(amount)}</div>
            </td></tr>
            <tr><td style="padding-top:12px;">
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr><td style="font-size:13px;color:#475569;padding-bottom:6px;"><strong style="color:#0f172a;">Paid by:</strong> ${esc(paid_by_name)}</td></tr>
                <tr><td style="font-size:13px;color:#475569;padding-bottom:6px;"><strong style="color:#0f172a;">Split between:</strong> ${participant_count} ${participant_count === 1 ? "person" : "people"}</td></tr>
                <tr><td style="font-size:13px;color:#475569;"><strong style="color:#0f172a;">Your share:</strong>
                  <span style="font-weight:700;color:#7c3aed;">${esc(currency)} ${fmt(share)}</span></td></tr>
              </table>
            </td></tr>
          </table>
        </td>
      </tr>
    </table>
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;">
    <tr><td align="center">
      <a href="https://badminton360.app/splits" style="display:inline-block;background:linear-gradient(135deg,#a855f7,#7c3aed);color:#fff;font-size:14px;font-weight:700;text-decoration:none;padding:13px 32px;border-radius:12px;letter-spacing:.3px;">View Split Pay →</a>
    </td></tr>
    </table>
    <p style="margin:0;font-size:12px;color:#94a3b8;text-align:center;line-height:1.6;">Check the Balance tab in Split Pay to see who owes what.</p>
  </td></tr>
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;line-height:1.8;">
      <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;">Badminton 360</a>
      &nbsp;·&nbsp;
      <a href="${unsub}" style="color:#0099bb;text-decoration:none;">Unsubscribe</a>
      &nbsp;·&nbsp;
      <a href="https://badminton360.app/settings/email" style="color:#0099bb;text-decoration:none;">Email preferences</a>
    </p>
  </td></tr>
</table>
</td></tr>
</table>
</body></html>`
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  try {
    const authHeader = req.headers.get("authorization")
    if (!authHeader) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const SUPABASE_URL         = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY    = Deno.env.get("SUPABASE_ANON_KEY")!
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const RESEND_API_KEY       = Deno.env.get("RESEND_API_KEY")!

    const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: authErr } = await anonClient.auth.getUser()
    if (authErr || !user) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const { expense_id } = await req.json()
    if (!expense_id) return new Response(JSON.stringify({ error: "expense_id required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Server-authoritative: who's a participant, their share, and who may be emailed.
    const { data: digest, error: digErr } = await admin.rpc("get_expense_email_recipients", { p_expense_id: expense_id })
    if (digErr) return new Response(JSON.stringify({ error: digErr.message }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    if (!digest) return new Response(JSON.stringify({ ok: true, sent: 0 }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const recipients = (digest.recipients ?? []) as { email: string; name: string; share: number }[]
    let sent = 0
    const errors: string[] = []

    for (const r of recipients) {
      const unsub = `${SUPABASE_URL}/functions/v1/unsubscribe?e=${encodeURIComponent(r.email)}&t=${await hmacHex(r.email.toLowerCase(), SUPABASE_SERVICE_KEY)}`
      const html = buildExpenseHtml({
        title: digest.title, amount: Number(digest.amount),
        paid_by_name: digest.paid_name ?? "Unknown",
        participant_count: Number(digest.participant_count) || recipients.length,
        club_name: digest.club_name ?? "Your Club",
        currency: digest.currency ?? "AED",
        share: Number(r.share),
        unsub,
      })
      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Badminton 360 <hello@badminton360.app>",
          to: [r.email], subject: `💰 New expense added — ${digest.title}`, html,
          headers: { "List-Unsubscribe": `<${unsub}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
        }),
      })
      if (resp.ok) sent++
      else errors.push(`${r.email}: ${await resp.text()}`)
    }

    return new Response(JSON.stringify({ ok: true, sent, participants: recipients.length, errors }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
