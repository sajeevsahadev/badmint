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

// Current day-of-week (0=Sun..6=Sat) and hour (0..23) in a given IANA timezone.
function nowInTz(tz: string): { dow: number; hour: number } {
  let parts: Intl.DateTimeFormatPart[]
  try {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz || "Asia/Dubai", weekday: "short", hour: "numeric", hour12: false,
    }).formatToParts(new Date())
  } catch {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: "Asia/Dubai", weekday: "short", hour: "numeric", hour12: false,
    }).formatToParts(new Date())
  }
  const wd = parts.find(p => p.type === "weekday")?.value ?? "Sun"
  const dowMap: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }
  let hour = parseInt(parts.find(p => p.type === "hour")?.value ?? "0", 10)
  if (hour === 24) hour = 0
  return { dow: dowMap[wd] ?? 0, hour }
}

const esc = (s: string) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

interface LeaderboardRow {
  display_name: string
  elo: number
  games: number
  wins: number
  win_pct: number
  club_rank: number | null
}
interface WeeklyRow {
  display_name: string
  games: number
  wins: number
  losses: number
  elo_delta: number
}

// Colored initials "avatar" — data-URI photos are stripped by Gmail, so we
// render a reliable initials circle instead (renders in every mail client).
const AVATAR_COLORS = ["#00b4d8", "#a855f7", "#f59e0b", "#10b981", "#ef4444", "#6366f1", "#ec4899", "#14b8a6"]
function initials(name: string): string {
  return (name || "?").trim().split(/\s+/).map(w => w[0]).slice(0, 2).join("").toUpperCase()
}
function colorFor(name: string): string {
  let h = 0
  for (const c of (name || "?")) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return AVATAR_COLORS[h % AVATAR_COLORS.length]
}
function avatarCell(name: string, size = 34): string {
  const fs = Math.round(size * 0.4)
  return `<table cellpadding="0" cellspacing="0" style="display:inline-table;"><tr>
    <td width="${size}" height="${size}" align="center" valign="middle"
      style="width:${size}px;height:${size}px;border-radius:${size}px;background:${colorFor(name)};
             color:#fff;font-weight:700;font-size:${fs}px;text-align:center;">${esc(initials(name))}</td>
  </tr></table>`
}

const medalFor = (rank: number) =>
  rank === 1 ? "🥇" : rank === 2 ? "🥈" : rank === 3 ? "🥉" : `#${rank}`

const eloChip = (delta: number) => {
  const up = delta >= 0
  const color = up ? "#059669" : "#dc2626"
  const bg = up ? "#ecfdf5" : "#fef2f2"
  const sign = up ? "▲ +" : "▼ "
  return `<span style="display:inline-block;background:${bg};color:${color};font-size:11px;font-weight:700;padding:2px 8px;border-radius:10px;">${sign}${Math.abs(delta)}</span>`
}

interface DayHeroPlayer { player_id: string; name: string; games: number; wins: number; delta: number }
interface DayAward { label: string; icon: string; color: string; soft: string; name: string; stat: string }

// Three DIFFERENT standouts from the latest match day, so recognition spreads
// beyond the single weekly MVP (mirrors the app's "Today's Heroes" card).
function computeDayAwards(raw: { players?: DayHeroPlayer[] } | null): DayAward[] {
  const arr = raw?.players ?? []
  if (!arr.length) return []
  const used = new Set<string>()
  const out: DayAward[] = []
  const pick = (
    label: string, icon: string, color: string, soft: string,
    better: (a: DayHeroPlayer, b: DayHeroPlayer) => boolean,
    statFn: (p: DayHeroPlayer) => string,
    guard: (p: DayHeroPlayer) => boolean,
  ) => {
    const cand = arr.filter(p => !used.has(p.player_id) && guard(p))
    if (!cand.length) return
    const win = cand.reduce((a, b) => (better(a, b) ? b : a))
    used.add(win.player_id)
    out.push({ label, icon, color, soft, name: win.name, stat: statFn(win) })
  }
  pick("Top Climber", "🚀", "#b45309", "#fef3c7", (a, b) => b.delta > a.delta, p => `+${p.delta} Elo`, p => p.delta > 0)
  pick("Most Wins", "🏆", "#0e7490", "#cffafe", (a, b) => b.wins > a.wins || (b.wins === a.wins && b.delta > a.delta), p => `${p.wins} win${p.wins === 1 ? "" : "s"}`, p => p.wins > 0)
  pick("Most Active", "🎯", "#7c3aed", "#f3e8ff", (a, b) => b.games > a.games || (b.games === a.games && b.wins > a.wins), p => `${p.games} games`, p => p.games >= 1)
  return out
}

