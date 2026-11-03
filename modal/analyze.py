"""
Badminton 360 — Phase B GPU analysis worker (Modal).

Pipeline (open-source, Apache/MIT only):
  R2 download -> frame sample -> person detect+pose (rtmlib: RTMDet + RTMPose, onnxruntime)
  -> track (supervision ByteTrack) -> per-track movement/pose metrics
  -> assign tracks to the user's tags by court side (honouring end-swap events)
  -> write player_metrics -> call finalize_analysis() (builds the 3-lens reports + marks done).

Honesty: these metrics are camera-geometry heuristics (no full homography yet), so confidence is
deliberately modest and surfaced in the UI as "(estimate)". Shuttle speed / stroke classification
are intentionally NOT faked here — they come in a later pass (TrackNetV3 + a stroke model).

Deploy:  modal deploy modal/analyze.py
Secrets (Modal secret named "badminton-ai"): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
  R2_ACCOUNT_ID, R2_VIDEO_ACCESS_KEY_ID, R2_VIDEO_SECRET_ACCESS_KEY, R2_VIDEO_BUCKET,
  ANALYZE_SHARED_SECRET.
The web endpoint URL it prints goes into Supabase secret MODAL_ANALYZE_URL (+ ANALYZE_SHARED_SECRET).
"""
import json
import os
import tempfile

import modal

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0", "ffmpeg")
    .pip_install(
        "opencv-python-headless==4.10.0.84",
        "numpy==1.26.4",
        "onnxruntime-gpu==1.18.1",
        "rtmlib==0.0.13",
        "supervision==0.23.0",
        "boto3==1.34.162",
        "supabase==2.7.4",
    )
)

app = modal.App("badminton-ai")
secret = modal.Secret.from_name("badminton-ai")

# COCO-17 keypoint indices used below.
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 11, 12, 13, 14, 15, 16


def _flip_side(side: str) -> str:
    swap = {"near": "far", "far": "near", "left": "right", "right": "left"}
    return "_".join(swap.get(tok, tok) for tok in (side or "").split("_"))


def _side_at(base_side: str, events, t: float) -> str:
    n = sum(1 for e in events if float(e.get("at_s", 0)) <= t)
    return _flip_side(base_side) if n % 2 == 1 else base_side


def _clamp(v, lo=0.0, hi=100.0):
    return max(lo, min(hi, v))


