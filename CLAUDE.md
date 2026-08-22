# CLAUDE.md — Badminton 360 Complete Project Context

> **Single source of truth.** Read this file at the start of every Claude Code session.
> Last updated: June 2026 — reflects all migrations v1–v37, including:
> - v34: admin RPCs for player profile bypass (admin_get_player, admin_get_player_matches)
> - v35: push_subscriptions.club_id made nullable (global push, not per-club)
> - v36/v36b: multi-payer PaySplits (paysplit_expense_payers table) + FIFO SQL RPC (get_fifo_result)
> - v37: pg_cron weekly digest schedule
> - New app icon (neon shuttlecock PNG), login→dashboard redirect, zoom disabled
> - Email sending live: match-recorded, expense-added, weekly-digest (auto Monday 8am UTC), announcements (admin-triggered)
> - Admin Panel expanded to 7 tabs (added Announcements)

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
| Styling | Tailwind CSS v3 + custom CSS (light theme — see Design system below) |
| PWA | vite-plugin-pwa — installable, offline-capable |
| Auth | Supabase Auth — Google OAuth only |
| Database | Supabase (PostgreSQL) |
| Hosting | Vercel (free tier, auto-deploy from GitHub) |
| Repo | `https://github.com/sajeevsahadev/badmint` |
| Live URL | `https://badminton360.app` (custom domain via Cloudflare DNS) · `https://badmint.vercel.app` (Vercel default) |

**Design system (actual, as shipped in `src/style.css` — light theme):**
- Background: `#eef4ff` (soft blue-white) with three radial-gradient glow accents (cyan/violet/amber) in the corners
- Cards: solid white (`#ffffff`) with soft shadows — `.card`, `.card-neon`/`.card-violet`/`.card-amber` add a colour-tinted glow border, not glassmorphism
- Primary/neon: `#00b4d8` / darkened to `#0099b8` for text (`.text-neon`) so it reads on white
- Secondary/violet: `#a855f7` / darkened to `#8b5cf6` for text (`.text-violet`)
- Accent/gold: `#fbbf24` / darkened to `#d97706` for text (`.text-gold`)
- Fonts: Bricolage Grotesque (display) + Outfit (body)
- Tailwind's near-white `slate-100/200/300` text utilities are remapped to dark equivalents at the bottom of `style.css` ("Light-theme text remapping") so templates written for the old dark theme still read correctly — **note**: this remap does NOT cover `border-white/[opacity]` utilities, so a few older borders (e.g. card section dividers) are faint-to-invisible on the white background. Known cosmetic gap, not yet swept across the codebase.
- Custom CSS classes: `.card`, `.card-neon`, `.card-violet`, `.card-amber`, `.btn-primary`, `.btn-ghost`, `.btn-violet`, `.btn-success`, `.btn-danger`, `.gradient-text`, `.text-neon`, `.text-violet`, `.text-gold`, `.badge-*`, `.shimmer`, `.fade-up`
- (The UAE flag hero and `@keyframes flagWave` were removed in the B360 rebrand — Home hero is now a global cyan/violet/amber gradient theme)
- **Appearance preference exists (Profile → Appearance) but only Light is real.** `tailwind.config.js` has `darkMode: 'class'` wired and `useTheme.js` toggles a `dark` class on `<html>`, but no dark palette has been written yet — selecting Dark just saves the preference for when it ships (see Not Yet Implemented).

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
    │   ├── useSession.js           # startSession, trackPage, trackAction, endSession
    │   ├── usePushNotifications.js # subscribe(clubId), isSubscribed, getPermission — needs VAPID key
    │   ├── useTheme.js             # [v32] light/dark/system preference, localStorage + theme_pref sync
    │   └── useBiometricLock.js     # [v32] WebAuthn app-lock: register/verify/disable/forgetThisDevice/timeout
    ├── components/
    │   ├── InfoTip.vue             # Inline ? tooltip (positioned right-0 top-6 to avoid overflow)
    │   ├── PageHeader.vue          # icon + title + subtitle + collapsible #help slot
    │   └── ToggleSwitch.vue        # [v32] reusable on/off switch (v-model="modelValue", :disabled)
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
        ├── Profile.vue             # Own profile editor (incl. gender), Settings list, Sign Out, Danger Zone, footer
        ├── PlayerProfile.vue       # Public player page (stats, matches — no phone/email)
        ├── ClubProfile.vue         # Public club page (stats, members with profile links)
        ├── FacilityProfile.vue     # Public facility page (schedule, bookings, clubs)
        ├── PrivacyPolicy.vue       # [v32] Public privacy policy (/privacy) — linked from Profile footer
        └── settings/               # [v32] Sub-pages reached from Profile → Settings list
            ├── EmailSettings.vue       # email_prefs toggles (invites/match/digest/payment/news)
            ├── PushSettings.vue        # push_prefs toggles + subscribe via usePushNotifications
            ├── SecuritySettings.vue    # Biometric app-lock toggle, timeout, Trusted Devices list
            └── AppearanceSettings.vue  # Light/Dark/System picker (Dark shows "Soon" badge)
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
| `/profile` | Profile.vue | Required | Edit own profile, Settings list, Sign Out, Delete Account |
| `/player/:id` | PlayerProfile.vue | Required | Public player view |
| `/club/:id` | ClubProfile.vue | Required | Public club view |
| `/settings/email` | EmailSettings.vue | Required | [v32] Email notification preferences |
| `/settings/notifications` | PushSettings.vue | Required | [v32] Push notification preferences + subscribe |
| `/settings/security` | SecuritySettings.vue | Required | [v32] Biometric app-lock + Trusted Devices |
| `/settings/appearance` | AppearanceSettings.vue | Required | [v32] Theme preference (Light live, Dark/System deferred) |
| `/privacy` | PrivacyPolicy.vue | **Public** | [v32] GDPR-aligned privacy policy |

