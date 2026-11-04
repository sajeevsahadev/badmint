"""
Badminton 360 — Phase B GPU analysis worker (Modal).

Pipeline (open-source, Apache/MIT only):
  R2 download -> sample up to ~600 frames across the whole video -> person pose
  (rtmlib Body = RTMDet + RTMPose, 17 keypoints, onnxruntime) -> assign each detected
  person to a court quadrant (near/far, +left/right for doubles) -> accumulate movement &
  pose metrics per quadrant -> map quadrants to the user's tags by court side (honouring
  end-swap events) -> write player_metrics -> finalize_analysis() builds the 3-lens reports.

Why quadrants, not a tracker: players are tagged BY COURT SIDE, so assigning detections to
court regions is deterministic, robust, and needs no fragile re-ID. Identity precision within
a side (doubles front/back) and shuttle speed come in a later pass.

Honesty: metrics are camera-geometry heuristics (no full court homography yet) — confidence is
modest and surfaced as "(estimate)" in the UI.

Deploy:  modal deploy modal/analyze.py
Secrets (Modal secret "badminton-ai"): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, R2_ACCOUNT_ID,
  R2_VIDEO_ACCESS_KEY_ID, R2_VIDEO_SECRET_ACCESS_KEY, R2_VIDEO_BUCKET, ANALYZE_SHARED_SECRET.
"""
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
        "fastapi==0.115.0",
    )
)

app = modal.App("badminton-ai")
secret = modal.Secret.from_name("badminton-ai")

MAX_FRAMES = 600  # upper bound on frames analysed, so runtime is bounded for any video length

# COCO-17 keypoint indices.
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 11, 12, 13, 14, 15, 16


def _flip_side(side: str) -> str:
    swap = {"near": "far", "far": "near", "left": "right", "right": "left"}
    return "_".join(swap.get(tok, tok) for tok in (side or "").split("_"))


def _side_at(base_side: str, events, t: float) -> str:
    n = sum(1 for e in events if float(e.get("at_s", 0)) <= t)
    return _flip_side(base_side) if n % 2 == 1 else base_side


def _clamp(v, lo=0.0, hi=100.0):
    return max(lo, min(hi, float(v)))


