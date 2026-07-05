import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
}

// ── helpers ────────────────────────────────────────────────────────────────

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms))
}

interface LeaderboardRow {
  id: string
  display_name: string
  elo: number
  games: number
  wins: number
  win_pct: number
  club_rank: number
}

const esc = (s: string) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

// Build the "story of the week" — a short narrative celebrating the winners.
function winnersStory(club_name: string, top5: LeaderboardRow[]): string {
  const champ = top5[0]
  const second = top5[1]
  const third = top5[2]
  if (!champ) return ""

  const champName = esc(champ.display_name)
  let story = `<strong style="color:#0f172a;">${champName}</strong> tops <strong>${esc(club_name)}</strong> this week `
  story += `with <strong>${Math.round(champ.elo)} Elo</strong>`
  if (champ.games > 0) story += ` and a ${Number(champ.win_pct).toFixed(0)}% win rate across ${champ.games} game${champ.games === 1 ? "" : "s"}`
  story += ". "

  if (second) {
    const gap = Math.round(champ.elo - second.elo)
    story += `${esc(second.display_name)} is in second`
    if (third) story += `, ${esc(third.display_name)} takes third`
    story += "."
    if (gap >= 0) {
      story += gap <= 15
        ? ` The gap at the top is just <strong>${gap} Elo</strong> — next week is anyone's game. 🔥`
        : ` The lead is <strong>${gap} Elo</strong> — can anyone close it? 🎯`
    }
  } else {
    story += "Get more matches recorded to fill out the podium!"
  }
  return story
}