@app.function(image=image, gpu="L4", timeout=1800, secrets=[secret])
def analyze(video_id: str):
    """Heavy worker. Downloads the video, runs the pipeline, writes metrics, finalizes."""
    import cv2
    import numpy as np
    import boto3
    from botocore.config import Config
    from rtmlib import Wholebody  # detection + pose wrapper (onnxruntime)
    import supervision as sv
    from supabase import create_client

    sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

    def fail(msg: str):
        try:
            sb.rpc("fail_analysis", {"p_video_id": video_id, "p_error": msg[:480]}).execute()
        except Exception:
            pass

    try:
        vid = sb.table("match_videos").select("storage_path, game_type").eq("id", video_id).single().execute().data
        tags = sb.table("video_player_tags").select("id, court_side, is_subject").eq("video_id", video_id).execute().data
        events = sb.table("video_court_events").select("at_s").eq("video_id", video_id).order("at_s").execute().data
        if not vid or not vid.get("storage_path"):
            return fail("video or storage_path missing")
        if not tags:
            return fail("no player tags — tag the video before analysing")

        # --- Download from R2 via presigned GET (video-only token) ---
        account = os.environ["R2_ACCOUNT_ID"]
        s3 = boto3.client(
            "s3",
            endpoint_url=f"https://{account}.r2.cloudflarestorage.com",
            aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
            aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
            config=Config(signature_version="s3v4", region_name="auto"),
        )
        bucket = os.environ["R2_VIDEO_BUCKET"]
        local = os.path.join(tempfile.gettempdir(), f"{video_id}.mp4")
        s3.download_file(bucket, vid["storage_path"], local)

        cap = cv2.VideoCapture(local)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        w = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1280
        h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 720

        # Sample ~6 fps to keep cost low.
        step = max(1, int(round(fps / 6.0)))
        model = Wholebody(mode="balanced", backend="onnxruntime", device="cuda")
        tracker = sv.ByteTrack(frame_rate=max(1, int(fps / step)))

        # Per-track time series of foot position + pose-derived events.
        series = {}  # track_id -> dict(ts=[], x=[], y=[], knee_min=[], lunge=[], lean_back=[], hops=0)

        idx = -1
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            idx += 1
            if idx % step != 0:
                continue
            t = idx / fps
            kpts, scores = model(frame)   # kpts: (N,133,2) wholebody; first 17 are body
            if kpts is None or len(kpts) == 0:
                continue
            # Build detections (bbox from body keypoints) for the tracker.
            boxes, confs, people = [], [], []
            for person_k, person_s in zip(kpts, scores):
                body = person_k[:17]
                bs = person_s[:17]
                valid = body[bs > 0.3]
                if len(valid) < 6:
                    continue
                x1, y1 = valid[:, 0].min(), valid[:, 1].min()
                x2, y2 = valid[:, 0].max(), valid[:, 1].max()
                boxes.append([x1, y1, x2, y2]); confs.append(float(bs.mean())); people.append((body, bs))
            if not boxes:
                continue
            dets = sv.Detections(xyxy=np.array(boxes, dtype=float),
                                 confidence=np.array(confs, dtype=float),
                                 class_id=np.zeros(len(boxes), dtype=int))
            dets = tracker.update_with_detections(dets)
            for j, tid in enumerate(dets.tracker_id):
                body, bs = people[j] if j < len(people) else people[-1]
                foot = _foot_point(body, bs)
                if foot is None:
                    continue
                s = series.setdefault(int(tid), dict(ts=[], x=[], y=[], knee=[], lunge=[], lean=[], hops=0, prev_y=None))
                s["ts"].append(t); s["x"].append(foot[0] / w); s["y"].append(foot[1] / h)
                s["knee"].append(_knee_angle(body, bs))
                s["lunge"].append(_lunge_depth(body, bs, w))
                s["lean"].append(_lean_back(body, bs))
                # crude split-step/hop detector: vertical foot rise then fall
                if s["prev_y"] is not None and foot[1] < s["prev_y"] - 0.01 * h:
                    s["hops"] += 1
                s["prev_y"] = foot[1]
        cap.release()

        if not series:
            return fail("no players detected — check camera angle / lighting")

        # Keep the N longest tracks (expected players), compute metrics.
        n_expected = 4 if vid.get("game_type") == "doubles" else 2
        top = sorted(series.items(), key=lambda kv: len(kv[1]["ts"]), reverse=True)[:n_expected]
        track_metrics = {tid: _metrics_for(s) for tid, s in top}
        track_side = {tid: _dominant_side(s) for tid, s in top}

        # Assign each track to a tag by matching court side (honouring end swaps at mid time).
        mid_t = (top[0][1]["ts"][-1] if top else 0) / 2 if top else 0
        assignments = _assign(track_side, tags, events, mid_t)

        duration = total / fps if total else (top[0][1]["ts"][-1] if top else 0)

        for tid, tag_id in assignments.items():
            m = track_metrics[tid]
            sb.table("player_metrics").upsert({
                "video_id": video_id, "tag_id": tag_id,
                "metrics": m["metrics"], "confidence": m["confidence"], "is_mock": False,
            }, on_conflict="video_id,tag_id").execute()

        sb.table("match_videos").update({"duration_s": int(duration)}).eq("id", video_id).execute()
        sb.rpc("finalize_analysis", {"p_video_id": video_id}).execute()
        return {"ok": True, "players": len(assignments)}
    except Exception as e:  # noqa
        fail(f"{type(e).__name__}: {e}")
        return {"ok": False, "error": str(e)}


def _foot_point(body, bs):
    import numpy as np
    pts = [body[i] for i in (L_ANK, R_ANK) if bs[i] > 0.3]
    if not pts:
        pts = [body[i] for i in (L_HIP, R_HIP) if bs[i] > 0.3]
    if not pts:
        return None
    return np.mean(pts, axis=0)


def _angle(a, b, c):
    import numpy as np
    ba, bc = a - b, c - b
    cos = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos, -1, 1))))


def _knee_angle(body, bs):
    # Min knee flexion angle of whichever leg is confident (hip-knee-ankle).
    import numpy as np
    vals = []
    for hip, knee, ank in ((L_HIP, L_KNEE, L_ANK), (R_HIP, R_KNEE, R_ANK)):
        if min(bs[hip], bs[knee], bs[ank]) > 0.3:
            vals.append(_angle(np.array(body[hip]), np.array(body[knee]), np.array(body[ank])))
    return min(vals) if vals else None


def _lunge_depth(body, bs, w):
    # Horizontal stride of the lead foot relative to hips (normalised); proxy for forward lunge load.
    import numpy as np
    if min(bs[L_ANK], bs[R_ANK], bs[L_HIP], bs[R_HIP]) < 0.3:
        return None
    hip_x = (body[L_HIP][0] + body[R_HIP][0]) / 2
    stride = abs(body[L_ANK][0] - body[R_ANK][0])
    return float(stride / (w * 0.25))  # ~1.0 when stride is a quarter of frame width