All four `/settings/*` routes (plus `/profile`) are listed in App.vue's `clubFreeRoutes` — they must stay reachable for users with zero clubs, or the "join/create a club" welcome screen blocks them instead of rendering the page.

**Auth guard logic** (`router/index.js`):
- Uses `sessionStorage` key `bm_after_login` ONLY for `/join` and `/player/:id` deep-links
- Redirect is consumed only when landing on `/` (post-OAuth) — NOT on every navigation
- Supabase client has `persistSession: true` — users stay logged in until explicit sign-out
- Biometric app-lock (see §10) is a separate, client-side-only gate layered on top of this — it never substitutes for the Supabase session check above

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
20. `supabase/v19_schema.sql` — PaySplits opening balances (paysplit_opening_balances table + set/delete/get RPCs)
21. `supabase/v20_schema.sql` — Open poll voting (any auth user, no club membership required) + public get_schedule_votes (grant to anon) + get_club_leaderboard security-definer RPC (bypasses v_leaderboard RLS for public club profiles)
22. `supabase/v21_schema.sql` — get_schedule_votes: add auth.users join so Google display name shows for voters who haven't set up their profile
23. `supabase/v22_schema.sql` — Super admin panel: admin_get_clubs, admin_rename_club, admin_get_facilities, admin_update_facility, admin_delete_facility, admin_get_tournaments; self-grant INSERT for sajeevsahadev@gmail.com; AdminPanel.vue expanded to 6 tabs (Stats/Users/Clubs/Facilities/Tournaments/Roles)
24. `supabase/v23_schema.sql` — Wallet contributions: restrict INSERT to managers/owners only
25. `supabase/v24_schema.sql` — `delete_join_request()` RPC so managers can remove rejected join requests
26. `supabase/v25_schema.sql` — DB-level trigger guard: a club must always retain at least one owner
27. `supabase/v26_schema.sql` — Guest player account linking via invite (`invite_guest_player()`, `club_invites.guest_player_id`)
28. `supabase/v27_schema.sql` — Performance indexes (club_members.user_id, match_sides.match_id, etc.) for scale
29. `supabase/v28_schema.sql` — Admin panel fixes: `get_all_users` session stats, `admin_get_clubs`/`admin_get_facilities` dedup, `admin_create_facility`
30. `supabase/v29_schema.sql` — `admin_delete_club()` — app_admin can force-delete any club via CASCADE, bypassing the match-count guard
31. `supabase/v30_schema.sql` — `facilities.courts_count` column; dropped the UAE-only `emirate` CHECK constraint (globalization)
32. `supabase/v31_schema.sql` — GDPR account deletion: `created_by`/`registered_by` FKs made nullable; `check_can_delete_account()` + `delete_account_data()` RPCs (blocks on club ownership, match history, wallet/PaySplit balance); paired with the `delete-account` Edge Function
33. `supabase/v32_schema.sql` — Profile settings expansion: `user_profiles` gains `gender`, `theme_pref`, `email_prefs` jsonb, `push_prefs` jsonb; **consolidates `upsert_profile` into a single 7-param function** (drops the old v2 3-param + v3 6-param overloads); adds `update_theme_pref()`, `update_notification_prefs()`; adds `webauthn_credentials` table for the biometric app-lock
34. `supabase/v33_schema.sql` — **Security fix**: tightens `user_profiles` RLS
35. `supabase/v34_schema.sql` — Admin bypass RPCs: `admin_get_player(p_player_id)` + `admin_get_player_matches(p_player_id, p_limit)` — SECURITY DEFINER, verify app_admin role, bypass RLS for full player data; fixes "column reference user_id is ambiguous" by qualifying all joins with table aliases
36. `supabase/v35_schema.sql` — `push_subscriptions.club_id` made nullable; new 3-param `save_push_subscription(p_endpoint, p_p256dh, p_auth)` (global push — no club scope); backward-compat 4-param overload kept
37. `supabase/v36_schema.sql` — Multi-payer PaySplits: new `paysplit_expense_payers(id, expense_id, player_id, amount)` table; updated `add_expense`/`update_expense` with optional `p_payers jsonb`; updated `get_expenses` returns `payers` array; updated `get_balance_summary` uses proportional debt edges for multi-payer; dropped old `expense_payment_source` CHECK + category CHECK constraints
38. `supabase/v36b_schema.sql` — `get_fifo_result(p_club_id uuid)` SECURITY DEFINER RPC: SQL window-function O(C+W) FIFO allocation replacing O(n²) JS computation; index on `paysplit_participants(expense_id)`
39. `supabase/v37_schema.sql` — `cron.schedule('weekly-ranking-digest', '0 8 * * 1', ...)` via pg_net → `send-weekly-digest` Edge Function; requires pg_cron + pg_net extensions enabled; fill in YOUR_PROJECT_REF + YOUR_SERVICE_ROLE_KEY before running from `up_read using (true)` (anyone could SELECT phone/gender/full_name) to owner-only; adds `resolve_public_nickname()`, `get_public_profiles()`, `get_member_profile_names()` RPCs; redefines `v_leaderboard`/`v_best_pairs`/`v_top_scorers` to resolve nicknames via the new SECURITY DEFINER function instead of a raw join to `user_profiles`

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

