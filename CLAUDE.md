# CLAUDE.md — Badmint Complete Project Context

> **Single source of truth.** Read this file at the start of every Claude Code session.
> Last updated: June 2026 — reflects all migrations v1–v6.

---

## 1. Business Context

### What is Badmint?
A free, installable **Progressive Web App (PWA)** for badminton doubles ranking in the UAE.

**Typical use-case:**  
A group of 6–30 friends books a badminton court at a sports academy or school facility every Saturday morning 6–8am, or weekday evenings. When they arrive, a manager opens the app, picks 4 players, assigns them to Side A / Side B, enters the score, and hits Record. The app calculates Elo ratings automatically. Everyone can see the leaderboard on their phone.

**Target users:**
- Players — view rankings, profile, match history
- Managers/Owners — record matches, manage roster, invite players, set up clubs
- Future: Facility admins, App Administrators

**Vision:** Free for every badminton group in the UAE (and globally). Multi-club from day one — each court/group is an isolated "club". Clubs can link to real facility profiles so anyone can see who is playing where.

---

## 2. Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vue 3 (Composition API) + Vite |
| Styling | Tailwind CSS v3 + custom CSS (neo/cyberpunk theme) |
| PWA | vite-plugin-pwa — installable, offline-capable |
| Auth | Supabase Auth — Google OAuth only |
| Database | Supabase (PostgreSQL) |
| Hosting | Vercel (free tier, auto-deploy from GitHub) |
| Repo | `https://github.com/sajeevsahadev/badmint` |
| Live URL | `https://badmint.vercel.app` |

**Design system:**
- Background: `#050d1a` (deep navy)
- Primary/neon: `#00e5ff` (electric cyan)
- Secondary: `#a855f7` (violet)
- Accent: `#fbbf24` (gold/amber)
- Fonts: Bricolage Grotesque (display) + Outfit (body)
- Cards: glassmorphism — `bg-white/[0.03]` + `backdrop-blur-xl`
- Custom CSS classes: `.card`, `.card-neon`, `.card-violet`, `.card-amber`, `.btn-primary`, `.btn-ghost`, `.btn-violet`, `.btn-success`, `.btn-danger`, `.gradient-text`, `.text-neon`, `.text-violet`, `.text-gold`, `.badge-*`, `.shimmer`, `.fade-up`

---

## 3. Project File Structure

```
badmint/
├── index.html                      # SEO meta, OG, JSON-LD, PWA icons, fonts
├── vite.config.js                  # Vite + PWA manifest config
├── tailwind.config.js
├── public/
│   ├── favicon.svg
│   ├── icon-192.png
│   ├── icon-512.png
│   ├── robots.txt
│   └── sitemap.xml
├── supabase/
│   ├── schema.sql                  # v1: core tables + Elo engine
│   ├── join_schema.sql             # v1.5: join_requests, club_invites
│   ├── v2_schema.sql               # v2: user_profiles, club ranking, match numbers, top scorers
│   ├── v3_schema.sql               # v3: full_name, emirate, country on user_profiles
│   ├── v4_schema.sql               # v4: is_active, delete_match, toggle_player_active
│   ├── v5_schema.sql               # v5: app_sessions, activity_log, online status
│   └── v6_schema.sql               # v6: facilities, facility_schedule, facility_bookings
└── src/
    ├── main.js
    ├── App.vue                     # Shell: top bar, nav, PWA banners, session tracking
    ├── style.css                   # Design system (neo theme)
    ├── router/
    │   └── index.js                # All routes + auth guard + sessionStorage redirect
    ├── lib/
    │   └── supabase.js             # Client: persistSession + autoRefreshToken + detectSessionInUrl
    ├── composables/
    │   ├── useAuth.js              # user, ready, signInWithGoogle, signOut
    │   ├── useClub.js              # clubs, currentClub, loadClubs, selectClub, createClub, isManager
    │   ├── useInstall.js           # PWA install prompt (Android + iOS detection)
    │   └── useSession.js           # startSession, trackPage, trackAction, endSession
    ├── components/
    │   ├── InfoTip.vue             # Inline ? tooltip
    │   └── PageHeader.vue          # icon + title + subtitle + collapsible #help slot
    └── views/
        ├── Login.vue               # Google sign-in, feature grid, PWA install buttons
        ├── Dashboard.vue           # Leaderboard, podium top 3, best pair, quick links
        ├── AddMatch.vue            # Pick 4 active players, assign sides, enter score + name
        ├── Matches.vue             # Match history (newest first), expand/rename/delete
        ├── Players.vue             # Roster: add+invite, active/inactive toggle, online status
        ├── Compare.vue             # Head-to-head + stat comparison + best pairs
        ├── RankingGuide.vue        # In-app ranking explainer
        ├── Manage.vue              # Club admin: requests, invites, weights, facility, roles
        ├── Explore.vue             # Public: Clubs tab | Facilities tab | Players tab
        ├── JoinClub.vue            # Browse clubs + join request + invite token onboarding
        ├── Profile.vue             # Own profile editor (nickname, phone, bio, emirate)
        ├── PlayerProfile.vue       # Public player page (stats, matches — no phone/email)
        ├── ClubProfile.vue         # Public club page (stats, members, facility link)
        └── FacilityProfile.vue     # Public facility page (schedule, bookings, clubs)
```

