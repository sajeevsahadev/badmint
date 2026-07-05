import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function buildExpenseHtml(opts: {
  title: string
  amount: number
  paid_by_name: string
  split_count: number
  club_name: string
}): string {
  const { title, amount, paid_by_name, split_count, club_name } = opts
  const per_person = split_count > 0 ? amount / split_count : amount
  const fmt = (n: number) => n.toFixed(2)

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>New expense — ${title}</title>
</head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:480px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:13px;font-weight:600;color:rgba(168,85,247,.8);letter-spacing:2px;text-transform:uppercase;margin-bottom:6px;">New Expense</div>
    <div style="font-size:22px;font-weight:800;color:#a855f7;letter-spacing:-0.5px;">💰 ${title}</div>
    <div style="font-size:12px;color:rgba(255,255,255,.45);margin-top:6px;">${club_name}</div>
  </td></tr>

  <!-- Body -->
  <tr><td style="background:#fff;padding:32px;border-radius:0 0 16px 16px;">

    <!-- Summary card -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
      <tr>
        <td style="background:#faf5ff;border:1px solid #e9d5ff;border-radius:12px;padding:20px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="padding-bottom:12px;border-bottom:1px solid #e9d5ff;">
                <div style="font-size:12px;color:#7c3aed;font-weight:600;text-transform:uppercase;letter-spacing:1px;margin-bottom:4px;">Total</div>
                <div style="font-size:30px;font-weight:900;color:#0f172a;">AED ${fmt(amount)}</div>
              </td>
            </tr>
            <tr>
              <td style="padding-top:12px;">
                <table width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td style="font-size:13px;color:#475569;padding-bottom:6px;">
                      <strong style="color:#0f172a;">Paid by:</strong> ${paid_by_name}
                    </td>
                  </tr>
                  <tr>
                    <td style="font-size:13px;color:#475569;padding-bottom:6px;">
                      <strong style="color:#0f172a;">Split between:</strong> ${split_count} ${split_count === 1 ? "person" : "people"}
                    </td>
                  </tr>
                  <tr>
                    <td style="font-size:13px;color:#475569;">
                      <strong style="color:#0f172a;">Your share:</strong>
                      <span style="font-weight:700;color:#7c3aed;">AED ${fmt(per_person)}</span>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>

    <!-- CTA -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;">
    <tr><td align="center">
      <a href="https://badminton360.app/splits"
        style="display:inline-block;background:linear-gradient(135deg,#a855f7,#7c3aed);
               color:#fff;font-size:14px;font-weight:700;text-decoration:none;
               padding:13px 32px;border-radius:12px;letter-spacing:.3px;">
        View Split Pay →
      </a>
    </td></tr>
    </table>

    <p style="margin:0;font-size:12px;color:#94a3b8;text-align:center;line-height:1.6;">
      Check the Balance tab in Split Pay to see who owes what.<br>
      <a href="https://badminton360.app/settings/email" style="color:#0099bb;text-decoration:none;">
        Manage email preferences
      </a>
    </p>
  </td></tr>

  <!-- Footer -->
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;">
      <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;">Badminton 360</a>
      &nbsp;·&nbsp;
      <a href="mailto:hello@badminton360.app" style="color:#0099bb;text-decoration:none;">hello@badminton360.app</a>
    </p>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>`
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

    const SUPABASE_URL         = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY    = Deno.env.get("SUPABASE_ANON_KEY")!
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const RESEND_API_KEY       = Deno.env.get("RESEND_API_KEY")!

    // Verify caller is an authenticated Supabase user
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

    const { club_id, title, amount, paid_by_name, split_count } = await req.json()
    if (!club_id || !title || !amount) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Use service role key to read member emails + prefs + club name
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Get club name
    const { data: club } = await admin
      .from("clubs")
      .select("name")
      .eq("id", club_id)
      .single()

    // Get all club member user_ids
    const { data: members } = await admin
      .from("club_members")
      .select("user_id")
      .eq("club_id", club_id)

    if (!members?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const userIds = members.map((m: { user_id: string }) => m.user_id)

    // Get profiles — check email_prefs->payment_reminders
    const { data: profiles } = await admin
      .from("user_profiles")
      .select("user_id, email_prefs")
      .in("user_id", userIds)

    // Default: notify if key is missing or explicitly true
    const optedIn = new Set<string>(
      (profiles ?? [])
        .filter((p: { user_id: string; email_prefs: Record<string, unknown> | null }) => {
          const prefs = p.email_prefs
          if (!prefs) return true
          return prefs.payment_reminders !== false && prefs.payment_reminders !== "false"
        })
        .map((p: { user_id: string }) => p.user_id)
    )
    for (const uid of userIds) {
      const hasProfile = (profiles ?? []).some((p: { user_id: string }) => p.user_id === uid)
      if (!hasProfile) optedIn.add(uid)
    }

    if (!optedIn.size) {
      return new Response(JSON.stringify({ ok: true, sent: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Get emails from auth.users via admin API
    const { data: authUsers } = await admin.auth.admin.listUsers({ perPage: 1000 })
    const emailMap = new Map<string, string>()
    for (const u of authUsers?.users ?? []) {
      if (u.email) emailMap.set(u.id, u.email)
    }

    const html = buildExpenseHtml({
      title,
      amount: Number(amount),
      paid_by_name: paid_by_name ?? "Unknown",
      split_count: Number(split_count) || 1,
      club_name: club?.name ?? "Your Club",
    })

    let sent = 0
    const errors: string[] = []

    for (const uid of optedIn) {
      const email = emailMap.get(uid)
      if (!email) continue

      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "Badminton 360 <hello@badminton360.app>",
          to: [email],
          subject: `💰 New expense added — ${title}`,
          html,
        }),
      })

      if (resp.ok) {
        sent++
      } else {
        const txt = await resp.text()
        errors.push(`${email}: ${txt}`)
      }
    }

    return new Response(JSON.stringify({ ok: true, sent, errors }), {
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
