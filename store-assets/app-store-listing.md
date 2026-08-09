# Badminton 360 — Apple App Store submission pack

Everything here is copy‑paste ready for **App Store Connect**. Assets live in this
`store-assets/` folder. Read the **"⚠️ Two Apple blockers"** section first — those
decide whether the app gets approved at all.

---

## 1. App information (copy‑paste)

| Field | Value | Limit |
|---|---|---|
| **App Name** | `Badminton 360` | ≤30 chars ✅ (13) |
| **Subtitle** | `Club rankings, chat & splits` | ≤30 chars ✅ (28) |
| **Primary category** | Sports | |
| **Secondary category** | Utilities *(or Social Networking)* | |
| **Age rating** | 4+ | |
| **Copyright** | `2026 Badminton 360` | |
| **Bundle ID** | `app.badminton360` *(or your chosen reverse‑domain id)* | |

### Promotional text (≤170 chars — editable any time without review)
```
The all-in-one app for your badminton club: Elo rankings, match tracking, group chat, expense splitting and tournaments. Free forever.
```

### Keywords (≤100 chars, comma-separated, NO spaces)
```
badminton,club,elo,ranking,doubles,tournament,match,score,leaderboard,expense,split,court,shuttle
```

### Description
```
Badminton 360 is the all-in-one app for your badminton club — rankings, match tracking, group chat, expense splitting and tournaments, all in one place. Free forever.

RANKINGS THAT ARE ACTUALLY FAIR
• Automatic Elo ratings for doubles — the app does the math after every match
• Club leaderboard with win %, games played and best pairs
• A global players board across all clubs

RUN YOUR CLUB IN SECONDS
• Record a match in a few taps: pick 4 players, set sides, enter the score
• Full match history with rename, delete and instant recalculation
• Invite players by link, email or WhatsApp

PLAN THE NEXT GAME
• "Who's playing?" attendance polls with a shareable link
• Match-day scheduling tied to your venue

SPLIT THE COURT FEES, PAINLESSLY
• PaySplits: log a shared expense and split it fairly
• A club wallet with contribution tracking
• See who owes what at a glance

CLUB CHAT
• A private chat for each club — messages, emojis, reactions, replies and photos
• Push notifications so nobody misses a game

TOURNAMENTS
• Create single-elimination or round-robin tournaments
• Register teams, generate the bracket, record results

Made for badminton groups everywhere. No ads. No cost.
```

### URLs
| Field | Value |
|---|---|
| **Support URL** | `https://badminton360.app` |
| **Marketing URL** | `https://badminton360.app` |
| **Privacy Policy URL** | `https://badminton360.app/privacy` |

---

## 2. Required assets

| Asset | Requirement | Status |
|---|---|---|
| **App icon** | 1024×1024 PNG, sRGB, no alpha, no rounded corners | ✅ `store-assets/appstore-icon-1024.png` |
| **iPhone 6.7" screenshots** | 1290×2796 px, 1–10 images — **mandatory** | ⛔ you capture (see below) |
| **iPhone 6.5" screenshots** | 1242×2688 px | optional (can reuse 6.7") |
| **iPad 12.9" screenshots** | 2048×2732 px — only if you enable iPad | optional |

**Screenshots — how to capture:** once the iOS build runs (step 4 below), open it in
the **iOS Simulator** (iPhone 15 Pro Max = 6.7"), press **⌘S** on these 5 screens and
you're done:
1. Dashboard / leaderboard  2. Record a match  3. Club chat  4. PaySplits balance  5. Schedule poll
Apple only strictly needs the **6.7"** set; it reuses them for smaller sizes.

---

## 3. App Review information (fill in App Store Connect → "App Review Information")

- **Sign-in required?** Yes → **you MUST provide a demo account** (see blocker #1).
- **Demo account:** create a throwaway club + login the reviewer can use (once Sign in with Apple or an email login exists).
- **Contact:** your name, phone, email (`sajeevsahadev@gmail.com`).
- **Notes to reviewer (paste this):**
```
Badminton 360 is a club-management app for badminton groups: Elo rankings, match
recording, scheduling, a private per-club chat, and expense splitting.

"Split Pay / PaySplits" is a bookkeeping tool for splitting court fees among friends
— it only records who owes what. No real money is transacted inside the app, so no
in-app purchases are used. The app is free with no paid features.

Demo login: <email> / <password>  (pre-joined to the "Demo Club").
```

---

## ⚠️ 4. Two Apple blockers you must clear BEFORE submitting

Apple is far stricter than Google Play. Two rules will get the app rejected as-is:

### Blocker A — "Sign in with Apple" is required (Guideline 4.8)
The app currently offers **Google sign-in only**. Apple's rule: if you offer a
third-party login (Google), you **must also offer "Sign in with Apple."** Without it,
rejection is near-certain. It also solves the reviewer-login problem.
**This is a development task** — Supabase supports Apple as an auth provider. It needs:
- An **Apple Services ID** + **Sign in with Apple key** created in the Apple Developer portal
- The Apple provider enabled in **Supabase → Auth → Providers**
- A "Sign in with Apple" button added to the login screen
👉 I can implement this end-to-end — just say go.

### Blocker B — "Minimum functionality" (Guideline 4.2)
Apple rejects apps that are "just a website in a wrapper." Badminton 360 is genuinely
feature-rich (rankings engine, chat, tournaments, expense splitting), so it should
pass — but a plain WKWebView wrapper is the riskiest packaging. The **review notes**
above and native touches (Sign in with Apple, push, share) help it read as a real app.

---

## 5. How to actually build the iOS app (pick one)

You have a web app + a Google Play TWA. iOS needs its own build:

- **Option A — PWABuilder iOS package** (fastest): pwabuilder.com → enter
  `https://badminton360.app` → download the iOS package → open in **Xcode** (needs a
  Mac) → set bundle id + signing → Archive → upload to App Store Connect. Higher 4.2 risk.
- **Option B — Capacitor** (more robust, recommended for App Store): wrap the existing
  Vite build with Capacitor, add native plugins (push, share). More work, safer review.

Either way you need a **Mac with Xcode** (or a Mac cloud service like MacinCloud) to
build and upload — Apple requires it.

---

## 6. Step-by-step — what to do, in order

1. ☐ **Ask me to add "Sign in with Apple"** (Blocker A) — required before anything else.
2. ☐ In **Apple Developer** portal: create the **App ID** (`app.badminton360`), enable
   "Sign in with Apple", create the **Services ID** + **key** (I'll tell you exactly which values I need — none are secrets I handle; you paste keys into Supabase yourself).
3. ☐ In **App Store Connect**: **My Apps → +** → create the app (name, bundle id, SKU).
4. ☐ Fill the **App Information** + **Pricing (Free)** + **App Privacy** questionnaire.
5. ☐ Paste the **listing copy** (section 1) and upload the **1024 icon**.
6. ☐ **Build the iOS app** (section 5) on a Mac, upload the build via Xcode/Transporter.
7. ☐ Capture **screenshots** from the Simulator, upload the 6.7" set.
8. ☐ Fill **App Review Information** + demo account (section 3).
9. ☐ **Submit for review.** First review is typically 24–48h.

---

**Bottom line:** the copy + icon are ready. The real gating items are **(1) a Mac to
build**, and **(2) adding Sign in with Apple** — start with #2, which I can build now.
