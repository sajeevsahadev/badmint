# Badmint 🏸

A free, installable PWA for badminton doubles ranking. Multi-club ready
(your team + the court next door + every team in the UAE). Google login,
Elo-based skill ranking, attendance weightage, and a full analytics dashboard.

**Stack:** Vue 3 (Composition API) · Tailwind · Supabase (Postgres + Auth) · Vercel · vite-plugin-pwa

---

## How ranking works

- **Elo per player** (doubles): each side's average rating sets the expected
  result; winners gain, losers lose. Mixing teams every day is fine — Elo is
  individual. Beating a stronger pair earns more.
- **Attendance score**: separate all-time `days_played` count, so regulars are
  rewarded without polluting skill.
- **Composite points** = `elo_weight × normalizedElo + participation_weight × normalizedAttendance`
  (defaults 0.7 / 0.3, tunable per club in the Manage tab).

All math lives in PostgreSQL views (`v_leaderboard`, `v_best_pairs`,
`v_head_to_head`) — nothing computed in the browser.

---

## 1. Prerequisites

- Node.js 18+
- A [Supabase](https://supabase.com) account (free)
- A [Vercel](https://vercel.com) account (free)
- A Google Cloud project for OAuth (free)
- A GitHub repo

## 2. Supabase setup

1. Create a new Supabase project. Note **Project URL** and **anon public key**
   (Settings → API).
2. Open **SQL Editor**, paste the contents of `supabase/schema.sql`, run it.
3. **Authentication → Providers → Google**: enable, paste your Google OAuth
   Client ID + Secret.
4. **Authentication → URL Configuration**: add your local `http://localhost:5173`
   and your Vercel URL (e.g. `https://shuttle-rank.vercel.app`) to **Redirect URLs**
   and **Site URL**.

### Google OAuth credentials
- Google Cloud Console → APIs & Services → Credentials → Create OAuth client ID
  → Web application.
- **Authorized redirect URI**: copy the callback URL Supabase shows on the Google
  provider screen (looks like `https://YOUR-PROJECT.supabase.co/auth/v1/callback`).

## 3. Run locally

```bash
cp .env.example .env        # fill in your Supabase URL + anon key
npm install
npm run dev
```

Open the app, sign in with Google, go to **Manage → Create a club**, add players,
then record matches.

## 4. Deploy to Vercel

1. Push this folder to GitHub.
2. Vercel → **New Project** → import the repo. It auto-detects Vite
   (build: `npm run build`, output: `dist`).
3. Add Environment Variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
4. Deploy. Add the resulting URL to Supabase redirect URLs (step 2.4).
5. On a phone, open the site → browser menu → **Add to Home Screen**. Installed PWA.

## 5. Roles

- **owner**: created the club.
- **manager**: can add players, record matches, tune weights.
- **player**: read-only dashboards.

Set roles in the `club_members` table (Supabase Table Editor) or extend the
Manage screen with an invite RPC. A new manager must sign in once first so their
`auth.users` row exists.

## 6. Replace the placeholder icons

`public/icon-192.png` and `public/icon-512.png` are 1×1 placeholders. Drop in
real 192² and 512² PNGs before publishing.

---

## Dashboard features included
Leaderboard (composite + Elo + win% + days), top-3 podium, best pair,
head-to-head (rank + opposite-side record), per-club tunable weights.

### Easy next additions (views already model the data)
- Most improved (Elo delta last 30 days — add a windowed view)
- Current streak / form guide (last 5 W/L from `match_participants` ordered by date)
- Nemesis (worst head-to-head opponent — already in `v_head_to_head`)
- Match history feed with undo (reverse Elo from stored `elo_before`)