### User Profiles (v2 + v3 + v32 + v33)

**`user_profiles`**
```
user_id (PK, → auth.users), nickname, phone, bio, avatar_url
+ [v3]  full_name, emirate, country (default 'UAE')
+ [v5]  last_seen_at (timestamptz) — updated on every navigation for online status
+ [v32] gender ('male'|'female'|'non_binary'|'unspecified', nullable)
+ [v32] theme_pref ('light'|'dark'|'system', default 'system')
+ [v32] email_prefs jsonb (default {invites,match_recorded,weekly_digest,payment_reminders,news})
+ [v32] push_prefs  jsonb (default {invites,match_recorded,schedule_polls,payment_reminders})
updated_at
```
- **RLS is owner-only as of v33** (`up_read_own using (user_id = auth.uid())`) — fixes a real gap where the old `up_read using (true)` policy let ANY authenticated client SELECT `phone`/`gender`/`full_name` for ANY user straight through the Supabase REST API, regardless of what the UI chose to display. `up_write` (own row, all operations) is unchanged.
- **Cross-user profile reads now go through SECURITY DEFINER RPCs (v33), never the raw table:**
  - `resolve_public_nickname(p_user_id)` — internal helper; only ever returns `nickname`. Used INSIDE `v_leaderboard`/`v_best_pairs`/`v_top_scorers` instead of a raw `LEFT JOIN user_profiles`, specifically so those views keep resolving other players' nicknames correctly now that RLS is tightened — see Design Rule 19 for why a raw join couldn't be trusted to bypass RLS on its own.
  - `get_public_profiles(p_user_ids uuid[])` — returns `nickname, bio, emirate, avatar_url` for a batch of users. Used by `PlayerProfile.vue` and `playerNames.js` (`withNicknames()`/`buildNameMap()`) for anyone viewing another player's public info.
  - `get_member_profile_names(p_club_id)` — returns `nickname, full_name` for members of a club, scoped to callers who are themselves a member of that club. Used by `Manage.vue`'s member list. `full_name` deliberately is NOT in `get_public_profiles` — it's the Google account name, more sensitive than a self-chosen nickname, so it only flows to fellow club members, not the whole app.
