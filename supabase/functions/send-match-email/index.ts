import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

function buildMatchHtml(opts: {
  match_name: string
  played_on: string
  side_a_names: string[]
  side_b_names: string[]
  score_a: number
  score_b: number
  club_name: string
}): string {
  const { match_name, played_on, side_a_names, side_b_names, score_a, score_b, club_name } = opts
  const winner_side = score_a > score_b ? "A" : "B"
  const winner_names = winner_side === "A" ? side_a_names : side_b_names
  const loser_names  = winner_side === "A" ? side_b_names : side_a_names
  const winner_score = winner_side === "A" ? score_a : score_b
  const loser_score  = winner_side === "A" ? score_b : score_a

  const dateStr = new Date(played_on + "T00:00:00").toLocaleDateString("en-GB", {
    weekday: "short", day: "numeric", month: "long", year: "numeric",
  })

  const nameList = (names: string[]) =>
    names.map(n => `<span style="display:block;font-size:14px;font-weight:700;color:#0f172a;">${n}</span>`).join("")

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${match_name} — Badminton 360</title>
</head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:480px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:13px;font-weight:600;color:rgba(0,229,255,.7);letter-spacing:2px;text-transform:uppercase;margin-bottom:6px;">Match Recorded</div>
    <div style="font-size:22px;font-weight:800;color:#00e5ff;letter-spacing:-0.5px;">🏸 ${match_name}</div>
    <div style="font-size:12px;color:rgba(255,255,255,.45);margin-top:6px;">${club_name} · ${dateStr}</div>
  </td></tr>

  <!-- Score card -->
  <tr><td style="background:#fff;padding:32px;border-radius:0 0 16px 16px;">

    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
      <tr>
        <!-- Winner side -->
        <td width="40%" valign="top"
          style="background:linear-gradient(135deg,#f0fdf4,#dcfce7);border:2px solid #86efac;
                 border-radius:12px;padding:16px 14px;text-align:center;">
          <div style="font-size:10px;font-weight:700;color:#16a34a;letter-spacing:2px;
            text-transform:uppercase;margin-bottom:8px;">🏆 Winner</div>
          ${nameList(winner_names)}
        </td>

        <!-- Score badge -->
        <td width="20%" valign="middle" style="text-align:center;padding:0 8px;">
          <div style="font-size:26px;font-weight:900;color:#0f172a;line-height:1;">${winner_score}</div>
          <div style="font-size:11px;color:#94a3b8;margin:4px 0;">vs</div>
          <div style="font-size:26px;font-weight:900;color:#94a3b8;line-height:1;">${loser_score}</div>
        </td>

        <!-- Loser side -->
        <td width="40%" valign="top"
          style="background:#f8fafc;border:1px solid #e2e8f0;
                 border-radius:12px;padding:16px 14px;text-align:center;">
          <div style="font-size:10px;font-weight:700;color:#94a3b8;letter-spacing:2px;
            text-transform:uppercase;margin-bottom:8px;">Side ${winner_side === "A" ? "B" : "A"}</div>
          ${nameList(loser_names)}
        </td>
      </tr>
    </table>

    <!-- CTA -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;">
    <tr><td align="center">
      <a href="https://badminton360.app/matches"
        style="display:inline-block;background:linear-gradient(135deg,#00b4d8,#0077a8);
               color:#fff;font-size:14px;font-weight:700;text-decoration:none;
               padding:13px 32px;border-radius:12px;letter-spacing:.3px;">
        View Full Rankings →
      </a>
    </td></tr>
    </table>

    <p style="margin:0;font-size:12px;color:#94a3b8;text-align:center;line-height:1.6;">
      Elo ratings have been updated for all 4 players.<br>
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

    const SUPABASE_URL          = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY")!
    const SUPABASE_SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const RESEND_API_KEY        = Deno.env.get("RESEND_API_KEY")!

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

    const { club_id, match_name, played_on, side_a_names, side_b_names, score_a, score_b } = await req.json()
    if (!club_id || !match_name || !played_on || !side_a_names?.length || !side_b_names?.length) {
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

    // Get profiles — check email_prefs->match_recorded
    const { data: profiles } = await admin
      .from("user_profiles")
      .select("user_id, email_prefs")
      .in("user_id", userIds)

    // Build set of opted-in user_ids
    // Default: notify if key is missing (true) or explicitly "true"
    const optedIn = new Set<string>(
      (profiles ?? [])
        .filter((p: { user_id: string; email_prefs: Record<string, unknown> | null }) => {
          const prefs = p.email_prefs
          if (!prefs) return true // no prefs set = default true
          return prefs.match_recorded !== false && prefs.match_recorded !== "false"
        })
        .map((p: { user_id: string }) => p.user_id)
    )
    // Users without a profile row at all also get the email (default opt-in)
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

    const html = buildMatchHtml({
      match_name,
      played_on,
      side_a_names,
      side_b_names,
      score_a: Number(score_a),
      score_b: Number(score_b),
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
          subject: `🏸 Match recorded — ${match_name}`,
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
