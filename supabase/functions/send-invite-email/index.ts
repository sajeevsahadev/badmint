import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get("authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const SUPABASE_URL      = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!
    const RESEND_API_KEY    = Deno.env.get("RESEND_API_KEY")!

    // Verify the caller is an authenticated Supabase user
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authErr } = await supabase.auth.getUser()
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const { invitee_email, invitee_name, club_name, token } = await req.json()
    if (!invitee_email || !club_name || !token) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const inviteUrl   = `https://badminton360.app/join?token=${token}`
    const displayName = (invitee_name || "").trim() || invitee_email.split("@")[0]
    const senderFirst = (user.user_metadata?.full_name || "").split(" ")[0] || "Your friend"

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>You're invited to ${club_name}!</title>
</head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:480px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:32px;text-align:center;">
    <div style="font-size:40px;margin-bottom:8px;">🏸</div>
    <div style="font-size:22px;font-weight:800;color:#00e5ff;letter-spacing:-0.5px;">Badminton 360</div>
    <div style="font-size:10px;color:rgba(255,255,255,.5);letter-spacing:2px;margin-top:4px;">YOUR CLUB · YOUR GAME · ONE APP</div>
  </td></tr>

  <!-- Body -->
  <tr><td style="background:#fff;padding:36px 32px;border-radius:0 0 16px 16px;">
    <h1 style="margin:0 0 12px;font-size:22px;color:#0f172a;">Hey ${displayName}! 👋</h1>
    <p style="margin:0 0 20px;font-size:15px;color:#475569;line-height:1.65;">
      <strong style="color:#0f172a;">${senderFirst}</strong> has invited you to join
      <strong style="color:#0f172a;">${club_name}</strong> on Badminton 360 — the free app
      for tracking Elo rankings, splitting court costs, and running tournaments.
    </p>

    <!-- CTA button -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:28px 0;">
    <tr><td align="center">
      <a href="${inviteUrl}"
        style="display:inline-block;background:linear-gradient(135deg,#00b4d8,#0077a8);
               color:#fff;font-size:15px;font-weight:700;text-decoration:none;
               padding:15px 36px;border-radius:14px;letter-spacing:.3px;">
        Accept Invite &amp; Join Club →
      </a>
    </td></tr>
    </table>

    <!-- Feature pills -->
    <table width="100%" cellpadding="0" cellspacing="0"
      style="background:#f8fafc;border-radius:12px;margin-bottom:24px;">
      <tr><td style="padding:11px 16px;font-size:13px;color:#475569;">
        🏆 <strong style="color:#0f172a;">Elo Rankings</strong> — updated automatically after every match
      </td></tr>
      <tr><td style="padding:11px 16px;font-size:13px;color:#475569;border-top:1px solid #e2e8f0;">
        ⚖️ <strong style="color:#0f172a;">Split Pay</strong> — split court costs equally in seconds
      </td></tr>
      <tr><td style="padding:11px 16px;font-size:13px;color:#475569;border-top:1px solid #e2e8f0;">
        💰 <strong style="color:#0f172a;">Club Wallet</strong> — pre-fund and never chase payments again
      </td></tr>
    </table>

    <p style="margin:0 0 6px;font-size:12px;color:#94a3b8;text-align:center;">
      Sign in with Google to accept — it's completely free.
    </p>
    <p style="margin:0;font-size:11px;color:#cbd5e1;text-align:center;">
      Or copy: <a href="${inviteUrl}" style="color:#0099bb;">${inviteUrl}</a>
    </p>
  </td></tr>

  <!-- Footer -->
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;">
      Sent via <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;">Badminton 360</a>
      &nbsp;·&nbsp;
      <a href="mailto:hello@badminton360.app" style="color:#0099bb;text-decoration:none;">hello@badminton360.app</a>
    </p>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>`

    const resendResp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Badminton 360 <hello@badminton360.app>",
        to: [invitee_email],
        subject: `${senderFirst} invited you to join ${club_name} 🏸`,
        html,
      }),
    })

    if (!resendResp.ok) {
      const errText = await resendResp.text()
      return new Response(JSON.stringify({ error: `Email service error: ${errText}` }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
