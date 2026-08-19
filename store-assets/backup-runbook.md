# Supabase → Google Drive weekly backup

An independent, off-platform copy of the whole database, in **your** Google
Drive. Runs every **Sunday 03:00 UTC** via GitHub Actions and keeps the newest
**7** backups. Workflow: `.github/workflows/supabase-backup.yml`.

> Think of this as *defense in depth*. If you're on Supabase Pro, also keep its
> built-in daily backups / Point-in-Time-Recovery on — that's your fast first
> layer. This Drive copy survives even if the whole Supabase project is lost.

Nothing runs until you add the **3 GitHub secrets** below. You do these once.

---

## 1. `SUPABASE_DB_URL` — the database connection string

Supabase → your project → **Project Settings → Database → Connection string →
URI**, and pick the **Session pooler** tab (IPv4, port **5432** — GitHub's
runners are IPv4-only, and pg_dump needs session mode, not the 6543 transaction
pooler).

It looks like:
```
postgresql://postgres.bdmiirppiyopmdfrztoz:YOUR-DB-PASSWORD@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
```
- Replace `YOUR-DB-PASSWORD` with the database password (Settings → Database →
  *Reset database password* if you don't have it).
- Keep `?sslmode=require`.

GitHub repo → **Settings → Secrets and variables → Actions → New repository
secret** → name `SUPABASE_DB_URL`, paste the URI.

## 2. `GDRIVE_FOLDER` — the Drive folder name

Create a folder in your Google Drive, e.g. **`BadmintonBackups`**. Add a secret
`GDRIVE_FOLDER` with the value `BadmintonBackups`.

## 3. `RCLONE_CONF_BASE64` — Google Drive credentials for rclone

rclone is the uploader. Configure it once on your computer:

1. Install rclone: <https://rclone.org/downloads/> (Windows: download the exe).
2. Run `rclone config`:
   - `n` (new remote) → name it **exactly** `gdrive`
   - Storage: `drive` (Google Drive)
   - client_id / client_secret: press Enter to leave blank (uses rclone's built-in)
   - scope: `1` (full access) — or `drive.file` if you prefer least-privilege
   - Leave the rest default; when it asks to use the browser for auth, say **yes**
     and sign in with the Google account whose Drive you want to back up to.
   - `y` to confirm, then `q` to quit.
3. Base64-encode the config and copy it:
   - **Windows PowerShell:**
     ```powershell
     [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\rclone\rclone.conf")) | Set-Clipboard
     ```
   - **Mac/Linux:** `base64 -w0 ~/.config/rclone/rclone.conf | pbcopy`
4. Add a secret `RCLONE_CONF_BASE64` and paste the base64 string.

> The rclone OAuth token auto-refreshes, so this keeps working without
> re-auth. (For a token that never needs a human, a Google **service account**
> shared into the folder also works — ask if you want that instead.)

---

## Turn it on & test

1. After adding the 3 secrets, go to the repo's **Actions** tab → **Weekly
   Supabase backup to Google Drive** → **Run workflow** (manual trigger) to test
   immediately instead of waiting for Sunday.
2. Watch the run; on success a `badminton360-backup-YYYY-MM-DD.dump` appears in
   your Drive folder.

## Change the schedule / retention

In `supabase-backup.yml`:
- **Schedule:** the `cron:` line. `0 3 * * 0` = Sundays 03:00 UTC. For daily,
  use `0 3 * * *`.
- **Retention:** the `head -n -7` in the prune step keeps the newest 7. Change
  `7` to keep more/fewer.

## Restore (if you ever need it)

The `.dump` is PostgreSQL custom format. Restore into any Postgres 17 database:
```bash
pg_restore --no-owner --no-privileges --clean --if-exists \
  -d "postgresql://.../postgres" badminton360-backup-YYYY-MM-DD.dump
```
Notes:
- This captures **all database data** (public app tables + `auth.users`
  accounts, etc.).
- It does **not** capture Storage *files* (avatars live in the `avatars`
  bucket — object bytes are in Supabase's storage, not the DB). Those are
  re-uploadable and low-risk; if you want them backed up too, we can add an
  `rclone` sync of the bucket via the Storage S3 endpoint.
- Restoring into a brand-new Supabase project may warn on Supabase-managed
  roles/extensions — the **data** restores fine, which is the point.

## Cost

Free. GitHub Actions gives 2,000 free minutes/month; this job runs ~2 minutes
once a week. A 111 MB DB compresses to a small `.dump`.
