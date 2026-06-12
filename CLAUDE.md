# CLAUDE.md — Badminton 360 Complete Project Context

> **Single source of truth.** Read this file at the start of every Claude Code session.
> Last updated: June 2026 — reflects all migrations v1–v18 and the Badminton 360 rebrand (commit bfbb092).

---

## 1. Business Context

### What is Badminton 360?
A free, installable **Progressive Web App (PWA)** for badminton club management and doubles ranking — usable by clubs anywhere in the world. Branded **Badminton 360** (short form **B360**). Formerly named "Badmint" with a UAE-only focus; the repo, Supabase project and some internal identifiers still use the old `badmint` name.

**Typical use-case:**
A group of 6–30 friends books a badminton court at a sports academy or school facility every Saturday morning 6–8am, or weekday evenings. When they arrive, a manager opens the app, picks 4 players, assigns them to Side A / Side B, enters the score, and hits Record. The app calculates Elo ratings automatically. Everyone can see the leaderboard on their phone.

**Target users:**
- Players — view rankings, profile, match history
- Managers/Owners — record matches, manage roster, invite players, set up clubs
- Future: Facility admins, App Administrators

**Vision:** Free for every badminton group globally. Multi-club from day one — each court/group is an isolated "club". Clubs can link to real facility profiles so anyone can see who is playing where. The app auto-detects the visitor's country from their internet connection (`useGeo` composable) instead of assuming UAE.

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
| Live URL | `https://badminton360.app` (custom domain via Cloudflare DNS) · `https://badmint.vercel.app` (Vercel default) |

**Design system:**
- Background: `#050d1a` (deep navy)
- Primary/neon: `#00e5ff` (electric cyan)
- Secondary: `#a855f7` (violet)
- Accent: `#fbbf24` (gold/amber)
- Fonts: Bricolage Grotesque (display) + Outfit (body)
- Cards: glassmorphism — `bg-white/[0.03]` + `backdrop-blur-xl`
- Custom CSS classes: `.card`, `.card-neon`, `.card-violet`, `.card-amber`, `.btn-primary`, `.btn-ghost`, `.btn-violet`, `.btn-success`, `.btn-danger`, `.gradient-text`, `.text-neon`, `.text-violet`, `.text-gold`, `.badge-*`, `.shimmer`, `.fade-up`
- (The UAE flag hero and `@keyframes flagWave` were removed in the B360 rebrand — Home hero is now a global cyan/violet/amber gradient theme)

---

## 3. Project File Structure

