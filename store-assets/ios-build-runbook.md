# iOS build & submit — runbook for the cloud‑Mac day

Everything you run on the Mac, in order. I've done all the prep (icon, copy, Apple
sign‑in code). You run these steps; ping me on any error and I'll fix it live.

**Recommended path: PWABuilder** — fastest for a 1‑day window (the app is already a
polished PWA at `https://badminton360.app`). If Apple later rejects on "minimum
functionality" (Guideline 4.2), we switch to Capacitor — but try this first.

---

## Before the Mac (do these first, off the Mac)
1. ✅ App is live at `https://badminton360.app` (done).
2. ☐ **Apple sign‑in configured** — follow `apple-signin-setup.md` (App ID, Services ID,
   key, Supabase provider). Do this BEFORE submitting or review login fails.
3. ☐ Bundle id confirmed: **`app.badminton360`**.
4. ☐ In **App Store Connect** (any browser): accept any pending **Agreements** (Business →
   Agreements). Free apps don't need banking/tax, but the main agreement must be active.

## On the Mac (via macrent.cloud remote desktop)

### 1. Xcode
- Ensure **Xcode** is installed (App Store on the Mac). It's a big download — start it first.
- Open Xcode once → **Settings → Accounts → +** → sign in with **your Apple Developer ID**.

### 2. Generate the iOS package with PWABuilder
- In Safari on the Mac: **https://www.pwabuilder.com**
- Enter `https://badminton360.app` → **Start** → **Package For Stores → iOS → Generate**.
- Options to set:
  - **Bundle ID:** `app.badminton360`
  - **App name:** `Badminton 360`
  - **URL:** `https://badminton360.app`
  - Leave the rest default.
- **Download** the zip → unzip it.

### 3. Open + sign in Xcode
- Open the `.xcodeproj` / `.xcworkspace` from the unzipped folder in Xcode.
- Select the project → **Signing & Capabilities**:
  - Tick **Automatically manage signing**
  - **Team:** your developer team
  - **Bundle Identifier:** `app.badminton360`
- Set **Version** `1.0.0` and **Build** `1`.

### 4. Capture screenshots (do this before archiving)
- Top bar: choose the **iPhone 16 Pro Max** simulator (that's the 6.7" size Apple requires).
- **Product → Run** (▶). When the app loads, sign in (Apple), then press **⌘S** on these 5 screens:
  1. Dashboard / leaderboard  2. Record a match  3. Club chat  4. Split Pay balance  5. Schedule poll
- Screenshots save to the Desktop at **1290×2796** — exactly what App Store Connect wants.

### 5. Archive + upload
- Top bar target: **Any iOS Device (arm64)** (not a simulator).
- **Product → Archive** → when done, the Organizer opens.
- **Distribute App → App Store Connect → Upload** → Next through the defaults → **Upload**.
- Wait for "Upload successful." (Processing on Apple's side takes 5–30 min.)

## Back in App Store Connect (browser)
### 6. Create the app record (if not already)
- **My Apps → + → New App**: name `Badminton 360`, primary language English,
  Bundle ID `app.badminton360`, SKU `badminton360`.

### 7. Fill the listing (copy from `app-store-listing.md`)
- Name, Subtitle, Promo text, Description, Keywords, Support/Marketing/Privacy URLs.
- Upload **`appstore-icon-1024.png`**.
- Upload the **6.7" screenshots** from step 4.
- **Pricing:** Free.
- **App Privacy:** fill the questionnaire (data collected: name/email for account, usage;
  linked to identity; not used for tracking). I can give exact answers when you reach it.

### 8. Build + review info
- In the version page, select the **build** you uploaded (appears after processing).
- **App Review Information:**
  - Sign‑in required: **Yes**.
  - Notes (paste): reviewer can tap **"Browse Clubs"** (public, no login) to see clubs,
    players and facilities, and can **Sign in with Apple** to access the full app. "Split
    Pay" only records who owes what among friends — no real money is transacted, so no IAP.
  - Contact: your name, phone, `sajeevsahadev@gmail.com`.

### 9. Submit
- **Add for Review → Submit.** First review is usually 24–48h.

---

## Everything that depends on YOU (I can't do these)
| Dependency | Why it's yours |
|---|---|
| Apple sign‑in config (portal + Supabase) | involves your `.p8` key |
| Accept App Store Connect agreements | your account |
| Sign into Xcode with your Apple ID | signing certs are tied to your account |
| Run PWABuilder + Xcode archive/upload | needs macOS + your credentials |
| Capture simulator screenshots | runs on your Mac |
| Fill App Privacy questionnaire + submit | your account |

## What I keep doing
- Fix any build/JS error live, adjust the web app, answer the App Privacy questions,
  tune the listing, and if 4.2 rejection happens, do the Capacitor migration.

**Do NOT send me:** your Mac login, Apple ID password, the `.p8` file, or the generated
Apple secret. Those stay with you.
