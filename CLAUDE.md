# CLAUDE.md — Badmint Project Context

> This file is the single source of truth for the Badmint app.
> When opening this project in Claude Code, reference this file first.
> Command: `claude` in the project root → paste or reference this file.

---

## What is Badmint?

A free, installable Progressive Web App (PWA) for badminton doubles ranking.
Originally built for a 15-member team in Dubai (UAE) that plays 2 hours daily,
with 4–8 members showing up each session. Teams change and mix every day.

**Vision:** Publish for free to every badminton team in the UAE (and beyond).
Multi-club from day one — each court/team is an isolated "club."

---

## Stack

| Layer       | Technology                                |
|-------------|-------------------------------------------|
| Frontend    | Vue 3 (Composition API) + Vite            |
| Styling     | Tailwind CSS v3                           |
| PWA         | vite-plugin-pwa (installable, offline)    |
| Auth        | Supabase Auth (Google OAuth)              |
| Database    | Supabase (PostgreSQL)                     |
| Hosting     | Vercel (free tier, static build)          |

**Fonts:** Bricolage Grotesque (display) + Outfit (body) via Google Fonts.
**Theme:** Dark (`#0b1120` base) + teal (`#0f766e`) primary + amber accents.

---

## Project Structure

```
badmint/
├── index.html                    # Entry point, font imports
├── vite.config.js                # Vite + PWA config
├── tailwind.config.js
├── postcss.config.js
├── package.json
├── .env.example                  # Copy to .env and fill keys
├── .env                          # NEVER commit — gitignored
├── public/
│   ├── favicon.svg
│   ├── icon-192.png              # Replace with real icons before launch
│   └── icon-512.png
├── supabase/
│   └── schema.sql                # Full DB schema — run once in Supabase SQL Editor
└── src/
    ├── main.js
    ├── App.vue                   # Shell: top bar, club switcher, bottom nav
    ├── style.css                 # Tailwind + global classes (.card, .btn, .input)
    ├── router/
    │   └── index.js              # Routes with auth guard
    ├── lib/
    │   └── supabase.js           # Supabase client (reads from .env)
    ├── composables/
    │   ├── useAuth.js            # user ref, signInWithGoogle, signOut
    │   └── useClub.js            # clubs, currentClub, loadClubs, createClub, isManager
    ├── components/
    │   ├── InfoTip.vue           # Inline ? tooltip component
    │   └── PageHeader.vue        # Reusable page header with collapsible help slot
    └── views/
        ├── Login.vue             # Google sign-in + feature overview
        ├── Dashboard.vue         # Leaderboard + podium + best pair
        ├── AddMatch.vue          # Pick 4 players, assign sides, record score
        ├── Players.vue           # Roster management
        ├── Compare.vue           # Head-to-head + stats comparison + best pairs
        ├── RankingGuide.vue      # Full in-app ranking explainer (standalone page)
        └── Manage.vue            # Create clubs, tune weights, view members
```

---

## Environment Variables

```bash
# .env (copy from .env.example)
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

Both are exposed to the browser (Vite VITE_ prefix). This is safe — Supabase
Row-Level Security controls what each user can read/write.

---

## Database Schema (summary)

All tables are in the `public` schema. Full DDL in `supabase/schema.sql`.

### Tables

| Table                | Purpose                                                  |
|----------------------|----------------------------------------------------------|
| `clubs`              | A team/court. Created by a user (owner).                 |
| `club_members`       | Many-to-many: user ↔ club, with role (owner/manager/player) |
| `ranking_config`     | Per-club Elo weights and K-factor                        |
| `players`            | Roster entries. `user_id` is nullable (guest players OK) |
| `attendance`         | One row per player per day. Unique constraint.           |
| `matches`            | A doubles match (club + date + created_by)               |
| `match_sides`        | 2 rows per match: side A and side B with score + winner  |
| `match_participants` | 4 rows per match: player + elo_before + elo_after        |

### Key RPCs (Postgres functions called via `supabase.rpc()`)

**`record_match(p_club_id, p_played_on, p_side_a[], p_side_b[], p_score_a, p_score_b)`**
- Called from `AddMatch.vue`
- Validates caller is manager/owner
- Calculates Elo for both sides (average-based doubles Elo)
- Inserts match + sides + participants
- Updates `players.elo` for all 4
- Marks attendance for all 4 (upsert, idempotent)
- Returns `match_id` (uuid)

**`create_club(p_name)`**
- Creates club + makes caller owner + inserts default ranking_config
- Returns `club_id` (uuid)

### Views (used directly in frontend queries)

**`v_leaderboard`**
Columns: `id, club_id, display_name, elo, days_played, games, wins, win_pct,
elo_score, part_score, composite, club_rank`
- `composite` = weighted blend of normalised Elo + normalised attendance
- `club_rank` = window rank within club sorted by composite desc

**`v_best_pairs`**
Columns: `club_id, p1, p2, p1_name, p2_name, games, wins, win_pct`
- Every pair who played on the same side, their combined record

**`v_head_to_head`**
Columns: `club_id, player_a, player_b, meetings, a_wins, b_wins`
- Every time two players were on OPPOSITE sides
- Note: Check both (A,B) and (B,A) orderings in queries (see Compare.vue)

### Row-Level Security

Every table has RLS enabled. Helper functions:
- `is_member(club_id uuid) → boolean` — user is any member of that club
- `is_manager(club_id uuid) → boolean` — user is owner or manager

General rules:
- Members can SELECT from everything in their club
- Only managers/owners can INSERT/UPDATE/DELETE

---

## Ranking System (reference for all future changes)

### Elo (skill)
- Start: 1000
- Doubles: average the two players' Elo per side
- Formula: `new_elo = old_elo + K × (actual - expected)`
  - `expected = 1 / (1 + 10^((opp_avg - own_avg)/400))`
  - `actual` = 1 (win) or 0 (loss)
- Default K = 24 (tunable per club in `ranking_config.k_factor`)

### Attendance
- All-time count of distinct days played (`attendance` table)
- Does not decay. Founding members build an advantage over time.
- To switch to rolling window: add `WHERE played_on >= current_date - 30`
  to the attendance CTE in `v_leaderboard`

### Composite Score
- Both Elo and attendance normalised 0–100 within the club (min-max)
- `composite = elo_weight × elo_score + participation_weight × part_score`
- Defaults: elo_weight=0.7, participation_weight=0.3
- Configurable per club in `ranking_config` table
- Frontend allows managers to change in Manage → Ranking Weights

---

## Components Reference

### `PageHeader.vue`
Props: `icon`, `title`, `subtitle`, `help` (optional string)
Slot: `#help` (overrides `help` prop with rich HTML)
Has a "? Help" toggle button when help/slot is provided.