function heroesSection(heroes: DayAward[], dateLabel: string): string {
  if (!heroes.length) return ""
  const cells = heroes.map(h => `
    <td width="33%" align="center" valign="top" style="padding:16px 6px;">
      <div style="font-size:20px;line-height:1;">${h.icon}</div>
      <div style="font-size:10px;font-weight:800;letter-spacing:.5px;text-transform:uppercase;color:${h.color};margin:6px 0 9px;">${esc(h.label)}</div>
      ${avatarCell(h.name, 40)}
      <div style="font-size:13px;font-weight:700;color:#0f172a;margin-top:7px;">${esc(h.name)}</div>
      <div style="display:inline-block;margin-top:5px;font-size:11px;font-weight:800;color:${h.color};background:${h.soft};padding:2px 10px;border-radius:10px;">${esc(h.stat)}</div>
    </td>`).join("")
  return `
    <div style="font-size:13px;font-weight:800;color:#0f172a;margin:4px 0 10px;">🎉 Latest Session Heroes${dateLabel ? ` <span style="font-weight:600;color:#94a3b8;font-size:11px;">· ${esc(dateLabel)}</span>` : ""}</div>
    <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;margin-bottom:26px;background:#fbfcff;">
      <tr>${cells}</tr>
    </table>`
}

