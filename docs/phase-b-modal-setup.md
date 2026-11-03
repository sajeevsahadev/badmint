# Phase B — turning on the real AI engine (Modal)

Everything in the app is already built and wired. The only thing left is standing up the GPU worker
on **Modal** and giving Supabase two secrets. Until you do this, the app falls back to clearly-labelled
**sample analysis**, so nothing is broken in the meantime.

Do these steps when you're ready. They take ~20 minutes.

---

## 1. Create a Modal account + CLI (your machine)
1. Sign up at **https://modal.com** (free credits to start).
2. Install the CLI and log in:
   ```bash
   pip install modal
   ```
   ```bash
   modal token new
   ```

## 2. Create the Modal secret (one bundle named `badminton-ai`)
The worker needs to read the video from R2 and write results to Supabase. Create one Modal secret
holding all of these keys (dashboard: **Modal → Secrets → Create → Custom**, or CLI below):

```bash
modal secret create badminton-ai \
  SUPABASE_URL=https://bdmiirppiyopmdfrztoz.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=<Supabase → Settings → API → service_role> \
  R2_ACCOUNT_ID=ec52a38cc5c9769a2266d172e1f85206 \
  R2_VIDEO_ACCESS_KEY_ID=<same value you put in Supabase> \
  R2_VIDEO_SECRET_ACCESS_KEY=<same value you put in Supabase> \
  R2_VIDEO_BUCKET=badminton360-videos \
  ANALYZE_SHARED_SECRET=<make up a long random string, keep it>
```
> Keep the `ANALYZE_SHARED_SECRET` value — you'll paste the **same** one into Supabase in step 4.

## 3. Deploy the worker
From the repo root:
```bash
modal deploy modal/analyze.py
```
When it finishes, Modal prints a **web endpoint URL** for the `web` function, e.g.
`https://<your-workspace>--badminton-ai-web.modal.run`. **Copy it.**

## 4. Give Supabase the two secrets (so the app calls Modal)
Supabase → **Edge Functions → Secrets → Add new secret**, add both:

| Key | Value |
|---|---|
| `MODAL_ANALYZE_URL` | the web endpoint URL from step 3 |
| `ANALYZE_SHARED_SECRET` | the **same** random string from step 2 |

That's it — no redeploy needed. The `analyze-video` function picks them up on its next call.

## 5. Test
In the app: open a tagged video → **Run analysis**. It now dispatches to Modal (status shows
*Analysing…*, the page polls), and when the worker finishes you get a **real** report (no "Sample data"
badge). First run is slower (Modal cold-start + model download); later runs are quick.

If a run fails, the video shows **Failed** with a short reason; check the Modal logs:
```bash
modal app logs badminton-ai
```

---

## What the worker does (so you know what you're paying for)
`modal/analyze.py` (GPU **L4**, ~pennies/match): downloads the video from R2 → samples ~6 fps →
RTMDet+RTMPose (pose) → ByteTrack (tracking) → per-player movement/pose **metrics** (coverage,
recovery, split-step, landing safety, lunge load, rear-court reach) → assigns tracks to your tagged
players by court side (honouring end-swaps) → writes `player_metrics` → `finalize_analysis()` builds
the coach/physio/player reports and marks the video **done**.

**Honesty note:** these are camera-geometry heuristics (no full court homography yet), so metric
confidence is modest and shown as *(estimate)* in the UI. Shuttle speed and stroke classification
(TrackNetV3 + a stroke model) are deliberately **not** faked — they're the next refinement pass.
Expect to tune thresholds in `analysis_rubric` against real footage.

## Licensing
All worker dependencies are permissive (Apache-2.0 / MIT): rtmlib, onnxruntime, supervision, opencv,
numpy, boto3. No AGPL (YOLOv8) on the server, per the whitepaper.