- **Privacy rule (now DB-enforced, not just app-enforced)**: `phone` and `email` are NEVER shown to other users. `gender` and `full_name` are limited to the scopes above (self, or fellow club members for full_name). Only `nickname`, `bio`, `emirate`, `avatar_url` are broadly public.
- **`upsert_profile` is now ONE consolidated 7-param function (v32)** — the old "two overloads, always pass 6 params" landmine from v2/v3 is gone; both prior overloads were dropped. Still pass every param explicitly for clarity (all but `p_nickname` have defaults of `null`):
  ```js
  supabase.rpc('upsert_profile', {
    p_nickname, p_full_name: null, p_phone, p_bio, p_emirate: null, p_country: null, p_gender: null
  })
  ```

**`webauthn_credentials`** (v32 — biometric app-lock)
```
id, user_id (→ auth.users), credential_id (unique text), device_label, created_at, last_used_at
```
- RLS: own-row only (`wc_own_all`). No public key or signature is stored/verified server-side — see §10 for the security model.
- Powers the "Trusted Devices" list in `SecuritySettings.vue`; removing a row here is checked (best-effort, online-only) by `useBiometricLock.verify()` on that device to support remote revocation.

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
| `update_match(p_match_id, p_side_a[], p_side_b[], p_score_a, p_score_b, p_played_on?, p_display_name?)` | Creator or owner/manager | (v93) Edit a recorded match's players/scores/winner/date/name, then full Elo replay (same engine as delete_match). Validates 4 distinct club players + non-equal scores |
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
| `upsert_profile(p_nickname, p_full_name, p_phone, p_bio, p_emirate, p_country, p_gender)` | Own user | Creates/updates user_profiles — single consolidated function as of v32 |
| `update_theme_pref(p_theme)` | Own user | Sets `user_profiles.theme_pref` ('light'\|'dark'\|'system') |
| `update_notification_prefs(p_email_prefs?, p_push_prefs?)` | Own user | Upserts `email_prefs`/`push_prefs` jsonb — pass only the one(s) you're changing, the other is left untouched |
| `get_public_profiles(p_user_ids uuid[])` | Any auth | (v33) `nickname, bio, emirate, avatar_url` for a batch of users — the only sanctioned way to read OTHER users' profile fields |
| `get_member_profile_names(p_club_id)` | Member | (v33) `nickname, full_name` for fellow members of a club you also belong to |
| `resolve_public_nickname(p_user_id)` | Internal | (v33) SECURITY DEFINER helper used inside `v_leaderboard`/`v_best_pairs`/`v_top_scorers` — not meant to be called directly, but harmless if it were (only returns nickname) |
| `toggle_player_active(p_player_id)` | Manager | Toggles is_active; returns new boolean |
| `rename_match(p_match_id, p_name)` | Manager | Updates match display_name |
| `update_club_facility(p_club_id, ...)` | Manager | Updates clubs' direct facility fields |
| `get_club_players(p_club_id)` | Any auth | Returns players + online_status for a club |
| `get_public_clubs()` | Public | All clubs with ranking info (security definer) |
| `get_top_scorers(p_limit?)` | Public | Global Elo leaderboard (security definer) |
| `get_facilities(p_emirate?, p_search?)` | Public | All facilities with stats |
| `get_facility_detail(p_facility_id)` | Public | Full facility JSON (schedule + bookings + clubs) |
| `get_club_leaderboard(p_club_id)` | Public | Club leaderboard via SECURITY DEFINER — bypasses v_leaderboard RLS; used by ClubProfile.vue |
| `set_opening_balance(p_club_id, p_player_id, p_amount, p_notes?)` | Manager | Upsert a player's PaySplits opening balance (±, one per player; |amount|<0.01 deletes) |
| `delete_opening_balance(p_club_id, p_player_id)` | Manager | Remove a player's opening balance |
| `get_opening_balances(p_club_id)` | Member | Opening balances with resolved names |
| `create_facility(...)` | Any auth | Creates a facility master record |
| `update_facility(p_id, ...)` | Creator | Updates facility info |
| `set_club_facility(p_club_id, p_facility_id)` | Manager | Links/unlinks club ↔ facility |
| `add_facility_slot(...)` | Creator | Adds a weekly schedule slot |
| `delete_facility_slot(p_slot_id)` | Creator | Removes a schedule slot |
| `get_all_users(p_search?)` | App Admin | All users with roles + tournament count (SECURITY DEFINER) |
| `get_platform_stats()` | App Admin | Platform-wide stats: total users/clubs/matches/etc |
| `grant_role(p_user_id, p_role, ...)` | App Admin | Grant an app-level role to a user |
| `revoke_role(p_user_id, p_role)` | App Admin | Remove an app-level role from a user |
| `get_my_roles()` | Any auth | Returns current user's app_roles rows |
| `is_app_admin()` | SECURITY DEFINER | Returns true if current user has app_admin role |
| `admin_get_clubs()` | App Admin | All clubs with owner email + activity stats (v22) |
| `admin_rename_club(p_club_id, p_name)` | App Admin | Rename any club bypassing ownership check (v22) |
| `admin_get_facilities()` | App Admin | All facilities with creator email + linked clubs count (v22) |
| `admin_update_facility(p_id, p_name, ...)` | App Admin | Edit any facility details (v22) |
| `admin_delete_facility(p_id)` | App Admin | Delete facility + cascade unlink clubs/schedule/bookings (v22) |
| `admin_get_tournaments()` | App Admin | All tournaments with club + creator email (v22) |
| `delete_join_request(p_request_id)` | Manager | Removes a (typically rejected) join request row (v24) |
| `invite_guest_player(p_club_id, p_player_id, p_email)` | Manager | Sends an invite tied to an existing guest player so they can claim it (v26) |
| `admin_delete_club(p_club_id)` | App Admin | Force-deletes any club via CASCADE, skipping the match-count guard `delete_club` enforces for owners (v29) |
| `check_can_delete_account()` | Own user | GDPR pre-check — returns `{can_delete, reason, details}`; blocks on club ownership, match history, or non-zero wallet/PaySplit balance (v31) |
| `delete_account_data()` | Own user | GDPR deletion — anonymises `created_by`/`registered_by` FKs to NULL, deletes own PaySplit expenses/profile/sessions; called by the `delete-account` Edge Function right before `auth.admin.deleteUser()` (v31) |
| `admin_get_player(p_player_id)` | App Admin | (v34) Full player row + club info bypassing RLS — used by PlayerProfile.vue `?admin=1` path |
| `admin_get_player_matches(p_player_id, p_limit)` | App Admin | (v34) Full match history for any player bypassing RLS |
| `save_push_subscription(p_endpoint, p_p256dh, p_auth)` | Any auth | (v35) Global push subscribe — no club_id; overwrites existing subscription for this device |
| `get_fifo_result(p_club_id)` | Member | (v36b) O(C+W) SQL FIFO wallet allocation — returns `{active:[...], consumed:[...]}` jsonb; replaces O(n²) JS computation |

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