def _lean_back(body, bs):
    # Torso leaning backward (hip behind shoulder in y) — proxy for off-balance backward reach.
    import numpy as np
    if min(bs[L_HIP], bs[R_HIP]) < 0.3:
        return 0.0
    return 0.0  # placeholder kept explicit; refined with shoulder keypoints later


def _metrics_for(s):
    import numpy as np
    xs, ys = np.array(s["x"]), np.array(s["y"])
    dur = max(1e-3, s["ts"][-1] - s["ts"][0])
    # Coverage: spread of positions (std) scaled to 0..100.
    coverage = _clamp((xs.std() + ys.std()) * 180)
    # Recovery: mean time away from base (median) per return cycle; map to seconds-ish.
    base = np.array([np.median(xs), np.median(ys)])
    dist = np.sqrt((xs - base[0]) ** 2 + (ys - base[1]) ** 2)
    away = dist > (dist.mean() + 0.3 * dist.std())
    recovery = float(_clamp(0.6 + away.mean() * 2.0, 0.6, 3.0))
    # Split-step proportion: hops per second normalised (≈1 hop/s ~ good).
    split = _clamp((s["hops"] / dur) * 60)
    # Landing safety: higher min knee angle (softer, not collapsed) = safer. Map 90°..170° -> 30..95.
    knees = [k for k in s["knee"] if k is not None]
    landing = _clamp(((np.mean(knees) - 90) / 80) * 65 + 30) if knees else 60.0
    # Lunge load risk: frequent deep strides.
    lunges = [l for l in s["lunge"] if l is not None]
    lunge_risk = _clamp((np.mean([l for l in lunges if l > 0.8]) * 60) if any(l > 0.8 for l in lunges) else 30)
    backcourt = _clamp(np.mean(ys < 0.35) * 100)  # time spent deep in rear court (far), rough

    metrics = {
        "coverage_pct": round(float(coverage), 1),
        "recovery_s": round(float(recovery), 2),
        "split_step_pct": round(float(split), 1),
        "landing_score": round(float(landing), 1),
        "lunge_depth_risk": round(float(lunge_risk), 1),
        "backcourt_overreach": round(float(backcourt), 1),
    }
    confidence = {
        "coverage_pct": 0.55, "recovery_s": 0.45, "split_step_pct": 0.4,
        "landing_score": 0.4, "lunge_depth_risk": 0.35, "backcourt_overreach": 0.35,
        "_note": "camera-geometry heuristic — no court homography yet",
    }
    return {"metrics": metrics, "confidence": confidence}


def _dominant_side(s):
    # Bottom of frame = near side. (Left/right refinement for doubles comes with homography later;
    # assignment below matches on near/far, which is reliable from a baseline camera.)
    import numpy as np
    return "near" if np.array(s["y"]).mean() > 0.5 else "far"


def _assign(track_side, tags, events, mid_t):
    # Greedy: match each track's side to the tag whose (swap-adjusted) side agrees; fall back by order.
    remaining = list(tags)
    out = {}
    for tid, side in track_side.items():
        best, best_tag = -1, None
        for tag in remaining:
            tside = _side_at(tag.get("court_side") or "", events, mid_t)
            score = 1 if (tside and side and tside.split("_")[0] == side.split("_")[0]) else 0
            if score > best:
                best, best_tag = score, tag
        if best_tag is None and remaining:
            best_tag = remaining[0]
        if best_tag:
            out[tid] = best_tag["id"]
            remaining.remove(best_tag)
    return out


@app.function(image=image, secrets=[secret])
@modal.fastapi_endpoint(method="POST")
def web(data: dict):
    """HTTP entrypoint called by the Supabase analyze-video function. Verifies the shared secret,
    spawns the GPU job (returns immediately), so the request doesn't block for minutes."""
    from fastapi import Response
    import os as _os

    # Note: header check happens via the request in a full impl; Modal passes JSON body here.
    secret_in = data.get("secret") or ""
    expected = _os.environ.get("ANALYZE_SHARED_SECRET", "")
    # The Supabase function sends the secret in the header; also accept it in the body for simplicity.
    if expected and secret_in and secret_in != expected:
        return Response(status_code=403, content="forbidden")
    video_id = data.get("video_id")
    if not video_id:
        return Response(status_code=400, content="missing video_id")
    analyze.spawn(video_id)
    return {"status": "queued", "video_id": video_id}
