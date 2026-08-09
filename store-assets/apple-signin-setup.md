# Enable "Sign in with Apple" — your setup checklist

The **code is already done and deployed** (Apple button on the login screen). It stays
inert until you complete the config below. None of these are secrets I handle — you
create the key and paste it into Supabase yourself.

Values you'll collect along the way: **Team ID**, **Services ID**, **Key ID**, **.p8 key file**.

---

## A. Apple Developer portal — https://developer.apple.com/account → Certificates, Identifiers & Profiles

### 1. App ID
- **Identifiers → + → App IDs → App**
- Description: `Badminton 360`
- Bundle ID (explicit): **`app.badminton360`**  ← this is also your iOS app's bundle id
- Capabilities: tick **Sign In with Apple**
- Register.
- Note your **Team ID** (top-right of the portal, 10 characters).

### 2. Services ID  (this becomes the web "Client ID")
- **Identifiers → + → Services IDs**
- Description: `Badminton 360 Web`
- Identifier: **`app.badminton360.web`**
- After creating, tick **Sign In with Apple → Configure**:
  - Primary App ID: `app.badminton360`
  - **Domains and Subdomains:** `bdmiirppiyopmdfrztoz.supabase.co` , `badminton360.app`
  - **Return URLs:** `https://bdmiirppiyopmdfrztoz.supabase.co/auth/v1/callback`
  - Save.

### 3. Sign in with Apple Key
- **Keys → +**
- Key Name: `Badminton 360 SIWA`
- Tick **Sign in with Apple → Configure** → Primary App ID: `app.badminton360`
- Register → **Download the `AuthKey_XXXXX.p8`** (⚠️ downloadable only once — keep it safe)
- Note the **Key ID** (10 characters).

---

## B. Generate the Supabase client secret (on your machine)

From the project folder, run (fill in your real values + the path to the .p8 you downloaded):

```bash
node scripts/generate-apple-secret.js <TEAM_ID> <KEY_ID> app.badminton360.web ./AuthKey_XXXXX.p8
```

It prints a long token. That token is the "client secret." (Your `.p8` never leaves your
computer — don't commit it or paste it anywhere.)

---

## C. Supabase → Authentication → Providers → Apple

- **Enable** the Apple provider.
- **Client IDs:** `app.badminton360.web`  *(later, for the native iOS build, also add `app.badminton360`, comma-separated)*
- **Secret Key (for OAuth):** paste the token from step B.
- Save.

## D. Supabase → Authentication → URL Configuration
- Make sure **Site URL** and **Redirect URLs** include `https://badminton360.app` (they already do for Google — no change if so).

---

## Done — test it
Open `https://badminton360.app/login` and tap **Sign in with Apple**. It should hand off
to Apple and sign you in. If you get "provider is not enabled," the Supabase step (C) isn't
saved yet.

**Reminder:** the client secret expires in ~6 months — just re-run step B and update
Supabase when it does.

---

## What I still need from you (to keep going)
1. **Confirm the bundle id** `app.badminton360` (or tell me a different one) — it goes in the App Store listing and the iOS build.
2. Once the cloud Mac is ready, tell me and I'll give you the exact **PWABuilder vs Capacitor** build steps for iOS.