@app.function(image=image, gpu="L4", timeout=1200, secrets=[secret])
def analyze(video_id: str):
    import cv2
    import numpy as np
    import boto3
    from botocore.config import Config
    from rtmlib import Body
    from supabase import create_client

    sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])

    def fail(msg: str):
        try:
            sb.rpc("fail_analysis", {"p_video_id": video_id, "p_error": str(msg)[:480]}).execute()
        except Exception:
            pass
        return {"ok": False, "error": str(msg)}

    try:
        vid = sb.table("match_videos").select("storage_path, game_type").eq("id", video_id).single().execute().data
        tags = sb.table("video_player_tags").select("id, court_side").eq("video_id", video_id).execute().data
        events = sb.table("video_court_events").select("at_s").eq("video_id", video_id).order("at_s").execute().data
        if not vid or not vid.get("storage_path"):
            return fail("video or storage_path missing")
        if not tags:
            return fail("no player tags — tag the video before analysing")
        game = vid.get("game_type") or "singles"

        # Download the video from R2 (video-only token).
        s3 = boto3.client(
            "s3",
            endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
            aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
            aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
            config=Config(signature_version="s3v4", region_name="auto"),
        )
        local = os.path.join(tempfile.gettempdir(), f"{video_id}.mp4")
        s3.download_file(os.environ["R2_VIDEO_BUCKET"], vid["storage_path"], local)

        cap = cv2.VideoCapture(local)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        w = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1280
        h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 720

        # Sample ~5 fps, but never more than MAX_FRAMES frames across the whole video.
        step = max(1, int(round(fps / 5.0)))
        if total:
            step = max(step, total // MAX_FRAMES)

        model = Body(mode="balanced", backend="onnxruntime", device="cuda")

        # Accumulate per court quadrant.
        quad = {}
        idx = -1
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            idx += 1
            if idx % step != 0:
                continue
            t = idx / fps
            kpts, scores = model(frame)
            if kpts is None or len(kpts) == 0:
                continue
            for person_k, person_s in zip(kpts, scores):
                if (person_s > 0.3).sum() < 6:
                    continue
                foot = _foot_point(person_k, person_s)
                if foot is None:
                    continue
                nx, ny = foot[0] / w, foot[1] / h
                ud = "near" if ny > 0.5 else "far"                      # bottom of frame = near
                key = ud if game == "singles" else f"{ud}_{'left' if nx < 0.5 else 'right'}"
                s = quad.setdefault(key, dict(ts=[], x=[], y=[], knee=[], lunge=[], hops=0, prev_y=None))
                s["ts"].append(t); s["x"].append(nx); s["y"].append(ny)
                s["knee"].append(_knee_angle(person_k, person_s))
                s["lunge"].append(_lunge_depth(person_k, person_s, w))
                if s["prev_y"] is not None and foot[1] < s["prev_y"] - 0.01 * h:
                    s["hops"] += 1
                s["prev_y"] = foot[1]
        cap.release()

        if not quad:
            return fail("no players detected — check camera angle / lighting")

        duration = (total / fps) if total else (max((max(s["ts"]) for s in quad.values()), default=0))
        mid_t = duration / 2

        wrote = 0
        for tag in tags:
            tside = _side_at(tag.get("court_side") or "", events, mid_t)
            s = quad.get(tside)
            if not s or len(s["ts"]) < 3:
                continue
            m = _metrics_for(s, np)
            sb.table("player_metrics").upsert(
                {"video_id": video_id, "tag_id": tag["id"],
                 "metrics": m["metrics"], "confidence": m["confidence"], "is_mock": False},
                on_conflict="video_id,tag_id",
            ).execute()
            wrote += 1

        if wrote == 0:
            return fail("could not map detected players to the tagged court positions")

        sb.table("match_videos").update({"duration_s": int(duration)}).eq("id", video_id).execute()
        sb.rpc("finalize_analysis", {"p_video_id": video_id}).execute()
        _notify_done(video_id)
        return {"ok": True, "players": wrote}
    except Exception as e:  # noqa
        return fail(f"{type(e).__name__}: {e}")


def _notify_done(video_id: str):
    """Best-effort Web Push to the uploader that the report is ready. Never fails the analysis."""
    try:
        import json as _json
        import urllib.request
        req = urllib.request.Request(
            f"{os.environ['SUPABASE_URL']}/functions/v1/notify-analysis",
            data=_json.dumps({"video_id": video_id, "secret": os.environ.get("ANALYZE_SHARED_SECRET", "")}).encode(),
            headers={
                "content-type": "application/json",
                "x-analyze-secret": os.environ.get("ANALYZE_SHARED_SECRET", ""),
                "Authorization": f"Bearer {os.environ['SUPABASE_SERVICE_ROLE_KEY']}",
            },
            method="POST",
        )
        urllib.request.urlopen(req, timeout=15).read()
    except Exception:
        pass


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
    import numpy as np
    vals = []
    for hip, knee, ank in ((L_HIP, L_KNEE, L_ANK), (R_HIP, R_KNEE, R_ANK)):
        if min(bs[hip], bs[knee], bs[ank]) > 0.3:
            vals.append(_angle(np.array(body[hip]), np.array(body[knee]), np.array(body[ank])))
    return min(vals) if vals else None


def _lunge_depth(body, bs, w):
    if min(bs[L_ANK], bs[R_ANK]) < 0.3:
        return None
    return float(abs(body[L_ANK][0] - body[R_ANK][0]) / (w * 0.25))


def _metrics_for(s, np):
    xs, ys = np.array(s["x"]), np.array(s["y"])
    dur = max(1e-3, s["ts"][-1] - s["ts"][0])
    coverage = _clamp((xs.std() + ys.std()) * 180)
    base = np.array([np.median(xs), np.median(ys)])
    dist = np.sqrt((xs - base[0]) ** 2 + (ys - base[1]) ** 2)
    away = dist > (dist.mean() + 0.3 * dist.std()) if len(dist) else np.array([False])
    recovery = _clamp(0.6 + float(away.mean()) * 2.0, 0.6, 3.0)
    split = _clamp((s["hops"] / dur) * 60)
    knees = [k for k in s["knee"] if k is not None]
    landing = _clamp(((float(np.mean(knees)) - 90) / 80) * 65 + 30) if knees else 60.0
    lunges = [l for l in s["lunge"] if l is not None]
    deep = [l for l in lunges if l > 0.8]
    lunge_risk = _clamp(float(np.mean(deep)) * 60) if deep else 30.0
    backcourt = _clamp(float(np.mean(ys < 0.35)) * 100)

    metrics = {
        "coverage_pct": round(coverage, 1),
        "recovery_s": round(recovery, 2),
        "split_step_pct": round(split, 1),
        "landing_score": round(landing, 1),
        "lunge_depth_risk": round(lunge_risk, 1),
        "backcourt_overreach": round(backcourt, 1),
    }
    confidence = {
        "coverage_pct": 0.55, "recovery_s": 0.45, "split_step_pct": 0.4,
        "landing_score": 0.4, "lunge_depth_risk": 0.35, "backcourt_overreach": 0.35,
        "_note": "camera-geometry heuristic — no court homography yet",
    }
    return {"metrics": metrics, "confidence": confidence}


@app.function(image=image, secrets=[secret])
@modal.fastapi_endpoint(method="POST")
def web(data: dict):
    """HTTP entrypoint called by the Supabase analyze-video function. Verifies the shared secret,
    then spawns the GPU job and returns immediately (so the request never blocks for minutes)."""
    from fastapi import Response

    expected = os.environ.get("ANALYZE_SHARED_SECRET", "")
    if expected and data.get("secret") != expected:
        return Response(status_code=403, content="forbidden")
    video_id = data.get("video_id")
    if not video_id:
        return Response(status_code=400, content="missing video_id")
    analyze.spawn(video_id)
    return {"status": "queued", "video_id": video_id}