### `useTheme.js` (v32)
```js
const { theme, resolvedTheme, setTheme, syncFromProfile, DARK_THEME_READY } = useTheme()
// theme.value → 'light' | 'dark' | 'system' (persisted to localStorage 'b360_theme' + user_profiles.theme_pref)
// resolvedTheme → 'light' | 'dark', resolving 'system' via matchMedia('prefers-color-scheme: dark')
// DARK_THEME_READY = false — applyTheme() still toggles the 'dark' class on <html> for forward-compat,
// but there is no dark CSS yet, so it's a visual no-op until that work lands (see Not Yet Implemented).
```

### `useBiometricLock.js` (v32)
```js
const { isEnabled, isLocked, hasCredentialOnThisDevice, timeoutMs,
        isPlatformAvailable, armOnBoot, register, disable, forgetThisDevice, setTimeout, verify, unlock } = useBiometricLock()
```
- `register(userId, label)` runs the WebAuthn registration ceremony (`navigator.credentials.create`, platform authenticator only) and stores the credential id in `webauthn_credentials` + localStorage.
- `verify()` runs `navigator.credentials.get()`; a successful resolve is the only proof required (no server-side signature check) — see §10 for why that's an acceptable threat model here. Also does a best-effort online check that the credential wasn't remotely removed from Trusted Devices.
- `armOnBoot()` (called from `App.vue init()`) sets `isLocked = true` on cold start if enabled; a `visibilitychange` listener re-locks after `timeoutMs` of being hidden.
- `disable()` turns the gate off on this device without forgetting the credential (toggling back on doesn't need re-registration); `forgetThisDevice()` removes it everywhere.

---

## 8. App Shell (App.vue)

- **Loading splash** shown while `ready === false`
- **Top bar** (authenticated routes only): Badmint logo (RouterLink → `/`) | club switcher | iOS install trigger | profile avatar (→ /profile)
- **Biometric lock overlay** (v32, highest z-index `z-[400]`): rendered above everything, including the update banner and any open modal, whenever `useBiometricLock().isLocked` is true. "Unlock" runs the WebAuthn ceremony; "Trouble unlocking? Sign out" always falls back to a real sign-out + `/login` — the lock never traps a user who can't pass biometric.
- **PWA install banners**: Android `beforeinstallprompt` banner + iOS share instructions (authenticated shell only)
- **No-club welcome screen**: shown when `!currentClub && route not in clubFreeRoutes`; offers Browse/Join/Create
- **Sign out lives on `/profile` now (v32), not the hamburger menu.** The hamburger's Account section footer links to "Profile & Settings" instead. `App.vue` no longer imports `signOut`/`endSession` directly for this purpose — re-add them there only if some other shell-level flow needs sign-out again (e.g. the lock screen's fallback, which does need its own copy of this logic — see `signOutFromLockScreen()`).
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
10. **`upsert_profile` is one function as of v32** — the old two-overload ambiguity is gone (both prior versions were `DROP FUNCTION`'d). Still name every param explicitly when calling it.
11. **Explore `requestMap`**: Only includes `pending` status from join_requests (not `approved`). A user who was `approved` but has since left shows the Join button — the `approved` status is intentionally excluded to handle post-leave state.
12. **`useClub.loadClubs()` deduplicates** by `club_id` — guards against RLS edge case with multiple rows.
13. **Player names are RouterLinks** across all views (Dashboard, Matches, Explore, Players, ClubProfile) → `/player/:id`. Always use the player's `id` (from `players` table), not `user_id`.
14. **Facility bookings auto-create** when a match is recorded for a club with `facility_id` set.
15. **Leave Club blocks**: owners must transfer ownership first; players with match history must be deactivated instead. The `leave_club` RPC enforces both and also deletes the `join_requests` row.
16. **Biometric app-lock is "app-lock only" — never a login replacement (v32, deliberate security decision).** It can only re-reveal a session that's *already* signed in on that device, gated by `navigator.credentials.get()` succeeding (no server-side signature verification — that's an accepted trade-off given the data behind it is club rankings/expenses among friends, not financial accounts). A real Sign Out (`Profile.vue` or the lock screen's "Sign out" fallback) always requires Google sign-in again; biometric can never substitute for it, even for the same device/user. Don't build a "biometric restores a signed-out session" flow without re-opening this decision explicitly.
17. **Push subscriptions are global as of v35 — no club scope.** `push_subscriptions.club_id` is now nullable; `save_push_subscription` takes no club_id. The send-push Edge Function fans out to all of a user's devices via their club memberships. `PushSettings.vue` no longer requires a current club. The old "single-club-scoped per device" limitation is removed.
18. **Settings sub-pages (`/settings/*`) must stay in `App.vue`'s `clubFreeRoutes`.** Same reasoning as `/profile` — these are account-level, not club-level, and must render for users with zero clubs.
19. **Never read another user's `user_profiles` row via a raw `LEFT JOIN`/`.from('user_profiles')` — always go through `get_public_profiles()`, `get_member_profile_names()`, or `resolve_public_nickname()` (v33).** RLS now restricts `user_profiles` SELECT to the owner's own row. Whether a plain SQL `VIEW` bypasses RLS via its owner's privileges depends on Postgres/Supabase specifics this codebase has clearly been burned by before (see `get_club_leaderboard`'s comment about bypassing "v_leaderboard / players RLS") — don't re-introduce a raw cross-user join into a view and assume it'll keep working; wrap it in a SECURITY DEFINER function call instead, which bypasses RLS unambiguously regardless of view semantics.

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
- `upsert_profile` call: passes all 7 named params, now including `p_gender` (v32)
- Gender field: select with `''` (Prefer not to set, → NULL) / male / female / non_binary / `unspecified` (Rather not to say — a deliberate, distinct choice from leaving it blank)
- **Settings card** (v32): 4 RouterLink rows → `/settings/email`, `/settings/notifications`, `/settings/security`, `/settings/appearance`
- **Sign Out** (v32): moved here from the App.vue hamburger menu — styled as a plain list row, not a danger action
- My Club Rankings: Leave button per row (hidden if owner or games > 0)
- Footer (v32): tagline, `/privacy` link, version number from `package.json` — renders last, below Danger Zone (GDPR delete account, v31)