---

## 4. Routes

| Path | View | Auth | Notes |
|---|---|---|---|
| `/login` | Login.vue | Public | Google OAuth entry |
| `/explore` | Explore.vue | Public | 3 tabs: Clubs, Facilities, Players |
| `/facility/:id` | FacilityProfile.vue | Public | Anyone can see schedule + bookings |
| `/dashboard` | Dashboard.vue | Required | Club leaderboard |
| `/matches` | Matches.vue | Required | Match history + `?open=matchId` deep-link |
| `/match` | AddMatch.vue | Required | Record a match (managers only) |
| `/players` | Players.vue | Required | Roster management |
| `/compare` | Compare.vue | Required | Head-to-head stats |
| `/guide` | RankingGuide.vue | Required | Ranking explainer |
| `/manage` | Manage.vue | Required | Club administration |
| `/join` | JoinClub.vue | Required | Browse + join + invite token |
| `/profile` | Profile.vue | Required | Edit own profile |
| `/player/:id` | PlayerProfile.vue | Required | Public player view |
| `/club/:id` | ClubProfile.vue | Required | Public club view |

**Auth guard logic** (`router/index.js`):
- Uses `sessionStorage` key `bm_after_login` ONLY for `/join` and `/player/:id` deep-links
- Redirect is consumed only when landing on `/` (post-OAuth) — NOT on every navigation
- Supabase client has `persistSession: true` — users stay logged in until explicit sign-out

---

## 5. Full Database Schema

### Migration run order (all in Supabase SQL Editor)
1. `supabase/schema.sql` — core tables
2. `supabase/join_schema.sql` — join/invite tables
3. `supabase/v2_schema.sql` — user profiles, match numbers, club ranking
4. `supabase/v3_schema.sql` — extended profile fields
5. `supabase/v4_schema.sql` — active/inactive, delete match
6. `supabase/v5_schema.sql` — sessions, activity log, online status
7. `supabase/v6_schema.sql` — facility master

---

### Core Tables (schema.sql)

**`clubs`**
```
id, name, created_by (→ auth.users), created_at
+ [v2] emirates, facility_name, facility_address, maps_url, description
+ [v6] facility_id (→ facilities)
```
- RLS: members read their clubs; anyone logged in can create via `create_club()`

**`club_members`**
```
club_id (→ clubs), user_id (→ auth.users), role ('owner'|'manager'|'player'), joined_at
```
- PK: (club_id, user_id)
- Role change via UI in Manage.vue (owner can promote to any role; manager can promote players)

**`ranking_config`**
```
club_id (PK, → clubs), elo_weight (0.7), participation_weight (0.3), k_factor (24), starting_elo (1000)
```

**`players`**
```
id, club_id (→ clubs), display_name, user_id (→ auth.users, nullable), elo (default 1000)
created_at
+ [v4] is_active (boolean, default true)
```
- `user_id` is nullable — guest players (no Google account) are supported
- Inactive players excluded from leaderboard, top scorers, and Add Match picker

**`attendance`**
```
id, club_id, player_id (→ players), played_on (date)
UNIQUE(player_id, played_on)
```

**`matches`**
```
id, club_id, played_on, created_by (→ auth.users), created_at
+ [v2] match_number (int, auto via trigger), display_name (text, editable)
```
- `match_number` auto-assigned per club by `trg_auto_match_number` trigger (fires BEFORE INSERT)
- `display_name` defaults to `'Match #N'` if not provided; editable via `rename_match()` RPC
- Triggers also: `trg_auto_facility_booking` (AFTER INSERT → creates facility_bookings row if club has facility_id)