```
badmint/
├── index.html                      # SEO meta, OG, JSON-LD, PWA icons, fonts
├── vite.config.js                  # Vite + PWA manifest (icons: 192/512 any + maskable)
├── tailwind.config.js
├── package.json                    # scripts: dev, build, preview, generate:icons
├── scripts/
│   └── generate-icons.js           # Regenerate PNGs from icon.svg (uses sharp)
├── public/
│   ├── favicon.svg                 # Brand icon (shuttlecock design)
│   ├── icon.svg                    # Source icon SVG (same as favicon.svg)
│   ├── icon-192.png                # PWA home-screen icon (generated from icon.svg)
│   ├── icon-512.png                # PWA splash / maskable icon (generated)
│   ├── robots.txt
│   └── sitemap.xml
├── supabase/
│   ├── schema.sql                  # v1: core tables + Elo engine
│   ├── join_schema.sql             # v1.5: join_requests, club_invites
│   ├── v2_schema.sql               # v2: user_profiles, club ranking, match numbers, top scorers
│   ├── v3_schema.sql               # v3: full_name, emirate, country on user_profiles
│   ├── v4_schema.sql               # v4: is_active, delete_match, toggle_player_active
│   ├── v5_schema.sql               # v5: app_sessions, activity_log, online status
│   ├── v6_schema.sql               # v6: facilities, facility_schedule, facility_bookings
│   ├── v7_schema.sql               # v7: leave_club() RPC
│   ├── v8_schema.sql               # v8: 10-club limit (request_join update) + revoke_join_request
│   └── v9_schema.sql               # v9: playing schedule, poll, attendees, push_subscriptions
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
    │   ├── useInstall.js           # PWA install prompt (Android + iOS detection + isInstalled)
    │   ├── useGeo.js               # Auto country detection (ipapi.co + locale fallback, localStorage cache)
    │   └── useSession.js           # startSession, trackPage, trackAction, endSession
    ├── components/
    │   ├── InfoTip.vue             # Inline ? tooltip (positioned right-0 top-6 to avoid overflow)
    │   └── PageHeader.vue          # icon + title + subtitle + collapsible #help slot
    └── views/
        ├── Home.vue                # Public landing: global hero, story landing (logged out), Top Clubs/Players (logged in)
        ├── Login.vue               # Google sign-in, feature grid
        ├── Schedule.vue            # Calendar, match-day planning, poll voting, attendee tracking
        ├── PollView.vue            # Public poll page — shareable /poll/:id URL (WhatsApp link target)
        ├── Dashboard.vue           # Leaderboard (clickable rows), podium, Best Pairs top-3, quick links
        ├── AddMatch.vue            # Pick 4 active players, assign sides, enter score + name
        ├── Matches.vue             # Match history (expand/rename/delete with confirmation modal)
        ├── Players.vue             # Roster: add+invite, active/inactive toggle, online status (clickable)
        ├── Compare.vue             # Head-to-head + stat comparison + best pairs
        ├── RankingGuide.vue        # In-app ranking explainer
        ├── Manage.vue              # Club admin: requests, invites, weights, facility, roles, leave club
        ├── Explore.vue             # Public: Clubs tab | Facilities tab (inline create modal) | Players tab
        ├── JoinClub.vue            # Browse clubs + join request + invite token onboarding
        ├── Profile.vue             # Own profile editor + leave club option per stat row
        ├── PlayerProfile.vue       # Public player page (stats, matches — no phone/email)
        ├── ClubProfile.vue         # Public club page (stats, members with profile links)
        └── FacilityProfile.vue     # Public facility page (schedule, bookings, clubs)
```

---

## 4. Routes