```vue
<PageHeader icon="🏆" title="Rankings" subtitle="Live leaderboard">
  <template #help>
    <p>Custom help content here.</p>
  </template>
</PageHeader>
```

### `InfoTip.vue`
Inline `?` button that shows a tooltip on click.
```vue
<InfoTip text="This column shows your blended rank score." />
```

### `useClub.js`
```js
const { clubs, currentClub, loadClubs, selectClub, createClub, isManager } = useClub()
// currentClub.value → { club_id, role, clubs: { name } }
// isManager() → true if role is 'owner' or 'manager'
```

### `useAuth.js`
```js
const { user, ready, signInWithGoogle, signOut } = useAuth()
// user.value → Supabase User object or null
// ready.value → true once session check resolves
```

---

## Known Limitations / Future Work

### High priority
- [ ] **Undo match** — reverse Elo using stored `elo_before` values, delete rows
- [ ] **Manager invite by email** — write RPC that inserts a pending invite, email via Supabase Edge Function
- [ ] **Real app icons** — replace 1×1 placeholder PNGs in `public/`
- [ ] **Match history feed** — list of recent matches per club with scores

### Medium priority
- [ ] **Most improved** — Elo delta over last 30 days (add windowed view)
- [ ] **Form guide** — last 5 results per player (W/W/L/W/L dots)
- [ ] **Current streak** — consecutive wins or losses
- [ ] **Nemesis stat** — opponent you lose to most (from `v_head_to_head`)
- [ ] **Season reset** — snapshot current Elo, reset to 1000 for new season
- [ ] **Push notifications** — when a match is recorded (Supabase Realtime)

### Low priority / nice to have
- [ ] **Club invite link** — shareable URL that auto-adds as player role
- [ ] **Player profile page** — full stats page per player
- [ ] **Export to PDF** — monthly leaderboard report
- [ ] **Dark/light theme toggle**
- [ ] **UAE Arabic localisation** (RTL support)

---

## Deployment

### Local dev
```bash
cp .env.example .env   # fill in your Supabase keys
npm install
npm run dev            # http://localhost:5173
```

### Vercel
1. Push to GitHub
2. Import repo in Vercel → Framework: Vite, Output: dist
3. Add env vars: `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`
4. Deploy → add Vercel URL to Supabase Auth redirect URLs

### Supabase setup order
1. Create project (region: Singapore for UAE latency)
2. SQL Editor → run `supabase/schema.sql`
3. Authentication → Providers → Google → enable → paste Client ID + Secret
4. Authentication → URL Configuration → add your local + Vercel URLs

### Google OAuth
1. Google Cloud Console → New project → OAuth consent screen (External)
2. Credentials → OAuth Client ID → Web → add Supabase callback URL
3. Copy Client ID + Secret → paste into Supabase Google provider

---

## Useful Supabase Queries for Debugging

```sql
-- Check current leaderboard
SELECT * FROM v_leaderboard WHERE club_id = 'YOUR-CLUB-ID' ORDER BY club_rank;

-- Check a player's Elo history
SELECT mp.elo_before, mp.elo_after, m.played_on
FROM match_participants mp
JOIN match_sides ms ON ms.id = mp.match_side_id
JOIN matches m ON m.id = ms.match_id
WHERE mp.player_id = 'PLAYER-ID'
ORDER BY m.played_on DESC;

-- Check attendance count
SELECT player_id, count(*) as days FROM attendance GROUP BY player_id;

-- Reset a player's Elo (dev only)
UPDATE players SET elo = 1000 WHERE club_id = 'CLUB-ID';

-- Check ranking config
SELECT * FROM ranking_config;
```

---

## App Name & Branding

- **Name:** Badmint
- **Tagline:** "Ranking system for your badminton team"
- **Primary colour:** `#0f766e` (teal-600)
- **Background:** `#0b1120` with radial teal + amber gradients
- **Accent:** `#fbbf24` (amber-400)
- **Font display:** Bricolage Grotesque
- **Font body:** Outfit

---

## Notes for Claude Code Sessions

- Always check `supabase/schema.sql` before modifying DB queries — column names matter.
- Views (`v_leaderboard` etc.) are not materialised — they recompute on every query. Fine for 15–500 players; consider `MATERIALIZED VIEW` + periodic refresh if club grows to 1000+.
- `record_match` is the only write path for match data. Don't bypass it with direct inserts — it handles Elo + attendance atomically.
- `is_manager()` and `is_member()` use `auth.uid()` which is only set in RLS context (client queries). In SQL Editor, they return false — test with a real logged-in user.
- The `v_head_to_head` view stores ONE row per (player_a, player_b) ordering. In Compare.vue, both orderings are queried and merged. Keep this in mind if rewriting the query.