**`match_sides`**
```
id, match_id (→ matches), side ('A'|'B'), score, is_winner
UNIQUE(match_id, side)
```

**`match_participants`**
```
id, match_side_id (→ match_sides), player_id (→ players, ON DELETE CASCADE), elo_before, elo_after
```

---

### Join / Invite Tables (join_schema.sql)

**`join_requests`**
```
id, club_id, user_id, user_email, user_name, status ('pending'|'approved'|'rejected'), created_at
UNIQUE(club_id, user_id)
```

**`club_invites`**
```
id, club_id, email, token (unique, 32-byte hex), status ('pending'|'accepted'|'expired')
invited_by, created_at, expires_at (now + 7 days)
```

---

### User Profiles (v2 + v3)

**`user_profiles`**
```
user_id (PK, → auth.users), nickname, phone, bio, avatar_url
+ [v3] full_name, emirate, country (default 'UAE')
+ [v5] last_seen_at (timestamptz) — updated on every navigation for online status
updated_at
```
- RLS: public read (all columns); only own user can write
- **Privacy rule**: `phone` and `email` are NEVER shown to other users. Only `nickname`, `bio`, `emirate` are public. Always query only those 3 columns in PlayerProfile.vue.

---

### Club Ranking (v2)

**`v_club_rankings`** (view, not materialised)
```
club_id, name, emirates, facility_name, facility_address, maps_url, description
matches_30d, active_30d, total_members, last_played
club_score, club_rank
```
**Club Score Formula:**
```
score = (
  min(matches_30d / active_30d × 15, 50)   -- activity per member, capped at 50
  + active_30d / total_members × 25          -- engagement (% of members active)
) × recency_multiplier + 10 base
```
Recency: 1.0 (last 7d) / 0.7 (7–14d) / 0.4 (14–30d) / 0.1 (>30d)

**`v_top_scorers`** (view)
```
player_id, club_id, club_name, emirates, public_name (nickname or display_name)
elo, games, wins, win_pct, days_played, global_rank
```
- Filtered: `is_active = true AND games >= 1`
- Ordered by `p.elo desc` (Elo is cross-club comparable; composite score is per-club only)

---

### Active/Inactive + Delete Match (v4)

**`players.is_active`** (boolean, default true)
- `toggle_player_active(p_player_id)` — managers only; returns new boolean status
- Inactive players excluded from: `v_leaderboard`, `v_top_scorers`, Add Match player picker
- Inactive players still appear in Matches history and their past Elo is preserved

**`delete_match(p_match_id)`** — managers only
1. Deletes the match (cascades to match_sides, match_participants)
2. Resets ALL club players to `starting_elo` (from ranking_config)
3. Deletes all attendance for the club
4. Replays every remaining match in chronological order, recalculating Elo
5. Updates `elo_before`/`elo_after` in match_participants for history accuracy
6. Rebuilds attendance from scratch

---

### Sessions & Activity Log (v5)

**`app_sessions`**
```
id, user_id, ip_address (from PostgREST x-forwarded-for header), user_agent
logged_in_at, last_active_at, logged_out_at, is_active
```

**`activity_log`**
```
id, session_id (→ app_sessions), user_id, event_type, event_data (jsonb), created_at
```
- `event_type` values: `'page_view'` | `'match_created'` | `'player_added'` | etc.
- `event_data` example: `{ "path": "/dashboard" }` or `{ "match_id": "uuid" }`
- Used for future Admin dashboard — tracks all navigation and actions per session

**RPCs:**
- `create_session(p_user_agent)` — called on login; captures IP from request headers; returns `session_id`
- `log_activity(p_session_id, p_event_type, p_event_data)` — called on every route change
- `end_session(p_session_id)` — called on explicit sign-out

**Online status** (via `user_profiles.last_seen_at`):
- 🟢 Green pulse dot: `last_seen_at >= now() - interval '10 minutes'`
- 🟠 Orange dot: `last_seen_at >= now() - interval '1 month'`
- ⊗ Grey X: `last_seen_at < now() - interval '1 month'` or null
- Only shown for players with a linked `user_id` (not guest players)

---

### Facility Master (v6)

**`facilities`**
```
id, name, address, emirate, maps_url, description
image_url (paste any URL; file upload needs Supabase Storage — not yet set up)
phone, website, created_by (→ auth.users), created_at
```
- RLS: public read; creator can update