| Path | View | Auth | Notes |
|---|---|---|---|
| `/` | Home.vue | **Public** | Landing page — top clubs, players, search, PWA install |
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
8. `supabase/v7_schema.sql` — leave_club RPC
9. `supabase/v8_schema.sql` — 10-club limit + revoke_join_request RPC
10. `supabase/v9_schema.sql` — Playing schedule, poll, attendees, push_subscriptions
11. `supabase/v10_schema.sql` — Nickname-first display names in all views
12. `supabase/v11_schema.sql` — PaySplits: expense tracking & equal cost splitting
13. `supabase/v12_schema.sql` — Wallet: shared expense pool with FIFO contribution queue
14. `supabase/v13_schema.sql` — Open match recording to all members; delete = creator or owner
15. `supabase/v14_schema.sql` — Tournament module (tournaments, registrations, bracket matches)
16. `supabase/v15_schema.sql` — App-level roles (app_admin), admin panel, tournament quota guard
17. `supabase/v16_schema.sql` — delete_club RPC + fix get_tournaments ambiguous `status` column
18. `supabase/v17_schema.sql` — delete_tournament RPC
19. `supabase/v18_schema.sql` — fix register_for_tournament: registered_by/notes swapped in VALUES

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
club_id (PK, → clubs), elo_weight (0.7), participation_weight (0.3), k_factor (24, fixed), starting_elo (1000)
```
- **k_factor is locked at 24** — the Manage UI shows it as read-only and `saveCfg` always writes `k_factor: 24`
- Reason: cross-club Elo comparability — different K-factors would make global rankings unfair

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
- **Important**: When a user leaves a club via `leave_club()`, their `join_requests` row is also deleted so Explore shows "Join" again instead of "Approved"

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
- **Privacy rule**: `phone` and `email` are NEVER shown to other users. Only `nickname`, `bio`, `emirate` are public.
- **Critical**: `upsert_profile` has TWO PostgreSQL overloads (v2 3-param, v3 6-param). Always pass all 6 named params to avoid ambiguity:
  ```js
  supabase.rpc('upsert_profile', {
    p_nickname, p_full_name: null, p_phone, p_bio, p_emirate: null, p_country: null
  })
  ```

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
- **Note**: global ranking uses raw Elo; K-factor is locked at 24 for all clubs so comparisons are fair

---

### Active/Inactive + Delete Match (v4)

**`players.is_active`** (boolean, default true)
- `toggle_player_active(p_player_id)` — managers only; returns new boolean status
- Inactive players excluded from: `v_leaderboard`, `v_top_scorers`, Add Match player picker
- Inactive players still appear in Matches history and their past Elo is preserved
- **Use deactivation instead of removal** for players who have match history

**`delete_match(p_match_id)`** — managers only
1. Deletes the match (cascades to match_sides, match_participants)
2. Resets ALL club players to `starting_elo` (from ranking_config)
3. Deletes all attendance for the club
4. Replays every remaining match in chronological order, recalculating Elo
5. Updates `elo_before`/`elo_after` in match_participants for history accuracy
6. Rebuilds attendance from scratch
- **UI**: Tapping "Delete match" opens a styled confirmation modal (not native confirm()); requires explicit "Yes, Delete" button press

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
- Used for future Admin dashboard — tracks all navigation and actions per session

**RPCs:** `create_session`, `log_activity`, `end_session`

**Online status** (via `user_profiles.last_seen_at`):
- 🟢 Green pulse dot: `last_seen_at >= now() - interval '10 minutes'`
- 🟠 Orange dot: `last_seen_at >= now() - interval '1 month'`
- ⊗ Grey X: `last_seen_at < now() - interval '1 month'` or null
- Only shown for players with a linked `user_id` (not guest players)

---

### Facility Master (v6)

**`facilities`**, **`facility_schedule`**, **`facility_bookings`** — see original schema for column details.

Key behaviours:
- **Auto-booking**: trigger `trg_auto_facility_booking` creates a `facility_bookings` row whenever a match is recorded for a club with `facility_id` set
- **Facility creation** from Explore page: inline bottom-sheet modal (does NOT navigate to /manage)
- `image_url` is a paste-any-URL field; Supabase Storage not yet set up

---

### Leave Club (v7 — `supabase/v7_schema.sql`)

**`leave_club(p_club_id uuid)`** — own authenticated user
- **Blocks** if caller is the club owner ("Transfer ownership first")
- **Blocks** if caller has any match history in the club ("Ask manager to mark as Inactive")
- On success: deletes from `players`, `club_members`, and `join_requests` (so Explore shows "Join" again)
- UI available in: **Manage → Your Clubs** (Leave button per row) and **Profile → My Club Rankings** (Leave button per row)

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
| `leave_club(p_club_id)` | Own user | Leave a club (blocks owner/match-history; cleans join_requests) |
| `revoke_join_request(p_club_id)` | Own user | Cancel a pending join request (so Explore shows Join again) |
| `create_session(p_user_agent)` | Any auth | Creates session record; returns session UUID |
| `log_activity(p_session_id, p_event_type, p_event_data)` | Any auth | Logs a page view or action |
| `end_session(p_session_id)` | Any auth | Marks logout timestamp |
| `request_join(p_club_id)` | Any auth | Player requests to join a club |
| `approve_join(p_request_id)` | Manager | Approves request; adds to club_members + players |
| `reject_join(p_request_id)` | Manager | Rejects join request |
| `invite_member(p_club_id, p_email)` | Manager | Creates invite token; returns token string |
| `accept_invite(p_token)` | Any auth | Accepts invite; adds to club + creates player row |
| `upsert_profile(p_nickname, p_full_name, p_phone, p_bio, p_emirate, p_country)` | Own user | Creates/updates user_profiles — **always pass all 6 params** |
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
**Important**: After fetching, `clubs` is deduplicated by `club_id` (Set-based filter). This guards against an RLS edge case where the `cm_read` policy (allows reading all member rows for your clubs) could return multiple rows per club when the manager has approved new members.

### `useInstall.js`
```js
const { canInstall, isIOS, isInstalled, promptInstall } = useInstall()
// canInstall → true on Android Chrome when beforeinstallprompt has fired
// isIOS → true on iPhone/iPad
// isInstalled → true when running in standalone mode (already added to home screen)
// promptInstall() → triggers the native Chrome install dialog
```
- `isInstalled` uses `window.navigator.standalone` (iOS) + `matchMedia('display-mode: standalone')` (Android)
- `appinstalled` event auto-flips `isInstalled = true` and hides install prompts

### `useSession.js`
```js
const { sessionId, startSession, trackPage, trackAction, endSession } = useSession()
```

---

## 8. App Shell (App.vue)

- **Loading splash** shown while `ready === false`
- **Top bar** (authenticated routes only): Badmint logo (RouterLink → `/`) | club switcher | iOS install trigger | profile avatar (→ /profile) | Sign out
- **PWA install banners**: Android `beforeinstallprompt` banner + iOS share instructions (authenticated shell only)
- **No-club welcome screen**: shown when `!currentClub && route not in clubFreeRoutes`; offers Browse/Join/Create
- **Bottom nav (5 tabs): Home 🏠 | Rankings 🏆 | Matches 📋 | Players 👥 | Manage ⚙️**
  - **Shown for ALL logged-in users on EVERY page** (including public routes: `/`, `/explore`, `/facility/:id`)
  - Uses `exact-active-class` (not `active-class`) so the Home tab only highlights on exactly `/`
  - Manage tab shows a red badge dot when there are pending join requests
  - Public routes get `pb-28` wrapper when user is logged in (clears fixed nav)
- Session started on user login; page tracked on every route change; session ended on logout

---

## 9. Ranking System

### Elo (skill)
- Starting Elo: 1000 (from `ranking_config.starting_elo`)
- Doubles: average the two players' Elo per side before calculating expected score
- Formula: `new_elo = old_elo + K × (actual − expected)`
  - `expected = 1 / (1 + 10^((opp_avg − own_avg) / 400))`
  - `actual` = 1 (win) / 0 (loss)
- **K = 24 — fixed for all clubs, not editable** (locked in UI + enforced in saveCfg)
- Reason: consistent K across all clubs ensures raw Elo is comparable in the global leaderboard

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
Ranked by raw Elo. Composite is per-club only and cannot be compared across clubs.
K=24 lock ensures Elo accumulates at the same rate across all clubs, making global ranking fair.

### Best Pairs (Dashboard)
- Sourced from `v_best_pairs` — top **3** pairs (changed from top 1) ordered by `win_pct desc, games desc`
- Displayed with 🥇🥈🥉 medals, names, W/L record, win%
- InfoTip explains: "Ranked by win % across all doubles matches played together (min 1 game)"

---

## 10. Key Design Rules

1. **`record_match` is the ONLY write path** for match data. Never bypass it with direct inserts.
2. **`delete_match` replays all matches** from scratch. Delete shows a styled modal, not native confirm().
3. **`v_head_to_head` has ONE row per (A,B) ordering.** In Compare.vue, both orderings are queried and merged.
4. **Privacy**: Never query `phone` or `email` in PlayerProfile.vue or public-facing views. Only `nickname`, `bio`, `emirate`, `avatar_url`.
5. **Guest players**: `players.user_id` is nullable. They accumulate Elo without logging in; claim account via invite link.
6. **Views are not materialised.** Fine for ≤500 players per club.
7. **`is_manager()` / `is_member()`** use `auth.uid()` — only works in RLS context. Returns false in SQL Editor.
8. **Inactive players** are excluded from `v_leaderboard`, `v_top_scorers`, and Add Match picker. Their Elo is frozen.
9. **K-factor is FIXED at 24.** The UI shows it as read-only. `saveCfg` always writes `k_factor: 24`. Never allow user-configurable K again without reconsidering the global ranking fairness.
10. **`upsert_profile` overload**: Two PG function signatures exist. Always call with all 6 named params to avoid `"could not choose best candidate function"` error.
11. **Explore `requestMap`**: Only includes `pending` status from join_requests (not `approved`). A user who was `approved` but has since left shows the Join button — the `approved` status is intentionally excluded to handle post-leave state.
12. **`useClub.loadClubs()` deduplicates** by `club_id` — guards against RLS edge case with multiple rows.
13. **Player names are RouterLinks** across all views (Dashboard, Matches, Explore, Players, ClubProfile) → `/player/:id`. Always use the player's `id` (from `players` table), not `user_id`.
14. **Facility bookings auto-create** when a match is recorded for a club with `facility_id` set.
15. **Leave Club blocks**: owners must transfer ownership first; players with match history must be deactivated instead. The `leave_club` RPC enforces both and also deletes the `join_requests` row.

---

## 11. Views — Key Behaviours

### Home.vue (public, `/`)
- Global hero: cyan/violet/amber gradient + glow orbs + dot grid; shows auto-detected country with flag emoji ("🇦🇪 United Arab Emirates · Elo Rankings · Free Forever", falls back to "🌍 Worldwide") via `useGeo`
- Search bar: real-time search across clubs and facilities
- **Logged-out landing**: sign-in CTA card + 5-chapter story timeline (club management → match tracking/Elo → PaySplits/Wallet → discover tournaments → host tournaments); every story card is a button → `/login`; finale CTA card ("The whole game. The whole club. One app. 360°.")
- **Top Clubs and Top Players are hidden for logged-out visitors** — shown only when logged in
- My Teams section: shown for logged-in users; click switches club + navigates to club profile
- PWA Install section — kept at the **bottom** of the page (native iOS/Android apps planned); hidden once `isInstalled = true`:
  - Android card: calls `promptInstall()` when `canInstall` is true; otherwise opens Android guide bottom-sheet modal
  - iPhone/iPad card: always opens iOS guide bottom-sheet modal
- No emirate filter chips (removed in globalization)

### Dashboard.vue
- Leaderboard rows: clicking navigates to `/player/:id` (RouterLink on player name column)
- Podium names: RouterLink to `/player/:id`
- Best Pairs: top 3 (not just 1), with 🥇🥈🥉 medals
- Days column: has explicit `pr-4` right-padding for mobile readability
- InfoTip tooltip: positioned `right-0 top-6` to prevent right-edge overflow

### Matches.vue
- Delete match: styled Teleport modal (not native confirm) with amber warning about Elo recalculation
- Player names in expanded match detail: RouterLinks when player ID is available

### Manage.vue
- Members section: displays names (priority: `user_profiles.nickname` > `full_name` > `players.display_name` > `—`)
- K-factor: read-only display showing "24", not editable
- Ranking weights save: always writes `k_factor: 24`
- Your Clubs section: Leave button per club (hidden for owners); shows match-history error or success

### Explore.vue
- Facilities tab "Add Your Facility": opens inline bottom-sheet modal (does NOT navigate to /manage)
- Players tab rows: RouterLinks to `/player/:id`
- `requestMap`: only includes `pending` status from join_requests — `approved` is excluded to handle post-leave state

### Profile.vue
- `upsert_profile` call: passes all 6 named params (p_nickname, p_full_name:null, p_phone, p_bio, p_emirate:null, p_country:null)
- My Club Rankings: Leave button per row (hidden if owner or games > 0)

---

## 12. PWA Icons

| File | Size | Purpose |
|---|---|---|
| `public/icon.svg` | Source | Shuttlecock brand icon (dark navy bg, cyan shuttle, "BADMINT" text) |
| `public/favicon.svg` | Browser tab | Same as icon.svg |
| `public/icon-192.png` | 19 KB | Android home screen, PWA install icon |
| `public/icon-512.png` | 60 KB | Splash screen, maskable icon |

**To regenerate icons** (after editing `icon.svg`):
```bash
npm run generate:icons
```
Uses `sharp` (devDependency) to convert SVG → PNG at both sizes.

**Manifest entries** (`vite.config.js`):
```js
{ src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
{ src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
{ src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
```

---

## 13. Feature Status

### ✅ Implemented
- Google OAuth login + persistent session (never logs out until user action)
- Club creation, join requests, invite by email/WhatsApp, onboarding form
- **Leave Club** — from Manage → Your Clubs and Profile → My Club Rankings (blocks if owner or has matches)
- Player roster with active/inactive toggle, online status dots, profile links
- Match recording (Elo + attendance in one transaction)
- Match history with expand/rename/**styled delete confirmation** + full Elo recalculation on delete
- Match name input while adding (optional, auto-generated if blank)
- Club leaderboard with podium (clickable), **Best Pairs top-3**, composite ranking, **clickable rows**
- Head-to-head comparison + best pairs stats
- Player profile (public — no phone/email); **all player names across app are RouterLinks**
- Club profile page (`/club/:id`)
- Facility master (`/facility/:id`) with weekly schedule + auto-bookings
- Explore page (Clubs | **Facilities with inline add modal** | Players with profile links, all public)
- Own clubs shown first in Explore; Join/Pending/My Club status correctly updates after leave
- Top scorers across all clubs (global Elo-based, min 1 game)
- Manager role promotion in-app (Manage → Members, shows names not UUIDs)
- Cannot remove player with match history (deactivate instead)
- Session tracking + activity log (backend, admin UI coming later)
- SEO: meta tags, OG, Twitter Card, JSON-LD, robots.txt, sitemap.xml
- **PWA**: real shuttlecock brand icon (192 + 512 PNG), Android one-tap install, iOS guide bottom-sheet
- **Home page** (`/`) public landing — story landing for logged-out visitors, top clubs/players + search for logged-in users, install section at bottom
- **Bottom nav on all pages** for logged-in users (Schedule | Rankings | Matches | Players | Manage)
- **Playing Schedule** — Calendar view, plan match days, pick/create venue, team poll (Attending/Not Attending), actual attendee tracking, shareable poll URL, WhatsApp share
- **Add Match** — Schedule-aware player filter: if schedule has saved attendees for the date, only those players appear (with override toggle)
- K-factor locked at 24 for all clubs (cross-club Elo comparability)
- **Nickname-first display names** (v10) — all views use `COALESCE(nickname, display_name)`; guest players still show roster name
- **PaySplits** (v11) — expense tracking & equal cost splitting per session
- **Wallet** (v12) — shared expense pool with FIFO contribution queue; players pre-contribute
- **Open match recording** (v13) — any club member can record matches (not just managers); delete allowed for creator or owner
- **Tournament module** (v14) — `tournaments`, `tournament_registrations`, `tournament_matches` tables; single_elimination + round_robin formats; `TournamentView.vue` with bracket UI; register team, approve/reject, generate bracket, record match results
- **App-level roles** (v15) — `app_roles` table, `is_app_admin()` helper, tournament creation quota, admin panel route `/admin`
- **delete_club RPC** (v16) — owner or app_admin can delete a club (CASCADE); also fixed ambiguous `status` column bug in `get_tournaments`
- **delete_tournament RPC** (v17) — tournament creator, club owner/manager, or app_admin can delete
- **Badminton 360 rebrand + globalization** (commit bfbb092) — all branding renamed to Badminton 360 / B360; UAE flag hero, emirate chips and UAE-specific copy removed; `useGeo` auto country detection; JoinClub emirate dropdown → free-text City/Region; canonical domain badminton360.app

### ❌ Not Yet Implemented
- **Photo upload** — requires Supabase Storage bucket; currently `image_url` is paste-any-URL
- **Admin dashboard UI** — `app_roles` table exists; admin panel route exists but UI is basic
- **Facility admin role** — creator is currently the de-facto owner; formal role pending
- **Online court booking** — schedule visible but can't reserve online
- **Push notifications** — Web Push infrastructure wired up (DB tables + SW handler + composable); requires VAPID key setup and a Supabase Edge Function to send
- **Season reset** — snapshot Elo, reset to 1000 for new season
- **Form guide** — last 5 match results per player (W/L dots)
- **Most improved** — Elo delta over last 30 days
- **Export to PDF** — monthly leaderboard report
- **Full globalization of deeper forms** — Tournaments, ManageTournament, Manage (facility), BookCourt and Explore still have hardcoded UAE emirate dropdowns/filters; the DB `emirate`/`emirates` columns now hold free-text region strings

---

## 14. Deployment

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
2. SQL Editor → run all migration files in order (see section 5, v1–v7)
3. Auth → Providers → Google → enable → paste Client ID + Secret
4. Auth → URL Configuration → add `https://badmint.vercel.app/**` + localhost
5. Google Cloud Console → OAuth Client → add Vercel URL as authorised origin

### Environment variables (Vercel dashboard)
```
VITE_SUPABASE_URL       = https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY  = your-anon-key
```

---

## 15. Useful Debug Queries

```sql
-- Current leaderboard for a club
SELECT * FROM v_leaderboard WHERE club_id = 'CLUB-ID' ORDER BY club_rank;

-- Club ranking (all clubs)
SELECT * FROM v_club_rankings ORDER BY club_rank;

-- Top scorers globally
SELECT * FROM v_top_scorers ORDER BY global_rank LIMIT 20;

-- Best pairs for a club (top 3)
SELECT * FROM v_best_pairs WHERE club_id = 'CLUB-ID'
ORDER BY win_pct DESC, games DESC LIMIT 3;

-- Player Elo history
SELECT mp.elo_before, mp.elo_after, m.played_on, m.match_number
FROM match_participants mp
JOIN match_sides ms ON ms.id = mp.match_side_id
JOIN matches m ON m.id = ms.match_id
WHERE mp.player_id = 'PLAYER-ID'
ORDER BY m.played_on DESC;

-- Members with names for a club (as the app does it)
SELECT cm.user_id, cm.role,
  up.nickname, up.full_name,
  p.display_name
FROM club_members cm
LEFT JOIN user_profiles up ON up.user_id = cm.user_id
LEFT JOIN players p ON p.club_id = cm.club_id AND p.user_id = cm.user_id
WHERE cm.club_id = 'CLUB-ID';

-- Check if a user has match history in a club
SELECT COUNT(*) FROM match_participants mp
JOIN players p ON p.id = mp.player_id
WHERE p.club_id = 'CLUB-ID' AND p.user_id = 'USER-ID';

-- Sessions for a user
SELECT * FROM app_sessions WHERE user_id = 'USER-ID' ORDER BY logged_in_at DESC;

-- Facility bookings upcoming
SELECT fb.booked_date, fb.start_time, c.name as club_name
FROM facility_bookings fb
JOIN clubs c ON c.id = fb.club_id
WHERE fb.facility_id = 'FAC-ID' AND fb.booked_date >= current_date
ORDER BY fb.booked_date;

-- Check a club's facility link
SELECT c.name, f.name as facility, c.facility_id FROM clubs c
LEFT JOIN facilities f ON f.id = c.facility_id;

-- Check ranking config for all clubs
SELECT c.name, rc.elo_weight, rc.participation_weight, rc.k_factor, rc.starting_elo
FROM ranking_config rc JOIN clubs c ON c.id = rc.club_id;

-- Reset all players in a club to 1000 (dev/testing only)
UPDATE players SET elo = 1000 WHERE club_id = 'CLUB-ID';
```

---

## 16. Branding

- **App name:** Badminton 360 (short form: B360 — used as PWA short_name and icon monogram)
- **Tagline:** "Your Club · Your Game · One App"
- **Domain:** badminton360.app (Cloudflare DNS → Vercel; badmint.vercel.app still works)
- **GitHub:** github.com/sajeevsahadev/badmint
- **Owner email:** sajeevsahadev@gmail.com
- **Target market:** Badminton clubs worldwide (launched in the UAE)
- **Monetisation:** Free (Phase 1). Future: facility booking fees, premium features.
- **Icon**: Shuttlecock silhouette in neon cyan on dark navy rounded square with "B360" monogram. Source: `public/icon.svg`. Regenerate PNGs with `npm run generate:icons`.