function buildDigestHtml(opts: {
  club_name: string
  nickname: string
  top5: LeaderboardRow[]
  weekly: WeeklyRow[]
  heroes: DayAward[]
  heroDate: string
}): string {
  const { club_name, nickname, top5, weekly, heroes, heroDate } = opts
  const mvp = weekly[0]
  const greeting = nickname ? `Hi ${esc(nickname)},` : "Hi,"

  // Weekly narrative
  let story = ""
  if (mvp) {
    const climber = [...weekly].sort((a, b) => b.elo_delta - a.elo_delta)[0]
    story = `<strong style="color:#0f172a;">${esc(mvp.display_name)}</strong> led <strong>${esc(club_name)}</strong> this week with <strong>${mvp.wins} win${mvp.wins === 1 ? "" : "s"}</strong>`
    if (climber && climber.elo_delta > 0 && climber.display_name !== mvp.display_name) {
      story += `, and <strong style="color:#0f172a;">${esc(climber.display_name)}</strong> was the biggest climber (+${climber.elo_delta} Elo)`
    }
    story += ". Here's the full week 👇"
  } else {
    story = `No matches were recorded in <strong>${esc(club_name)}</strong> this week — get on court and make next week's highlights! 🏸`
  }

  // ── Section 1: This week's champions ──
  const weeklyRows = weekly.slice(0, 6).map((p, i) => `
    <tr style="${i === 0 ? "background:#fffbea;" : ""}border-bottom:1px solid #f1f5f9;">
      <td style="padding:10px 10px 10px 14px;width:34px;">${avatarCell(p.display_name)}</td>
      <td style="padding:10px 4px;font-weight:${i === 0 ? 800 : 600};color:#0f172a;font-size:14px;">
        ${esc(p.display_name)}${i === 0 ? ' <span style="font-size:11px;color:#d97706;font-weight:700;">MVP</span>' : ""}
      </td>
      <td style="padding:10px 8px;text-align:right;color:#475569;font-size:13px;white-space:nowrap;">${p.wins}W / ${p.losses}L</td>
      <td style="padding:10px 14px;text-align:right;white-space:nowrap;">${eloChip(p.elo_delta)}</td>
    </tr>`).join("")

  const weeklySection = weekly.length ? `
    <div style="font-size:13px;font-weight:800;color:#0f172a;margin:4px 0 10px;">🔥 This Week's Champions</div>
    <table width="100%" cellpadding="0" cellspacing="0"
      style="border-collapse:collapse;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;margin-bottom:26px;">
      <thead><tr style="background:#f8fafc;">
        <th colspan="2" style="padding:9px 14px;text-align:left;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Player</th>
        <th style="padding:9px 8px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">This week</th>
        <th style="padding:9px 14px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Elo Δ</th>
      </tr></thead>
      <tbody>${weeklyRows}</tbody>
    </table>` : `
    <div style="background:#f8fafc;border:1px dashed #cbd5e1;border-radius:12px;padding:18px;text-align:center;color:#64748b;font-size:13px;margin-bottom:26px;">
      No matches recorded this week — get on court! 🏸
    </div>`

  // ── Section 2: Full (all-time) standings ──
  const standingRows = top5.map(p => {
    const isFirst = p.club_rank === 1
    return `
    <tr style="${isFirst ? "background:#fffbea;" : ""}border-bottom:1px solid #f1f5f9;">
      <td style="padding:10px 6px 10px 14px;width:26px;font-weight:${isFirst ? 800 : 400};color:${isFirst ? "#d97706" : "#64748b"};font-size:13px;">${medalFor(p.club_rank ?? 0)}</td>
      <td style="padding:10px 8px;width:34px;">${avatarCell(p.display_name)}</td>
      <td style="padding:10px 4px;font-weight:${isFirst ? 800 : 600};color:#0f172a;font-size:13px;">${esc(p.display_name)}</td>
      <td style="padding:10px 8px;text-align:right;font-weight:700;color:#0099b8;font-size:13px;">${Math.round(p.elo)}</td>
      <td style="padding:10px 8px;text-align:right;color:#475569;font-size:12px;white-space:nowrap;">${p.wins}W / ${p.games - p.wins}L</td>
      <td style="padding:10px 14px;text-align:right;color:#475569;font-size:12px;">${Number(p.win_pct).toFixed(0)}%</td>
    </tr>`
  }).join("")

  const standingsSection = top5.length ? `
    <div style="font-size:13px;font-weight:800;color:#0f172a;margin:4px 0 10px;">🏆 Overall Standings</div>
    <table width="100%" cellpadding="0" cellspacing="0"
      style="border-collapse:collapse;border:1px solid #e2e8f0;border-radius:12px;overflow:hidden;">
      <thead><tr style="background:#f8fafc;">
        <th colspan="3" style="padding:9px 14px;text-align:left;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Player</th>
        <th style="padding:9px 8px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Elo</th>
        <th style="padding:9px 8px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">W / L</th>
        <th style="padding:9px 14px;text-align:right;font-size:11px;font-weight:700;color:#64748b;letter-spacing:1px;text-transform:uppercase;">Win%</th>
      </tr></thead>
      <tbody>${standingRows}</tbody>
    </table>` : ""

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
<table width="100%" style="max-width:540px;" cellpadding="0" cellspacing="0">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#050d1a,#0d1f3a);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="font-size:12px;font-weight:600;color:rgba(0,180,216,.75);letter-spacing:2px;text-transform:uppercase;margin-bottom:8px;">This week in ${esc(club_name)}</div>
    <div style="font-size:24px;font-weight:800;color:#00b4d8;letter-spacing:-0.5px;">${mvp ? "🏆 MVP of the Week" : "📊 Weekly Rankings"}</div>
    ${mvp ? `<div style="font-size:17px;font-weight:800;color:#fff;margin-top:8px;">${esc(mvp.display_name)}</div>
    <div style="font-size:12px;color:rgba(255,255,255,.55);margin-top:2px;">${mvp.wins}W / ${mvp.losses}L this week${mvp.elo_delta >= 0 ? ` · +${mvp.elo_delta} Elo` : ` · ${mvp.elo_delta} Elo`}</div>` : ""}
  </td></tr>

  <!-- Body -->
  <tr><td style="background:#ffffff;padding:26px 32px 8px;border-radius:0 0 16px 16px;">

    <p style="margin:0 0 16px;font-size:14px;color:#334155;line-height:1.65;">${greeting}</p>
    <p style="margin:0 0 24px;font-size:14px;color:#334155;line-height:1.7;">${story}</p>

    ${heroesSection(heroes, heroDate)}
    ${weeklySection}
    ${standingsSection}

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

// Fetch both leaderboards for a club. Returns null when there's nothing to show.
async function getClubData(admin: ReturnType<typeof createClient>, clubId: string) {
  const { data: lb } = await admin.rpc("get_club_leaderboard", { p_club_id: clubId })
  const top5: LeaderboardRow[] = (lb ?? [])
    .filter((r: LeaderboardRow) => r.club_rank != null && r.games > 0)
    .slice(0, 5)
  const { data: wk } = await admin.rpc("get_club_weekly_summary", { p_club_id: clubId, p_days: 7 })
  const weekly: WeeklyRow[] = (wk ?? []).slice(0, 6)
  const { data: heroesRaw } = await admin.rpc("get_day_heroes", { p_club_id: clubId })
  const heroes = computeDayAwards(heroesRaw as { players?: DayHeroPlayer[] } | null)
  let heroDate = ""
  const rawDate = (heroesRaw as { date?: string } | null)?.date
  if (rawDate) {
    try {
      heroDate = new Date(rawDate + "T00:00:00").toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })
    } catch { heroDate = rawDate }
  }
  if (!top5.length && !weekly.length) return null
  return { top5, weekly, heroes, heroDate }
}