**`facility_schedule`**
```
id, facility_id (→ facilities), day_of_week (0=Sun…6=Sat)
start_time, end_time, slot_label, is_active
```
- Managed by facility creator only

**`facility_bookings`**
```
id, facility_id, club_id, booked_date, start_time (default '00:00'), end_time
notes, auto_booked (boolean), created_by, created_at
UNIQUE(facility_id, club_id, booked_date, start_time)
```
- **Auto-created** by trigger `trg_auto_facility_booking` when a match is recorded for a club that has `facility_id` set
- Trigger finds the matching `facility_schedule` slot for that day of week to fill in times

**`clubs.facility_id`** (→ facilities, nullable)
- Links club to its home facility; set via `set_club_facility(p_club_id, p_facility_id)`

**RPCs:**
- `get_facilities(p_emirate, p_search)` — public; returns all facilities with club_count + upcoming_count
- `get_facility_detail(p_facility_id)` — public; returns JSON `{ facility, schedule, bookings, clubs }`
- `create_facility(...)` — any authenticated user; returns facility uuid
- `update_facility(p_id, ...)` — facility creator only
- `set_club_facility(p_club_id, p_facility_id)` — club manager only
- `add_facility_slot(p_facility_id, p_day, p_start, p_end, p_label)` — facility creator only
- `delete_facility_slot(p_slot_id)` — facility creator only

---

### Leaderboard View (updated in v4)

**`v_leaderboard`**
```
id, club_id, display_name, elo, days_played, games, wins, win_pct
elo_score, part_score, composite, club_rank
```
- Filters: `WHERE p.is_active = true`
- `composite = elo_weight × elo_score + participation_weight × part_score` (both normalised 0–100 within club)
- `club_rank` = window RANK() partitioned by club_id, ordered by composite DESC

---

## 6. Key RPCs Summary

| RPC | Auth | Description |
|---|---|---|
| `record_match(p_club_id, p_played_on, p_side_a[], p_side_b[], p_score_a, p_score_b, p_display_name?)` | Manager | Full Elo engine — only write path for match data |
| `delete_match(p_match_id)` | Manager | Delete + full Elo recalculation |
| `create_club(p_name)` | Any auth | Creates club + owner membership + ranking_config |
| `create_session(p_user_agent)` | Any auth | Creates session record; returns session UUID |
| `log_activity(p_session_id, p_event_type, p_event_data)` | Any auth | Logs a page view or action |
| `end_session(p_session_id)` | Any auth | Marks logout timestamp |
| `request_join(p_club_id)` | Any auth | Player requests to join a club |
| `approve_join(p_request_id)` | Manager | Approves request; adds to club_members + players |
| `reject_join(p_request_id)` | Manager | Rejects join request |
| `invite_member(p_club_id, p_email)` | Manager | Creates invite token; returns token string |
| `accept_invite(p_token)` | Any auth | Accepts invite; adds to club + creates player row |
| `upsert_profile(p_nickname, p_full_name?, p_phone?, p_bio?, p_emirate?, p_country?)` | Own user | Creates/updates user_profiles row |
| `toggle_player_active(p_player_id)` | Manager | Toggles is_active; returns new boolean |
| `rename_match(p_match_id, p_name)` | Manager | Updates match display_name |
| `update_club_facility(p_club_id, ...)` | Manager | Updates clubs' direct facility fields |
| `get_club_players(p_club_id)` | Any auth | Returns players + online_status for a club |
| `get_public_clubs()` | Public | All clubs with ranking info (security definer) |
| `get_top_scorers(p_limit?)` | Public | Global Elo leaderboard (security definer) |
| `get_facilities(p_emirate?, p_search?)` | Public | All facilities with stats |
| `get_facility_detail(p_facility_id)` | Public | Full facility JSON (schedule + bookings + clubs) |
| `create_facility(...)` | Any auth | Creates a facility master record |
| `update_facility(p_id, ...)` | Creator | Updates facility info |
| `set_club_facility(p_club_id, p_facility_id)` | Manager | Links/unlinks club ↔ facility |
| `add_facility_slot(...)` | Creator | Adds a weekly schedule slot |
| `delete_facility_slot(p_slot_id)` | Creator | Removes a schedule slot |

---

## 7. Composables

### `useAuth.js`
```js
const { user, ready, signInWithGoogle, signOut } = useAuth()
// user.value → Supabase User object or null
// ready.value → true once initial session check resolves
// Session persists in localStorage — user stays logged in until signOut()
```