### settings/EmailSettings.vue, PushSettings.vue (v32/v35)
- Both load/save a jsonb prefs blob (`email_prefs` / `push_prefs`) via `update_notification_prefs()`, with an explicit "Save Changes" button (not auto-save per toggle)
- **What actually sends email today**: club invites (always), match recorded (`send-match-email`), expense added (`send-expense-email`), weekly digest (auto Monday 8am via pg_cron → `send-weekly-digest`), announcements (admin-triggered via `send-announcement`). Payment reminders are still saved-but-not-sent.
- `PushSettings.vue` subscribes via `usePushNotifications().subscribe()` — no club_id since v35 (global scope). Shows a "still being wired up" notice when `VITE_VAPID_PUBLIC_KEY` is unset.

### settings/SecuritySettings.vue (v32)
- Toggle calls `useBiometricLock().register()` (WebAuthn ceremony) or `.disable()`
- Lock Timeout buttons (Immediately/1min/5min/30min) call `.setTimeout(ms)`
- Trusted Devices list reads `webauthn_credentials` directly (RLS-scoped to own rows); "Remove" deletes the row and, if it's this device's credential, also calls `forgetThisDevice()` to clear local state immediately

### settings/AppearanceSettings.vue (v32)
- Light / Dark / System picker; Dark shows a `.badge-pending` "Soon" tag since `DARK_THEME_READY` is `false` — don't remove that badge until a real dark palette ships