async function sendEmail(RESEND_API_KEY: string, to: string, subject: string, html: string): Promise<string | null> {
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: "Badminton 360 <noreply@badminton360.app>", to: [to], subject, html }),
  })
  if (resp.ok) return null
  return await resp.text()
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

    // Auth: verify_jwt=false so pg_cron can call it; must present the shared
    // secret (or the service-role key as bearer for manual/admin triggers).
    const secretHeader = req.headers.get("x-cron-secret") ?? ""
    const bearer = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "")
    const authorised =
      (CRON_SECRET && secretHeader === CRON_SECRET) ||
      (SUPABASE_SERVICE_KEY && bearer === SUPABASE_SERVICE_KEY)
    if (!authorised) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Body: { force?, club_id?, test_email? }
    //  - test_email → send exactly ONE preview email to that address
    //  - force      → ignore each club's schedule and send now
    //  - club_id    → restrict to a single club
    const body = await req.json().catch(() => ({})) as { force?: boolean; club_id?: string; test_email?: string }
    const force = body?.force === true
    const onlyClubId = body?.club_id ?? null
    const testEmail = typeof body?.test_email === "string" ? body.test_email.trim() : null

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    const { data: clubs, error: clubsErr } = await admin
      .from("clubs")
      .select("id, name, digest_dow, digest_hour, digest_tz, digest_enabled")
    if (clubsErr) throw new Error(`clubs fetch: ${clubsErr.message}`)

    // ── Test mode: one preview email to a single address ──
    if (testEmail) {
      const candidates = (clubs ?? []).filter(c => !onlyClubId || c.id === onlyClubId)
      for (const club of candidates) {
        const cd = await getClubData(admin, club.id)
        if (!cd) continue
        const html = buildDigestHtml({ club_name: club.name, nickname: "", top5: cd.top5, weekly: cd.weekly, heroes: cd.heroes, heroDate: cd.heroDate })
        const mvpName = cd.weekly[0]?.display_name ?? cd.top5[0]?.display_name ?? club.name
        const err = await sendEmail(RESEND_API_KEY, testEmail, `🏆 Weekly Rankings — ${club.name} (preview)`, html)
        return new Response(JSON.stringify({ ok: !err, test: testEmail, club: club.name, mvp: mvpName, error: err }), {
          status: err ? 502 : 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
        })
      }
      return new Response(JSON.stringify({ ok: false, test: testEmail, error: "No club with data to preview" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // ── Which clubs are due right now (or all, when force) ──
    const dueClubs = (clubs ?? []).filter(club => {
      if (onlyClubId && club.id !== onlyClubId) return false
      if (force) return true
      if (club.digest_enabled === false) return false
      const { dow, hour } = nowInTz(club.digest_tz || "Asia/Dubai")
      return dow === club.digest_dow && hour === club.digest_hour
    })
    if (!dueClubs.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, clubs: 0, due: 0 }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Map user_id → email once
    const { data: authData } = await admin.auth.admin.listUsers({ perPage: 1000 })
    const emailMap = new Map<string, string>()
    for (const u of authData?.users ?? []) if (u.email) emailMap.set(u.id, u.email)

    let totalSent = 0
    const allErrors: string[] = []
    let batchCount = 0

    for (const club of dueClubs) {
      const cd = await getClubData(admin, club.id)
      if (!cd) continue

      const { data: members } = await admin.from("club_members").select("user_id").eq("club_id", club.id)
      if (!members?.length) continue

      const userIds = members.map((m: { user_id: string }) => m.user_id)
      const { data: profiles } = await admin
        .from("user_profiles").select("user_id, nickname, email_prefs").in("user_id", userIds)
      const profileMap = new Map<string, { nickname: string | null; email_prefs: Record<string, unknown> | null }>()
      for (const p of profiles ?? []) profileMap.set(p.user_id, { nickname: p.nickname, email_prefs: p.email_prefs })

      const mvpName = cd.weekly[0]?.display_name ?? cd.top5[0]?.display_name ?? club.name

      for (const uid of userIds) {
        const email = emailMap.get(uid)
        if (!email) continue
        const profile = profileMap.get(uid)
        const prefs   = profile?.email_prefs ?? null
        const wantsDigest = !prefs || (prefs.weekly_digest !== false && prefs.weekly_digest !== "false")
        if (!wantsDigest) continue

        const html = buildDigestHtml({ club_name: club.name, nickname: profile?.nickname ?? "", top5: cd.top5, weekly: cd.weekly, heroes: cd.heroes, heroDate: cd.heroDate })
        const err = await sendEmail(RESEND_API_KEY, email, `🏆 ${mvpName} tops ${club.name} — Weekly Rankings`, html)
        if (err) allErrors.push(`${email}(${club.name}): ${err}`)
        else totalSent++

        // Resend free tier = 2 requests/second — pause after every 2 sends.
        batchCount++
        if (batchCount % 2 === 0) await sleep(1100)
      }
    }

    return new Response(
      JSON.stringify({ ok: true, sent: totalSent, clubs: dueClubs.length, errors: allErrors }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
