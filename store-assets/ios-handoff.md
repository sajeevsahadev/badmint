# iOS App Store — handoff (read this first on the Mac)

Written 2026-11-14 on the Windows PC so the work can continue on the Mac. It collects
everything known about the iOS launch that is not already in the other files here.

Read order: this file → `apple-signin-setup.md` → `ios-build-runbook.md` → `app-store-listing.md`.

---

## 1. The goal

Publish **Badminton 360** on the Apple App Store with the **same features as the Android
app**. Android is the PWA at `https://badminton360.app` wrapped as a TWA (see
`android-play-runbook.md`). iOS is the same PWA wrapped with **PWABuilder** (a WKWebView
shell). Nothing is built from this repo's source on the Mac: the wrapper loads the live
site, so every web deploy reaches the iOS app without a new App Store build.

Fallback if Apple rejects for "minimum functionality" (Guideline 4.2): migrate the
wrapper to **Capacitor**.

## 2. Fixed values

| Thing | Value |
|---|---|
| App name | `Badminton 360` |
| Subtitle | `Club rankings, chat & splits` |
| Bundle id (iOS app + App ID) | `app.badminton360` — **confirm before registering; it cannot be changed later** |
| Services ID (web client id for Apple sign-in) | `app.badminton360.web` |
| SKU | `badminton360` |
| Version / build | `1.0.0` / `1` |
| Live URL the wrapper loads | `https://badminton360.app` |
| Supabase project ref | `bdmiirppiyopmdfrztoz` |
| Apple sign-in return URL | `https://bdmiirppiyopmdfrztoz.supabase.co/auth/v1/callback` |
| Services ID domains | `bdmiirppiyopmdfrztoz.supabase.co`, `badminton360.app` |
| Privacy policy URL | `https://badminton360.app/privacy` |
| Support / marketing URL | `https://badminton360.app` |
| Category / age rating / price | Sports / 4+ / Free |
| Icon | `store-assets/appstore-icon-1024.png` (1024×1024, no alpha; regenerate with `scripts/generate-appstore-icon.js`) |
| Screenshot size | 1290×2796 (iPhone 16 Pro Max simulator, ⌘S) |

## 3. What is already done

- **Sign in with Apple code** (commit `34ac163`): `useAuth().signInWithApple()` in
  `src/composables/useAuth.js` and the black Apple button in `src/views/Login.vue`. It
  does nothing until the Apple provider is enabled in Supabase.
- **In-app account deletion** (Profile → Danger Zone). Apple requires this (5.1.1(v)).
- **Privacy policy page** at `/privacy`.
- Listing copy, icon, Apple sign-in checklist, Mac-day runbook: all in this folder.
- `scripts/generate-apple-secret.js`: makes the Apple client-secret token locally from
  the `.p8` key, so the key never leaves the machine.

## 4. What is NOT done / not verified

Status as of 2026-11-14. Nothing below has been tested on an iOS device or simulator.

- [ ] Bundle id confirmed by the owner
- [ ] Apple portal: App ID, Services ID, Sign in with Apple key (`apple-signin-setup.md` A)
- [ ] Client secret generated and Apple provider enabled in Supabase (B, C)
- [ ] Sign in with Apple tested on `https://badminton360.app/login`
- [ ] App Store Connect agreements accepted
- [ ] PWABuilder package generated, opened and signed in Xcode
- [ ] The four iOS differences in section 5 tested
- [ ] Donation link decision (section 6)
- [ ] Screenshots, listing, App Privacy, submit

## 5. Where iOS differs from Android (test these on the simulator first)

The wrapper is an embedded web view, not a full browser. Four features may behave
differently. Test each one before archiving and note the result here.

1. **Google sign-in.** Google usually refuses sign-in inside embedded web views
   (error `disallowed_useragent`). If it fails: either change the wrapper so the Google
   sign-in page opens in the system browser sheet (`ASWebAuthenticationSession` /
   `SFSafariViewController`), or hide the Google button inside the iOS wrapper and offer
   Apple sign-in only. Existing users who signed up with Google would then need the first
   option, so prefer it.
2. **Push notifications.** Web Push does not work inside the wrapper. Real iOS push needs
   Apple push (APNs) capability, a device-token bridge from the wrapper to the web app,
   and a sender. This is separate work; version 1.0 can ship without push. Until then the
   Push Settings page should not promise notifications on iOS.