### `useClub.js`
```js
const { clubs, currentClub, loadClubs, selectClub, createClub, isManager } = useClub()
// currentClub.value → { club_id, role, clubs: { name } }
// isManager() → true if role is 'owner' or 'manager'
// selectClub(c) → sets currentClub + saves to localStorage
```

### `useInstall.js`
```js
const { canInstall, isIOS, isInstalled, promptInstall } = useInstall()
// canInstall → true on Android/Chrome when PWA installable
// isIOS → true on iPhone/iPad (shows manual instructions instead)
// promptInstall() → triggers the browser install prompt
```

### `useSession.js`
```js
const { sessionId, startSession, trackPage, trackAction, endSession } = useSession()
// startSession() — call on login; creates app_sessions row; fire-and-forget
// trackPage(path) — call on every route change; logs page_view to activity_log
// trackAction(type, data) — call on significant actions (match_created, etc.)
// endSession() — call before signOut()
```

---

## 8. App Shell (App.vue)

- **Loading splash** shown while `ready === false`
- **Top bar**: Badmint logo | club switcher (select) | iOS install trigger | profile avatar (→ /profile) | Sign out
- **PWA install banners**: Android `beforeinstallprompt` banner + iOS share instructions
- **No-club welcome screen**: shown when `!currentClub && route not in clubFreeRoutes`; offers Browse/Join/Create
- **Bottom nav** (5 tabs): Rankings | Matches | Explore | Players | Manage
  - Manage tab shows a red badge dot when there are pending join requests
  - Badge count loaded on init and on every route change
- Session started on user login; page tracked on every route change; session ended on logout

---

## 9. Ranking System

### Elo (skill)
- Starting Elo: 1000 (from `ranking_config.starting_elo`)
- Doubles: average the two players' Elo per side before calculating expected score
- Formula: `new_elo = old_elo + K × (actual − expected)`
  - `expected = 1 / (1 + 10^((opp_avg − own_avg) / 400))`
  - `actual` = 1 (win) / 0 (loss)
- K = 24 default, configurable per club (8–64)

### Attendance
- All-time count of distinct days played (rows in `attendance`)
- Does not decay. Founding members accumulate advantage.

### Composite Score (per-club ranking)
```
composite = elo_weight × elo_score + participation_weight × part_score
```
Both `elo_score` and `part_score` normalised 0–100 within the club (min-max).
Defaults: elo_weight=0.7, participation_weight=0.3 (configurable in Manage → Ranking Weights).

### Global Top Scorers
Ranked by raw Elo (comparable across clubs). Composite is per-club only and cannot be compared across clubs.

---

## 10. Key Design Rules

1. **`record_match` is the ONLY write path** for match data. Never bypass it with direct inserts — it handles Elo + attendance atomically.
2. **`delete_match` replays all matches** from scratch. After deletion, all player Elo values and match_participants history are recomputed.
3. **`v_head_to_head` has ONE row per (A,B) ordering.** In Compare.vue, both orderings are queried and merged.
4. **Privacy**: Never query `phone` or `email` from `user_profiles` in PlayerProfile.vue or any public-facing view. Only `nickname`, `bio`, `emirate`, `avatar_url`.
5. **Guest players**: `players.user_id` is nullable. Guest players can play and accumulate Elo without ever logging in. They claim their account via invite link.
6. **Views are not materialised.** Fine for ≤500 players per club. For 1000+, consider `MATERIALIZED VIEW` + periodic refresh.
7. **`is_manager()` / `is_member()`** use `auth.uid()` — only works in RLS context (client queries). Returns false in SQL Editor.
8. **Inactive players** are excluded from `v_leaderboard`, `v_top_scorers`, and the Add Match player picker. Their Elo is frozen.
9. **Club ranking** is recalculated live from matches + attendance. `v_club_rankings` is not materialised.
10. **Facility bookings auto-create** when a match is recorded for a club with `facility_id` set — matches the `facility_schedule` slot for that day of week.

---

## 11. Feature Status