function buildDigestHtml(opts: {
  club_name: string
  nickname: string
  top5: LeaderboardRow[]
}): string {
  const { club_name, nickname, top5 } = opts
  const champ = top5[0]

  const medalFor = (rank: number) =>
    rank === 1 ? "🥇" : rank === 2 ? "🥈" : rank === 3 ? "🥉" : `#${rank}`

  // Podium (top 3) as a celebratory row of cards
  const podium = top5.slice(0, 3).map(p => {
    const medal = medalFor(p.club_rank)
    const isChamp = p.club_rank === 1
    const bg = isChamp ? "#fffbea" : "#f8fafc"
    const border = isChamp ? "#fcd34d" : "#e2e8f0"
    return `
      <td width="33%" valign="top" style="padding:4px;">
        <div style="background:${bg};border:1px solid ${border};border-radius:12px;padding:14px 8px;text-align:center;">
          <div style="font-size:26px;line-height:1;margin-bottom:6px;">${medal}</div>
          <div style="font-size:13px;font-weight:800;color:#0f172a;margin-bottom:2px;">${esc(p.display_name)}</div>
          <div style="font-size:12px;font-weight:700;color:#0099b8;">${Math.round(p.elo)} Elo</div>
          <div style="font-size:11px;color:#64748b;margin-top:2px;">${p.wins}W / ${p.games - p.wins}L</div>
        </div>
      </td>`
  }).join("")

  const rows = top5.map(p => {
    const isFirst = p.club_rank === 1
    const rowBg   = isFirst ? "background:#fffbea;" : ""
    const rankCell = isFirst
      ? `<td style="padding:12px 14px;font-weight:800;color:#d97706;font-size:15px;">${medalFor(p.club_rank)}</td>`
      : `<td style="padding:12px 14px;color:#64748b;font-size:13px;">${medalFor(p.club_rank)}</td>`
    const nameSt = isFirst
      ? `font-weight:800;color:#92400e;font-size:14px;`
      : `font-weight:600;color:#0f172a;font-size:13px;`

    return `
    <tr style="${rowBg}border-bottom:1px solid #f1f5f9;">
      ${rankCell}
      <td style="padding:12px 4px;${nameSt}">${esc(p.display_name)}</td>
      <td style="padding:12px 8px;text-align:right;font-weight:700;color:#0099b8;font-size:13px;">${Math.round(p.elo)}</td>
      <td style="padding:12px 8px;text-align:right;color:#475569;font-size:13px;">${p.wins}W / ${p.games - p.wins}L</td>
      <td style="padding:12px 14px;text-align:right;color:#475569;font-size:12px;">${Number(p.win_pct).toFixed(0)}%</td>
    </tr>`
  }).join("")

  const greeting = nickname ? `Hi ${esc(nickname)},` : "Hi,"
  const story = winnersStory(club_name, top5)

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Weekly Rankings — ${esc(club_name)}</title>
</head>
<body style="margin:0;padding:0;background:#f0f4f8;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f4f8;padding:32px 16px;">
<tr><td align="center">
<table width="100%" style="max-width:520px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:12px;font-weight:600;color:rgba(0,180,216,.75);letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">This week in ${esc(club_name)}</div>
    <div style="font-size:24px;font-weight:800;color:#00b4d8;letter-spacing:-0.5px;">🏆 Champion of the Week</div>
    ${champ ? `<div style="font-size:16px;font-weight:800;color:#fff;margin-top:8px;">${esc(champ.display_name)}</div>` : ""}
  </td></tr>

  <!-- Body -->
  <tr><td style="background:#ffffff;padding:26px 32px 8px;border-radius:0 0 16px 16px;">

    <p style="margin:0 0 16px;font-size:14px;color:#334155;line-height:1.65;">${greeting}</p>

    <!-- Winners story -->
    <p style="margin:0 0 22px;font-size:14px;color:#334155;line-height:1.7;">${story}</p>

    <!-- Podium -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
      <tr>${podium}</tr>
    </table>

    <!-- Full top 5 -->
    <div style="font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;margin-bottom:8px;">Full standings</div>
    <table width="100%" cellpadding="0" cellspacing="0"
      style="border-collapse:collapse;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;">
      <thead>
        <tr style="background:#f8fafc;">
          <th style="padding:10px 14px;text-align:left;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Rank</th>
          <th style="padding:10px 4px;text-align:left;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Player</th>
          <th style="padding:10px 8px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Elo</th>
          <th style="padding:10px 8px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">W / L</th>
          <th style="padding:10px 14px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Win%</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>

    <!-- CTA -->
    <table width="100%" cellpadding="0" cellspacing="0" style="margin:24px 0 8px;">
    <tr><td align="center">
      <a href="https://badminton360.app/dashboard"
        style="display:inline-block;background:linear-gradient(135deg,#00b4d8,#0077a8);
               color:#fff;font-size:14px;font-weight:700;text-decoration:none;
               padding:13px 32px;border-radius:12px;letter-spacing:.3px;">
        View Full Leaderboard →
      </a>
    </td></tr>
    </table>

  </td></tr>

  <!-- Footer -->
  <tr><td style="padding:20px 0;text-align:center;">
    <p style="margin:0;font-size:11px;color:#94a3b8;line-height:1.8;">
      <a href="https://badminton360.app" style="color:#0099bb;text-decoration:none;font-weight:600;">Badminton 360</a>
      &nbsp;·&nbsp; Manage emails in
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
    const SUPABASE_URL         = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const RESEND_API_KEY       = Deno.env.get("RESEND_API_KEY")!
    const CRON_SECRET          = Deno.env.get("WEEKLY_DIGEST_SECRET") ?? ""

    // Auth: this function runs with verify_jwt=false so pg_cron can call it,
    // but it must present the shared secret (also allow the service-role key
    // as a bearer for manual/admin triggers).
    const secretHeader = req.headers.get("x-cron-secret") ?? ""
    const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "")
    const authorised =
      (CRON_SECRET && secretHeader === CRON_SECRET) ||
      (SUPABASE_SERVICE_KEY && bearer === SUPABASE_SERVICE_KEY)
    if (!authorised) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // 1. Get all clubs
    const { data: clubs, error: clubsErr } = await admin
      .from("clubs")
      .select("id, name")

    if (clubsErr) throw new Error(`clubs fetch: ${clubsErr.message}`)
    if (!clubs?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, clubs: 0 }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Get all auth users once (to map user_id → email)
    const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
    const emailMap = new Map<string, string>()
    for (const u of authData?.users ?? []) {
      if (u.email) emailMap.set(u.id, u.email)
    }

    let totalSent = 0
    const allErrors: string[] = []
    let batchCount = 0

    for (const club of clubs) {
      // 2. Get top 5 from leaderboard RPC
      const { data: leaderboard, error: lbErr } = await admin.rpc("get_club_leaderboard", {
        p_club_id: club.id,
      })
      if (lbErr) {
        allErrors.push(`leaderboard(${club.id}): ${lbErr.message}`)
        continue
      }
      // Only ranked players (games>0) — unplayed members have null club_rank
      const ranked: LeaderboardRow[] = (leaderboard ?? []).filter((r: LeaderboardRow) => r.club_rank != null && r.games > 0)
      const top5 = ranked.slice(0, 5)
      if (!top5.length) continue

      // 3. Get all club members
      const { data: members } = await admin
        .from("club_members")
        .select("user_id")
        .eq("club_id", club.id)

      if (!members?.length) continue

      const userIds = members.map((m: { user_id: string }) => m.user_id)

      // 4. Get profiles for weekly_digest preference + nickname
      const { data: profiles } = await admin
        .from("user_profiles")
        .select("user_id, nickname, email_prefs")
        .in("user_id", userIds)

      const profileMap = new Map<string, { nickname: string | null; email_prefs: Record<string, unknown> | null }>()
      for (const p of profiles ?? []) {
        profileMap.set(p.user_id, { nickname: p.nickname, email_prefs: p.email_prefs })
      }

      // 5. Filter opted-in members (default = true when key missing)
      for (const uid of userIds) {
        const email = emailMap.get(uid)
        if (!email) continue

        const profile = profileMap.get(uid)
        const prefs   = profile?.email_prefs ?? null
        const wantsDigest =
          !prefs ||
          (prefs.weekly_digest !== false && prefs.weekly_digest !== "false")

        if (!wantsDigest) continue

        const nickname = profile?.nickname ?? ""
        const html = buildDigestHtml({ club_name: club.name, nickname, top5 })

        // 6. Send via Resend
        const resp = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${RESEND_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: "Badminton 360 <noreply@badminton360.app>",
            to: [email],
            subject: `🏆 ${top5[0].display_name} tops ${club.name} — Weekly Rankings`,
            html,
          }),
        })

        if (resp.ok) {
          totalSent++
        } else {
          const txt = await resp.text()
          allErrors.push(`${email}(${club.name}): ${txt}`)
        }

        batchCount++
        if (batchCount % 10 === 0) {
          await sleep(1000)
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, sent: totalSent, clubs: clubs.length, errors: allErrors }),
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
