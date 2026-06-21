import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

// ── helpers ────────────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

/** Converts plain text with \n line breaks into HTML paragraphs / <br> tags. */
function textToHtml(body: string): string {
  return body
    .split("\n\n")
    .map(para => `<p style="margin:0 0 14px;font-size:14px;color:#334155;line-height:1.7;">${
      para.trim().replace(/\n/g, "<br>")
    }</p>`)
    .join("")
}

function buildAnnouncementHtml(opts: {
  subject: string
  body: string
}): string {
  const { subject, body } = opts
  const bodyHtml = textToHtml(body)

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${subject}</title>
</head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:520px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:12px;font-weight:600;color:rgba(0,180,216,.75);letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">📢 Badminton 360</div>
    <div style="font-size:22px;font-weight:800;color:#ffffff;letter-spacing:-0.5px;">${subject}</div>
  </td></tr>

  <!-- Body -->
  <tr><td style="background:#ffffff;padding:28px 32px 8px;border-radius:0 0 16px 16px;">

    <div style="margin-bottom:8px;">
      ${bodyHtml}
    </div>

    <!-- CTA -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:20px 0 8px;">
    <tr><td align="center">
      <a href="https://badminton360.app"
        style="display:inline-block;background:linear-gradient(135deg,#00b4d8,#0077a8);
               color:#fff;font-size:14px;font-weight:700;text-decoration:none;
               padding:13px 32px;border-radius:12px;letter-spacing:.3px;">
        Open Badminton 360 →
      </a>
    </td></tr>
    </table>

  </td></tr>

  <!-- Footer -->
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;line-height:1.8;">
      You're receiving this as a
      <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;font-weight:600;">Badminton 360</a>
      member
      &nbsp;·&nbsp;
      Unsubscribe in app
      <a href="https://badminton360.app/settings/email" style="color:#0099bb;text-decoration:none;">Settings → Email</a>
    </p>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>`
}

// ── handler ────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    // Require an Authorization header with a valid user JWT
    const authHeader = req.headers.get("authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const SUPABASE_URL         = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY    = Deno.env.get("SUPABASE_ANON_KEY")!
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const RESEND_API_KEY       = Deno.env.get("RESEND_API_KEY")!

    // 1. Verify caller is authenticated
    const anonClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authErr } = await anonClient.auth.getUser()
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // 2. Verify caller is an app_admin
    const { data: roles, error: rolesErr } = await anonClient.rpc("get_my_roles")
    if (rolesErr) {
      return new Response(JSON.stringify({ error: `Role check failed: ${rolesErr.message}` }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }
    const isAdmin = Array.isArray(roles) && roles.some(
      (r: { role: string }) => r.role === "app_admin"
    )
    if (!isAdmin) {
      return new Response(JSON.stringify({ error: "Forbidden — app_admin role required" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // 3. Parse request body
    const { subject, body } = await req.json()
    if (!subject || !body) {
      return new Response(JSON.stringify({ error: "Missing required fields: subject, body" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // 4. Service role client for user lookups (bypasses RLS)
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // 5. Get all user_ids opted into news announcements
    //    Default = true when email_prefs is null or key is missing
    const { data: profiles, error: profErr } = await admin
      .from("user_profiles")
      .select("user_id, email_prefs")

    if (profErr) throw new Error(`profiles fetch: ${profErr.message}`)

    // Also get auth users for email addresses
    const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
    const emailMap = new Map<string, string>()
    for (const u of authData?.users ?? []) {
      if (u.email) emailMap.set(u.id, u.email)
    }

    // Determine opted-in set: profile rows where news !== false
    const optedInIds = new Set<string>()
    for (const p of profiles ?? []) {
      const prefs = p.email_prefs as Record<string, unknown> | null
      const wantsNews = !prefs || (prefs.news !== false && prefs.news !== "false")
      if (wantsNews) optedInIds.add(p.user_id)
    }
    // Users with no profile row at all get the email (default opt-in)
    for (const u of authData?.users ?? []) {
      if (u.email && !profiles?.some((p: { user_id: string }) => p.user_id === u.id)) {
        optedInIds.add(u.id)
      }
    }

    if (!optedInIds.size) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const html = buildAnnouncementHtml({ subject, body })

    let sent = 0
    const errors: string[] = []
    let batchCount = 0

    for (const uid of optedInIds) {
      const email = emailMap.get(uid)
      if (!email) continue

      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "Badminton 360 <noreply@badminton360.app>",
          to: [email],
          subject,
          html,
        }),
      })

      if (resp.ok) {
        sent++
      } else {
        const txt = await resp.text()
        errors.push(`${email}: ${txt}`)
      }

      batchCount++
      // Rate-limit: sleep 1 s after every 10 sends
      if (batchCount % 10 === 0) {
        await sleep(1000)
      }
    }

    return new Response(
      JSON.stringify({ ok: true, sent, errors }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