3. **Camera and microphone** (the `/record` screen and AI Match Analysis). `getUserMedia`
   works in WKWebView only if `Info.plist` declares why. Add:
   - `NSCameraUsageDescription` — `Badminton 360 uses the camera to record your match for AI analysis.`
   - `NSMicrophoneUsageDescription` — `Badminton 360 uses the microphone to record sound with your match video.`
   Without these the app crashes when the camera opens, and Apple rejects the build.
4. **Biometric app-lock** (Settings → Security, WebAuthn platform authenticator). May not
   be available in the wrapper without an Associated Domains setup. If
   `isPlatformAvailable` is false it already hides itself; if it shows but fails, hide
   the toggle inside the iOS wrapper.

Also check: the PWA install banners and the "install on iPhone" section should not show
inside the wrapper (they key off standalone display mode; confirm the wrapper counts).

## 6. Rejection risks

| Guideline | Risk | Position |
|---|---|---|
| 4.8 Sign in with Apple | Required because Google login is offered | Code done; needs Supabase config |
| 4.2 Minimum functionality | App is a web wrapper | Feature-rich; review notes point to public "Browse Clubs"; fallback is Capacitor |
| 3.1.1 Payments | `/support` page ("Buy us a shuttle") links to an external payment page (Ziina). Apple commonly rejects donation links outside in-app purchase | **Undecided.** Safest: hide the Support link (hamburger menu + Profile footer) when running inside the iOS wrapper |
| 3.1.1 Payments | "Split Pay" / PaySplits / Wallet could look like payments | It only records who owes what; no money moves. Say so in the review notes |
| 5.1.1(v) Account deletion | Must be possible in-app | Done |
| 5.1.1 Login for review | Auth is OAuth-only, so there is no username/password demo account | Reviewer uses "Browse Clubs" without login, or signs in with their own Apple ID. If Apple insists on a demo account, an email/password test login would have to be added |
| 5.1.2 Privacy labels | App now handles video and opt-in face recognition | Declare them (section 7) |

Detecting the iOS wrapper from the web app (for hiding things): PWABuilder's iOS shell
adds a marker to the user agent / sets a cookie (check the generated project's
`Settings.swift` for the exact name) — use that, not a generic iPhone check, so Safari
users keep the full site.

## 7. App Privacy questionnaire — draft answers (confirm each against the live app)

Tracking: **No** (no ad networks, no cross-app tracking).

Data collected, all **linked to the user**, purpose **App Functionality**:

- Contact info: name, email (from Google/Apple sign-in); phone number (optional profile field)
- User content: match videos uploaded for analysis; club chat messages; photos/avatars
- Identifiers: user ID
- Usage data: product interaction (page views in the activity log)
- Location: coarse location (country from IP)
- Sensitive / other: face data, **only** if the user turns on face recognition
  (Settings → Security); deleted when they turn it off. Also body measurements
  (height/weight) and injury notes if the user enters them for AI coaching — declare
  under Health & Fitness if those fields are live.
- Financial info: not collected (expense splitting stores amounts between friends, no
  payment details).

Third parties that process data (already listed in the privacy policy — keep in sync):
Supabase, Google, Apple, Resend, ipapi.co / Cloudflare, plus the AI analysis providers
(Gemini, Modal, video storage). Check `/privacy` names all of them before submitting.

## 8. Review notes (paste into App Review Information)

> Badminton 360 is a free club-management app for badminton groups. You can tap "Browse
> Clubs" without signing in to see clubs, players and facilities. To use the full app,
> sign in with Apple. "Split Pay" only records shared expenses among friends; no money is
> transferred in the app and nothing is sold, so there are no in-app purchases. Account
> deletion is under Profile → Danger Zone.

## 9. Things only the owner can do

Apple portal work, the `.p8` key, running `generate-apple-secret.js`, Supabase Apple
provider, App Store Connect agreements, Xcode signing, archive/upload, screenshots,
privacy questionnaire, submit.

**Never paste into a chat or commit:** the `.p8` file, the generated client secret, the
Apple ID password, the Mac login. The client secret expires after about 6 months —
re-run the script and update Supabase.

## 10. Using this on the Mac

```bash
git clone https://github.com/sajeevsahadev/badmint.git
cd badmint && npm install
```

Open the folder in Claude Code; it reads `CLAUDE.md` (full project context) and this
file. No `.env` is needed for the iOS build. Node is needed only for
`generate-apple-secret.js`.
