# Badminton 360 — Security Assessment

_Last assessment: 2026-07-05. Scope: full stack — Vue frontend, Supabase (RLS,
RPCs, Edge Functions), deployment. Methodology: OWASP Top 10 (2021) review +
Supabase database linter + dependency audit + manual code review._

## Summary

Overall posture is **solid**. The app's core security model — RLS enabled on
every table, all writes funnelled through SECURITY DEFINER RPCs that check
authorization via `auth.uid()`/`is_manager()`/`is_app_admin()`, Google-OAuth-only
auth, no secrets in the client bundle — held up. Two database-layer issues were
found and fixed in migration `v49_schema.sql`. No exploitable frontend or Edge
Function vulnerabilities were found.

## Findings

### Fixed (v49)

| # | Severity | Class | Finding | Fix |
|---|----------|-------|---------|-----|
| 1 | Medium | A01 Broken Access Control | `get_club_players` executable by anon returned auth `user_id` + `last_seen_at` (presence) for every player in every club — unauthenticated roster/activity scraping | Revoked anon EXECUTE; `authenticated` only |
| 2 | Low-Med | A01 / PII exposure | `get_public_profiles` executable by anon — nickname/bio/emirate/avatar scrapeable by logged-out callers | Revoked anon EXECUTE; `authenticated` only |
| 3 | Low | A01 | `accept_invite` executable by anon — an anonymous call with a token could consume/burn an invite | Revoked anon EXECUTE; `authenticated` only |
| 4 | Medium | A05 Misconfig / CWE-426 | 13 SECURITY DEFINER functions had a mutable `search_path` (search_path-injection risk) | Pinned `search_path = public` on all definer functions missing it |

### Reviewed — no action needed

- **Injection (A03):** No dynamic SQL built from user input in RPCs; all use
  parameterized args. No `v-html`, `eval`, `innerHTML`, or `new Function` in the
  frontend. Edge Functions pass user data as JSON, not string-concatenated SQL.
- **Secrets (A02/A07):** Client bundle exposes only the Supabase **anon key** and
  **VAPID public key** (both designed to be public). Service-role key and Resend
  key live only in Edge Function env. `Bearer` tokens in the frontend are the
  user's own session token.
- **Edge Functions:** `delete-account` and `send-email` run with `verify_jwt:false`
  but both authenticate manually — `delete-account` verifies the caller's JWT and
  only ever deletes the caller's own `user.id`; `send-email` requires the
  service-role key as bearer. The `send-*email` functions verify the caller is an
  authenticated user before sending.
- **RLS (A01):** Enabled on **every** public table (0 gaps). `user_profiles` is
  owner-row-only (v33); cross-user reads go through vetted SECURITY DEFINER RPCs.
- **Dependencies (A06):** `npm audit --omit=dev` → 0 vulnerabilities.
- **Remaining anon-granted RPCs:** ~90 SECURITY DEFINER functions are still
  granted to anon but each self-protects — `auth.uid()` is NULL for anon, so
  `is_manager()`/`is_member()`/`is_app_admin()` return false and the body raises.
  Not exploitable; broad REVOKE deferred to avoid breaking genuinely-public pages.
- **SECURITY DEFINER views** (leaderboard/pairs/rankings): flagged by the linter
  but required by design (CLAUDE.md rule 19). Read-only, expose only public
  nickname/elo.
- **Leaked-password protection:** N/A — Google OAuth only, no password auth.

## DDoS / rate limiting

App-layer rate limiting is intentionally not implemented; it's handled at the
infrastructure edge:
- **Vercel** fronts the static PWA (CDN + platform DDoS mitigation).
- **Supabase** API gateway applies per-project rate limits on REST/RPC/Auth.
- **Cloudflare** DNS fronts `badminton360.app`.

Residual consideration: expensive anon-callable read RPCs (`get_public_clubs`,
`get_top_scorers`, `get_facilities`) could be hammered. These are cheap view reads
and covered by Supabase's gateway limits. If abuse appears, enable Cloudflare
proxy/WAF rate rules on the API hostname — no code change required.

## Recommendations (not yet done)

1. **Rotate the Supabase service-role and Resend keys** if they were ever pasted
   into a migration file, chat, or commit (v37 template had placeholders — verify
   the real keys only live in Supabase secrets / Vercel env).
2. Consider deleting the generic `send-email` Edge Function if unused (the
   specific `send-*email` functions supersede it) to shrink attack surface.
3. Longer term, revoke anon EXECUTE from all authenticated-only RPCs (defense in
   depth) once each public page's RPC dependency is confirmed.