### ✅ Implemented
- Google OAuth login + persistent session (never logs out until user action)
- Club creation, join requests, invite by email/WhatsApp, onboarding form
- Player roster with active/inactive toggle, online status dots, profile links
- Match recording (Elo + attendance in one transaction)
- Match history with expand/rename/delete + full Elo recalculation on delete
- Match name input while adding (optional, auto-generated if blank)
- Club leaderboard with podium, best pair, composite ranking
- Head-to-head comparison + best pairs stats
- Player profile (public — no phone/email)
- Club profile page (/club/:id)
- Facility master (/facility/:id) with weekly schedule + auto-bookings
- Explore page (Clubs | Facilities | Players tabs, all public)
- Own clubs shown first in Explore
- Top scorers across all clubs (global Elo-based, min 1 game)
- Manager role promotion in-app (Manage → Members dropdown)
- Cannot remove player with match history (deactivate instead)
- Session tracking + activity log (backend, admin UI coming later)
- SEO: meta tags, OG, Twitter Card, JSON-LD, robots.txt, sitemap.xml
- PWA install: Android prompt + iOS instructions

### ❌ Not Yet Implemented
- **Photo upload** for players/clubs/facilities — requires Supabase Storage bucket (`avatars`) to be created; currently `image_url` is a paste-any-URL field
- **Admin role / Admin dashboard** — tables exist (`app_sessions`, `activity_log`); UI and role pending
- **Facility admin** — currently facility creator is the owner; formal facility_admin role pending
- **Online court booking** — facility schedule shows slots but cannot book/reserve online yet
- **Push notifications** — Supabase Realtime not wired up yet
- **Season reset** — snapshot Elo, reset to 1000 for new season
- **Form guide** — last 5 match results per player (W/L dots)
- **Most improved** — Elo delta over last 30 days
- **Export to PDF** — monthly leaderboard report
- **Payment / Splitwise integration** — cost sharing for court bookings

---

## 12. Deployment

### Local dev
```bash
cp .env.example .env   # fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm install
npm run dev            # http://localhost:5173
```

### Push to deploy
```bash
git push origin main   # Vercel auto-deploys in ~30 seconds
```

### Supabase setup (one-time)
1. Create project (region: Singapore — best latency for UAE)
2. SQL Editor → run all migration files in order (see section 5)
3. Auth → Providers → Google → enable → paste Client ID + Secret
4. Auth → URL Configuration → add `https://badmint.vercel.app/**` + localhost
5. Google Cloud Console → OAuth Client → add Vercel URL as authorised origin

### Environment variables (Vercel dashboard)
```
VITE_SUPABASE_URL       = https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY  = your-anon-key
```

---

## 13. Useful Debug Queries

```sql
-- Current leaderboard for a club
SELECT * FROM v_leaderboard WHERE club_id = 'CLUB-ID' ORDER BY club_rank;

-- Club ranking (all clubs)
SELECT * FROM v_club_rankings ORDER BY club_rank;

-- Top scorers globally
SELECT * FROM v_top_scorers ORDER BY global_rank LIMIT 20;

-- Player Elo history
SELECT mp.elo_before, mp.elo_after, m.played_on, m.match_number
FROM match_participants mp
JOIN match_sides ms ON ms.id = mp.match_side_id
JOIN matches m ON m.id = ms.match_id
WHERE mp.player_id = 'PLAYER-ID'
ORDER BY m.played_on DESC;

-- Sessions for a user
SELECT * FROM app_sessions WHERE user_id = 'USER-ID' ORDER BY logged_in_at DESC;

-- Activity log for a session
SELECT event_type, event_data, created_at FROM activity_log
WHERE session_id = 'SESSION-ID' ORDER BY created_at;

-- Facility bookings upcoming
SELECT fb.booked_date, fb.start_time, c.name as club_name
FROM facility_bookings fb
JOIN clubs c ON c.id = fb.club_id
WHERE fb.facility_id = 'FAC-ID' AND fb.booked_date >= current_date
ORDER BY fb.booked_date;

-- Check a club's facility link
SELECT c.name, f.name as facility, c.facility_id FROM clubs c
LEFT JOIN facilities f ON f.id = c.facility_id;

-- Reset all players in a club to 1000 (dev/testing only)
UPDATE players SET elo = 1000 WHERE club_id = 'CLUB-ID';
```

---

## 14. Branding

- **App name:** Badmint
- **Tagline:** "Smart rankings for UAE badminton teams"
- **Domain:** badmint.vercel.app
- **GitHub:** github.com/sajeevsahadev/badmint
- **Owner email:** sajeevsahadev@gmail.com
- **Target market:** UAE badminton clubs — all 7 emirates
- **Monetisation:** Free (Phase 1). Future: facility booking fees, premium features.
