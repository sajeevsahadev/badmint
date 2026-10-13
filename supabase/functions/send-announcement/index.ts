import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

async function hmacHex(msg: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"])
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg))
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, "0")).join("")
}

function textToHtml(body: string): string {
  return body
    .split("\n\n")
    .map(para => `<p style="margin:0 0 14px;font-size:14px;color:#334155;line-height:1.7;">${
      para.trim().replace(/\n/g, "<br>")
    }</p>`)
    .join("")
}

function buildAnnouncementHtml(opts: { subject: string; body: string; unsub: string }): string {
  const { subject, body, unsub } = opts
  const bodyHtml = textToHtml(body)
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${subject}</title></head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:520px;" cellpadding="0" cellspacing="0">
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:12px;font-weight:600;color:rgba(0,180,216,.75);letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">📢 Badminton 360</div>
    <div style="font-size:22px;font-weight:800;color:#ffffff;letter-spacing:-0.5px;">${subject}</div>
  </td></tr>
  <tr><td style="background:#ffffff;padding:28px 32px 8px;border-radius:0 0 16px 16px;">
    <div style="margin-bottom:8px;">${bodyHtml}</div>
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:20px 0 8px;">
    <tr><td align="center">
      <a href="https://badminton360.app" style="display:inline-block;background:linear-gradient(135deg,#00b4d8,#0077a8);color:#fff;font-size:14px;font-weight:700;text-decoration:none;padding:13px 32px;border-radius:12px;letter-spacing:.3px;">Open Badminton 360 →</a>
    </td></tr>
    </table>
  </td></tr>
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;line-height:1.8;">
      You're receiving this as a <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;font-weight:600;">Badminton 360</a> member
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

    const { data: roles, error: rolesErr } = await anonClient.rpc("get_my_roles")
    if (rolesErr) return new Response(JSON.stringify({ error: `Role check failed: ${rolesErr.message}` }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    const isAdmin = Array.isArray(roles) && roles.some((r: { role: string }) => r.role === "app_admin")
    if (!isAdmin) return new Response(JSON.stringify({ error: "Forbidden — app_admin role required" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const { subject, body } = await req.json()
    if (!subject || !body) return new Response(JSON.stringify({ error: "Missing required fields: subject, body" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // profiles — need news pref + deactivation state
    const { data: profiles, error: profErr } = await admin
      .from("user_profiles").select("user_id, email_prefs, deactivated_at")
    if (profErr) throw new Error(`profiles fetch: ${profErr.message}`)

    // suppression list (keyed by email)
    const { data: supp } = await admin.from("email_suppression").select("email")
    const suppressed = new Set<string>((supp ?? []).map((s: { email: string }) => s.email.toLowerCase()))

    const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
    const emailMap = new Map<string, string>()
    for (const u of authData?.users ?? []) if (u.email) emailMap.set(u.id, u.email)

    const profById = new Map<string, { email_prefs: Record<string, unknown> | null; deactivated_at: string | null }>()
    for (const p of profiles ?? []) profById.set(p.user_id, { email_prefs: p.email_prefs as Record<string, unknown> | null, deactivated_at: p.deactivated_at as string | null })

    // Opted-in = news !== false AND not deactivated AND email not suppressed
    const recipients: { id: string; email: string }[] = []
    for (const u of authData?.users ?? []) {
      if (!u.email) continue
      if (suppressed.has(u.email.toLowerCase())) continue
      const p = profById.get(u.id)
      if (p?.deactivated_at) continue
      const prefs = p?.email_prefs
      const wantsNews = !prefs || (prefs.news !== false && prefs.news !== "false")
      if (wantsNews) recipients.push({ id: u.id, email: u.email })
    }

    if (!recipients.length) return new Response(JSON.stringify({ ok: true, sent: 0 }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })

    let sent = 0
    const errors: string[] = []
    let batchCount = 0
    for (const r of recipients) {
      const unsub = `${SUPABASE_URL}/functions/v1/unsubscribe?e=${encodeURIComponent(r.email)}&t=${await hmacHex(r.email.toLowerCase(), SUPABASE_SERVICE_KEY)}`
      const html = buildAnnouncementHtml({ subject, body, unsub })
      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          from: "Badminton 360 <noreply@badminton360.app>",
          to: [r.email], subject, html,
          headers: { "List-Unsubscribe": `<${unsub}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
        }),
      })
      if (resp.ok) sent++
      else errors.push(`${r.email}: ${await resp.text()}`)
      batchCount++
      if (batchCount % 10 === 0) await sleep(1000)
    }

    return new Response(JSON.stringify({ ok: true, sent, sent_count: sent, errors }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })
  }
})
