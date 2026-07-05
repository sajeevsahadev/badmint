import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const RESEND_API_KEY      = Deno.env.get("RESEND_API_KEY")
const SERVICE_ROLE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function buildWelcomeHtml(name: string): string {
  const displayName = name && name.trim() ? name.split(" ")[0] : "Champ"

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Welcome to Badminton 360</title>
</head>
<body style="margin:0;padding:0;background-color:#060e1c;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
    style="background-color:#060e1c;min-height:100vh;">
    <tr>
      <td align="center" style="padding:32px 16px;">

        <!-- Outer card -->
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
          style="max-width:580px;background-color:#0c1a2e;border-radius:16px;border:1px solid #1a3050;overflow:hidden;">

          <!-- Header stripe -->
          <tr>
            <td style="background:linear-gradient(135deg,#0c1a2e 0%,#0f2040 50%,#0c1a2e 100%);
              padding:32px 40px 28px;text-align:center;border-bottom:1px solid #1a3050;">
              <!-- Logo mark -->
              <div style="display:inline-block;background:linear-gradient(135deg,#00e5ff,#a855f7);
                border-radius:12px;padding:10px 16px;margin-bottom:16px;">
                <span style="font-size:20px;font-weight:900;color:#060e1c;letter-spacing:-0.5px;">B360</span>
              </div>
              <div style="font-size:13px;font-weight:600;color:#94a3b8;letter-spacing:3px;
                text-transform:uppercase;margin-top:4px;">Badminton 360</div>
            </td>
          </tr>

          <!-- Hero -->
          <tr>
            <td style="padding:40px 40px 32px;text-align:center;">
              <p style="margin:0 0 8px;font-size:13px;font-weight:500;color:#00e5ff;letter-spacing:2px;
                text-transform:uppercase;">Welcome aboard</p>
              <h1 style="margin:0 0 12px;font-size:32px;font-weight:800;line-height:1.2;
                background:linear-gradient(90deg,#00e5ff,#a855f7);
                -webkit-background-clip:text;-webkit-text-fill-color:transparent;
                background-clip:text;color:#00e5ff;">
                Hey ${displayName}! 🏸
              </h1>
              <p style="margin:0;font-size:16px;color:#cbd5e1;line-height:1.6;">
                You're now part of <strong style="color:#f8fafc;">Badminton 360</strong> —
                the free app your whole badminton crew has been waiting for.
              </p>
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding:0 40px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#1e3a5f,transparent);"></div>
            </td>
          </tr>

          <!-- Feature grid -->
          <tr>
            <td style="padding:32px 40px;">
              <p style="margin:0 0 20px;font-size:12px;font-weight:600;color:#64748b;
                letter-spacing:2px;text-transform:uppercase;text-align:center;">
                Everything your club needs
              </p>

              <!-- Row 1 -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td width="48%" valign="top"
                    style="background-color:#0f2040;border-radius:12px;border:1px solid #1a3050;
                    padding:20px 18px;">
                    <div style="font-size:24px;margin-bottom:10px;">🏆</div>
                    <div style="font-size:14px;font-weight:700;color:#00e5ff;margin-bottom:6px;">
                      Elo Rankings
                    </div>
                    <div style="font-size:13px;color:#94a3b8;line-height:1.5;">
                      Your skill rating updates after every match. Compete globally.
                    </div>
                  </td>
                  <td width="4%"></td>
                  <td width="48%" valign="top"
                    style="background-color:#0f2040;border-radius:12px;border:1px solid #1a3050;
                    padding:20px 18px;">
                    <div style="font-size:24px;margin-bottom:10px;">💰</div>
                    <div style="font-size:14px;font-weight:700;color:#a855f7;margin-bottom:6px;">
                      Split Pay + Wallet
                    </div>
                    <div style="font-size:13px;color:#94a3b8;line-height:1.5;">
                      Split court costs equally. Track who owes what. No drama.
                    </div>
                  </td>
                </tr>
              </table>

              <div style="height:12px;"></div>

              <!-- Row 2 -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td width="48%" valign="top"
                    style="background-color:#0f2040;border-radius:12px;border:1px solid #1a3050;
                    padding:20px 18px;">
                    <div style="font-size:24px;margin-bottom:10px;">🎯</div>
                    <div style="font-size:14px;font-weight:700;color:#fbbf24;margin-bottom:6px;">
                      Tournaments
                    </div>
                    <div style="font-size:13px;color:#94a3b8;line-height:1.5;">
                      Organize brackets, register teams, track results.
                    </div>
                  </td>
                  <td width="4%"></td>
                  <td width="48%" valign="top"
                    style="background-color:#0f2040;border-radius:12px;border:1px solid #1a3050;
                    padding:20px 18px;">
                    <div style="font-size:24px;margin-bottom:10px;">📅</div>
                    <div style="font-size:14px;font-weight:700;color:#00e5ff;margin-bottom:6px;">
                      Schedule & Polls
                    </div>
                    <div style="font-size:13px;color:#94a3b8;line-height:1.5;">
                      Plan match days, vote on times, track who's coming.
                    </div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- CTA -->
          <tr>
            <td style="padding:8px 40px 40px;text-align:center;">
              <a href="https://badminton360.app"
                style="display:inline-block;padding:15px 40px;font-size:15px;font-weight:700;
                color:#060e1c;text-decoration:none;border-radius:10px;letter-spacing:0.3px;
                background:linear-gradient(135deg,#00e5ff,#00b8d4);">
                Open Badminton 360 →
              </a>
              <p style="margin:16px 0 0;font-size:12px;color:#475569;">
                Install it on your phone — it works like a native app.
              </p>
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding:0 40px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#1e3a5f,transparent);"></div>
            </td>
          </tr>

          <!-- Tagline / quote -->
          <tr>
            <td style="padding:28px 40px;text-align:center;">
              <p style="margin:0;font-size:15px;font-style:italic;color:#64748b;line-height:1.6;">
                "Your Club · Your Game · One App"
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color:#080f1e;border-top:1px solid #1a3050;
              padding:24px 40px;text-align:center;border-radius:0 0 16px 16px;">
              <p style="margin:0 0 6px;font-size:12px;color:#475569;">
                Questions? Reply to this email or reach us at
                <a href="mailto:hello@badminton360.app"
                  style="color:#00e5ff;text-decoration:none;">hello@badminton360.app</a>
              </p>
              <p style="margin:0;font-size:11px;color:#334155;">
                © 2026 Badminton 360 · Free for every club, worldwide
              </p>
            </td>
          </tr>

        </table>
        <!-- /Outer card -->

      </td>
    </tr>
  </table>
</body>
</html>`
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // Only accept calls from Supabase internal webhooks (service role key as Bearer)
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "")
  if (!SERVICE_ROLE_KEY || token !== SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }

  try {
    const body = await req.json()

    // Support two call modes:
    // 1. Supabase Auth webhook: { type: "INSERT", record: { email, raw_user_meta_data: { full_name } } }
    // 2. Direct/manual call:   { to, name }
    let to: string
    let name: string

    if (body.record?.email) {
      // Auth webhook payload
      to   = body.record.email
      name = body.record.raw_user_meta_data?.full_name ?? ""
    } else if (body.to) {
      // Direct call
      to   = body.to
      name = body.name ?? ""
    } else {
      return new Response(
        JSON.stringify({ error: "Missing required field: to (or Auth webhook record.email)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      )
    }

    const html = buildWelcomeHtml(name)

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Badminton 360 <hello@badminton360.app>",
        to: [to],
        subject: "Welcome to Badminton 360 🏸",
        html,
      }),
    })

    const data = await res.json()

    if (!res.ok) {
      return new Response(JSON.stringify({ error: data }), {
        status: res.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    return new Response(JSON.stringify({ ok: true, ...data }), {
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