### PrivacyPolicy.vue (v32)
- Public route `/privacy`; standalone page (no shell top bar since it's `meta:{public:true}`) with its own `‹ Back` button
- Discloses third-party processors actually in use (Supabase, Google, Resend, ipapi.co) — keep this list honest if new ones are added

---

## 12. PWA Icons

| File | Size | Purpose |
|---|---|---|
| `public/icon.png` | Source | Neon shuttlecock brand icon (dark navy bg, green feathers, cyan arc) — PNG source |
| `public/favicon.png` | 64×64 | Browser tab favicon |
| `public/icon-192.png` | ~38 KB | Android home screen, PWA install icon |
| `public/icon-512.png` | ~277 KB | Splash screen, maskable icon |

**Icon was updated in this session** to a new neon shuttlecock design (PNG source, not SVG). The old `icon.svg` / `favicon.svg` files remain in the repo but are no longer used. `index.html` now points to `favicon.png`.

**To regenerate icons** from the PNG source:
```js
// Run in node (sharp is a devDependency)
const sharp = require('sharp');
sharp('public/icon.png').resize(192,192).png().toFile('public/icon-192.png', cb);
sharp('public/icon.png').resize(512,512).png().toFile('public/icon-512.png', cb);
sharp('public/icon.png').resize(64,64).png().toFile('public/favicon.png', cb);
```

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
- **PaySplits: Simplify debts toggle + opening balances** (v19) — Splitwise-style toggle in Balance tab (ON = fewest payments via greedy netting incl. wallet + opening balances; OFF = debts as recorded, wallet/opening shown vs "Club Pool"); admin-only per-player opening balance (± amount, one entry per player, for migrating from another app); warning when opening balances don't net to zero
- **Super Admin Panel** (v22) — `/admin` route guarded at router level; 6-tab panel (Stats | Users | Clubs | Facilities | Tournaments | Roles); admin can view, rename/delete clubs, edit/delete facilities, delete tournaments, grant/revoke roles; sajeevsahadev@gmail.com self-grant INSERT in v22_schema.sql
- **GDPR account deletion** (v31) — Profile → Danger Zone; `check_can_delete_account()` pre-check blocks on club ownership, match history, or non-zero wallet/PaySplit balance; `delete-account` Edge Function anonymises FKs then calls `auth.admin.deleteUser()`
- **Onboarding wizard re-trigger** — accessible any time from the hamburger menu's "Club Setup Wizard" action, not just on first login
- **Profile settings expansion** (v32) — Gender field (incl. "Rather not to say"); Email Settings + Push Settings preference pages (saved now, most categories not wired to real sending yet — see notes under those views); Security page with a real WebAuthn biometric app-lock (register/verify/Trusted Devices/timeout, app-lock-only — never replaces Google sign-in); Appearance picker (Light fully live, Dark/System save the preference but show "Soon" since no dark palette exists); Sign Out moved from the hamburger to Profile; Privacy Policy page (`/privacy`)
- **`user_profiles` RLS lockdown** (v33) — fixed a real gap where `phone`/`gender`/`full_name` were SELECT-able by any authenticated client via the REST API; RLS is now owner-row-only, with `get_public_profiles()`/`get_member_profile_names()`/`resolve_public_nickname()` SECURITY DEFINER RPCs covering every legitimate cross-user read that used to rely on the open policy
- **Admin player profile** (v34) — `admin_get_player` + `admin_get_player_matches` RPCs; `PlayerProfile.vue ?admin=1` shows full player data + match history for app_admin; "column reference user_id is ambiguous" fixed by qualifying all joins
- **Multi-payer PaySplits** (v36) — `paysplit_expense_payers` table; add/edit expense supports multiple payers with individual amounts; balance summary uses proportional debt edges; opening balances shown as collapsible ribbon in Expenses tab; Splitwise-style inline amount inputs per payer
- **FIFO performance fix** (v36b) — `get_fifo_result` SECURITY DEFINER RPC replaces O(n²) JS FIFO with O(C+W) SQL window functions; `PaySplits.vue` loads result via RPC instead of computing in browser
- **Global push notifications** (v35) — `push_subscriptions.club_id` nullable; subscribe no longer requires a club; `PushSettings.vue` works for users with zero clubs
- **Login → dashboard redirect** — `router/index.js` redirects logged-in users hitting `/` to `/dashboard` instead of showing the public landing page again
- **Zoom disabled** — `index.html` viewport meta has `user-scalable=no, maximum-scale=1.0` so the app feels native
- **New app icon** — neon shuttlecock PNG (`public/icon.png`); regenerated `icon-192.png`, `icon-512.png`, `favicon.png`; `index.html` now uses `favicon.png`
- **Email sending wired up** — `send-match-email` (after match recorded), `send-expense-email` (after expense added), `send-weekly-digest` (auto Monday 8am UTC via pg_cron), `send-announcement` (admin-triggered from Admin Panel → Announcements tab)
- **Admin Panel Announcements tab** (7th tab) — app_admin can write subject + body, send to all users with `email_prefs.news = true`; calls `send-announcement` Edge Function

### ❌ Not Yet Implemented
- **Photo upload** — requires Supabase Storage bucket; currently `image_url` is paste-any-URL
- **Facility admin role** — creator is currently the de-facto owner; formal role pending
- **Online court booking** — schedule visible but can't reserve online
- **Push notification sending** — Web Push infrastructure wired up (DB tables + SW handler + composable + global subscribe); requires VAPID key and a `send-push` Edge Function to fan out messages
- **Real Dark theme** — `useTheme.js` + `darkMode:'class'` + the Appearance picker are wired, but no dark CSS palette has been written; selecting Dark just saves the preference for later. Converting `style.css` + every view to theme-aware CSS variables is its own pass (~20 files).
- **Payment reminder emails** — preference saved in `email_prefs.payment_reminders` but no sender job built yet
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
2. SQL Editor → run all migration files in order (see section 5, v1–v37)
3. Auth → Providers → Google → enable → paste Client ID + Secret
4. Auth → URL Configuration → add `https://badmint.vercel.app/**` + localhost
5. Google Cloud Console → OAuth Client → add Vercel URL as authorised origin
6. Enable **pg_cron** + **pg_net** extensions (Database → Extensions) then run v37_schema.sql with real PROJECT_REF + SERVICE_ROLE_KEY filled in

### Edge Functions (deploy after any change)
```bash
npx supabase functions deploy send-match-email
npx supabase functions deploy send-expense-email
npx supabase functions deploy send-weekly-digest
npx supabase functions deploy send-announcement
npx supabase functions deploy delete-account
```
Supabase project ref: `bdmiirppiyopmdfrztoz`

### Supabase secrets required
```
RESEND_API_KEY          = re_...   (Resend dashboard)
SUPABASE_SERVICE_ROLE_KEY = ...    (Project Settings → API → service_role)
```

### Environment variables (Vercel dashboard)
```
VITE_SUPABASE_URL         = https://bdmiirppiyopmdfrztoz.supabase.co
VITE_SUPABASE_ANON_KEY    = your-anon-key
VITE_VAPID_PUBLIC_KEY     = your-vapid-public-key
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
