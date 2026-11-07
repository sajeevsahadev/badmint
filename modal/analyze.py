"""
Badminton 360 — Phase B GPU analysis worker (Modal).

Pipeline (open-source, Apache/MIT only):
  R2 download -> sample up to ~600 frames across the whole video -> person pose
  (rtmlib Body = RTMDet + RTMPose, 17 keypoints, onnxruntime) -> assign each detected
  person to a court quadrant (near/far, +left/right for doubles) -> accumulate movement &
  pose metrics per quadrant -> map quadrants to the user's tags by court side (honouring
  end-swap events) -> write player_metrics -> finalize_analysis() builds the 3-lens reports.

Supabase is reached over PostgREST (not the supabase-py client) so the new `sb_secret_` API-key
format works; the key authenticates as service_role and bypasses RLS.

Honesty: metrics are camera-geometry heuristics (no full court homography yet) — confidence is
modest and surfaced as "(estimate)" in the UI.

Deploy:  modal deploy modal/analyze.py
Secrets (Modal secret "badminton-ai"): SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, R2_ACCOUNT_ID,
  R2_VIDEO_ACCESS_KEY_ID, R2_VIDEO_SECRET_ACCESS_KEY, R2_VIDEO_BUCKET, ANALYZE_SHARED_SECRET.
"""
import json
import os
import tempfile
import urllib.request

import modal

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0", "ffmpeg")
    .pip_install(
        "opencv-python-headless==4.10.0.84",
        "numpy==1.26.4",
        "onnxruntime==1.18.1",
        "rtmlib==0.0.13",
        "supervision==0.23.0",
        "boto3==1.34.162",
        "supabase==2.7.4",
        "fastapi==0.115.0",
        "tqdm==4.66.5",
    )
)

app = modal.App("badminton-ai")
secret = modal.Secret.from_name("badminton-ai")

MAX_FRAMES = 600
L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANK, R_ANK = 11, 12, 13, 14, 15, 16


def _flip_side(side: str) -> str:
    swap = {"near": "far", "far": "near", "left": "right", "right": "left"}
    return "_".join(swap.get(tok, tok) for tok in (side or "").split("_"))


def _side_at(base_side: str, events, t: float) -> str:
    n = sum(1 for e in events if float(e.get("at_s", 0)) <= t)
    return _flip_side(base_side) if n % 2 == 1 else base_side


def _clamp(v, lo=0.0, hi=100.0):
    return max(lo, min(hi, float(v)))


def _supa(method, path, key, url, body=None, prefer=None):
    h = {"apikey": key, "Authorization": f"Bearer {key}", "content-type": "application/json"}
    if prefer:
        h["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{url}/rest/v1/{path}", data=data, headers=h, method=method)
    with urllib.request.urlopen(req, timeout=120) as r:
        txt = r.read().decode()
        return json.loads(txt) if txt.strip() else None


@app.function(image=image, timeout=1200, cpu=2.0, memory=4096, secrets=[secret])
def analyze(video_id: str):
    URL = os.environ["SUPABASE_URL"]
    KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    def rest(method, path, body=None, prefer=None):
        return _supa(method, path, KEY, URL, body, prefer)

    def fail(msg):
        try:
            rest("POST", "rpc/fail_analysis", {"p_video_id": video_id, "p_error": str(msg)[:480]})
        except Exception:
            pass
        return {"ok": False, "error": str(msg)}

    try:
        import cv2
        import numpy as np
        import boto3
        from botocore.config import Config
        from rtmlib import Body

        vrows = rest("GET", f"match_videos?id=eq.{video_id}&select=storage_path,game_type")
        vid = vrows[0] if vrows else None
        tags = rest("GET", f"video_player_tags?video_id=eq.{video_id}&select=id,court_side") or []
        events = rest("GET", f"video_court_events?video_id=eq.{video_id}&select=at_s&order=at_s.asc") or []
        if not vid or not vid.get("storage_path"):
            return fail("video or storage_path missing")
        if not tags:
            return fail("no player tags — tag the video before analysing")
        game = vid.get("game_type") or "singles"

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

        step = max(1, int(round(fps / 5.0)))
        if total:
            step = max(step, total // MAX_FRAMES)

        model = Body(mode="balanced", backend="onnxruntime", device="cpu")

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
                ud = "near" if ny > 0.5 else "far"
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

        duration = (total / fps) if total else max((max(s["ts"]) for s in quad.values()), default=0)
        mid_t = duration / 2

        rows = []
        for tag in tags:
            tside = _side_at(tag.get("court_side") or "", events, mid_t)
            s = quad.get(tside)
            if not s or len(s["ts"]) < 3:
                continue
            m = _metrics_for(s, np)
            rows.append({"video_id": video_id, "tag_id": tag["id"],
                         "metrics": m["metrics"], "confidence": m["confidence"], "is_mock": False})

        if not rows:
            return fail("could not map detected players to the tagged court positions")

        rest("POST", "player_metrics?on_conflict=video_id,tag_id", body=rows, prefer="resolution=merge-duplicates")
        rest("PATCH", f"match_videos?id=eq.{video_id}", body={"duration_s": int(duration)})
        rest("POST", "rpc/finalize_analysis", body={"p_video_id": video_id})
        _notify_done(video_id, URL, KEY)
        return {"ok": True, "players": len(rows)}
    except Exception as e:  # noqa
        return fail(f"{type(e).__name__}: {e}")


def _notify_done(video_id, url, key):
    """Best-effort Web Push to the uploader that the report is ready. Never fails the analysis."""
    try:
        req = urllib.request.Request(
            f"{url}/functions/v1/notify-analysis",
            data=json.dumps({"video_id": video_id, "secret": os.environ.get("ANALYZE_SHARED_SECRET", "")}).encode(),
            headers={
                "content-type": "application/json",
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "x-analyze-secret": os.environ.get("ANALYZE_SHARED_SECRET", ""),
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
    coverage = _clamp((float(np.ptp(xs)) + float(np.ptp(ys))) * 120)  # range of movement -> 0..100
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
        "coverage_pct": round(coverage, 1), "recovery_s": round(recovery, 2),
        "split_step_pct": round(split, 1), "landing_score": round(landing, 1),
        "lunge_depth_risk": round(lunge_risk, 1), "backcourt_overreach": round(backcourt, 1),
    }
    confidence = {
        "coverage_pct": 0.55, "recovery_s": 0.45, "split_step_pct": 0.4,
        "landing_score": 0.4, "lunge_depth_risk": 0.35, "backcourt_overreach": 0.35,
        "_note": "camera-geometry heuristic — no court homography yet",
    }
    return {"metrics": metrics, "confidence": confidence}


def _post(url, payload, key):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"content-type": "application/json", "apikey": key,
                 "Authorization": f"Bearer {key}", "x-analyze-secret": payload.get("secret", "")},
        method="POST")
    urllib.request.urlopen(req, timeout=120).read()


def _detect_shots(frames, np, w, h, min_gap=0.5):
    """Detect shots as wrist-speed peaks; derive coarse type + technique flags at contact."""
    ts = [f[0] for f in frames]
    speeds = [0.0]
    for k in range(1, len(frames)):
        prev, cur = frames[k - 1], frames[k]
        d = 0.0
        for i in (9, 10):  # wrists
            if prev[2][i] > 0.3 and cur[2][i] > 0.3:
                d = max(d, float(np.linalg.norm(cur[1][i] - prev[1][i])))
        dt = max(1e-3, ts[k] - ts[k - 1])
        speeds.append(d / dt / w)
    speeds = np.array(speeds)
    if len(speeds) < 3:
        return []
    thr = max(0.6, float(speeds.mean() + 1.2 * speeds.std()))
    base_x = float(np.median([fr[3] for fr in frames]))
    base_y = float(np.median([fr[4] for fr in frames]))
    shots, last_t = [], -10.0
    for k in range(1, len(speeds) - 1):
        if speeds[k] >= thr and speeds[k] >= speeds[k - 1] and speeds[k] >= speeds[k + 1] and (ts[k] - last_t) > min_gap:
            last_t = ts[k]
            f = frames[k]
            sc = f[2]
            sh_y = np.mean([f[1][i][1] for i in (5, 6) if sc[i] > 0.3]) if (sc[5] > 0.3 or sc[6] > 0.3) else None
            hip_y = np.mean([f[1][i][1] for i in (11, 12) if sc[i] > 0.3]) if (sc[11] > 0.3 or sc[12] > 0.3) else None
            wy = min([f[1][i][1] for i in (9, 10) if sc[i] > 0.3], default=None)
            el_y = min([f[1][i][1] for i in (7, 8) if sc[i] > 0.3], default=None)
            torso = abs(hip_y - sh_y) if (hip_y is not None and sh_y is not None) else 0.2 * h
            contact = (sh_y - wy) / (torso + 1e-3) if (sh_y is not None and wy is not None) else 0.0
            overhead, low = contact > 0.3, contact < -0.3
            elbow_up = (el_y is not None and sh_y is not None and el_y < sh_y)
            spd = float(speeds[k])
            typ = ("smash" if spd > thr * 1.6 else "clear") if overhead else ("net" if low else "drive")
            after = [fr for fr in frames if 0 < fr[0] - ts[k] <= 1.5]
            recovered = bool(after and min(float(np.hypot(fr[3] - base_x, fr[4] - base_y)) for fr in after) < 0.12)
            shots.append({
                "t": round(float(ts[k]), 1), "type": typ, "conf": 0.4 if overhead else 0.3,
                "tech": {"contact": "overhead" if overhead else ("low" if low else "mid"),
                         "elbow_up": bool(elbow_up), "recovered": recovered, "speed": round(spd, 2)},
            })
    return shots[:60]


@app.function(image=image, timeout=1800, cpu=2.0, memory=4096, secrets=[secret])
def analyze_deep(video_id: str):
    URL = os.environ["SUPABASE_URL"]
    KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]

    def rest(method, path, body=None, prefer=None):
        return _supa(method, path, KEY, URL, body, prefer)

    def fail(msg):
        try:
            rest("POST", "rpc/fail_deep", {"p_video_id": video_id, "p_error": str(msg)[:480]})
        except Exception:
            pass
        return {"ok": False, "error": str(msg)}

    try:
        import cv2
        import numpy as np
        import boto3
        from botocore.config import Config
        from rtmlib import Body

        vrows = rest("GET", f"match_videos?id=eq.{video_id}&select=storage_path,game_type")
        vid = vrows[0] if vrows else None
        tags = rest("GET", f"video_player_tags?video_id=eq.{video_id}&select=id,court_side") or []
        events = rest("GET", f"video_court_events?video_id=eq.{video_id}&select=at_s&order=at_s.asc") or []
        if not vid or not vid.get("storage_path"):
            return fail("video missing")
        if not tags:
            return fail("no player tags")
        game = vid.get("game_type") or "singles"

        s3 = boto3.client("s3", endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                          aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
                          aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
                          config=Config(signature_version="s3v4", region_name="auto"))
        local = os.path.join(tempfile.gettempdir(), f"{video_id}_deep.mp4")
        s3.download_file(os.environ["R2_VIDEO_BUCKET"], vid["storage_path"], local)

        cap = cv2.VideoCapture(local)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        w = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1280
        h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 720
        # Denser sampling than the simple pass (shots are fast), capped at 1800 frames.
        step = max(1, int(round(fps / 12.0)))
        if total:
            step = max(step, total // 1800)

        model = Body(mode="balanced", backend="onnxruntime", device="cpu")
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
            for pk, ps in zip(kpts, scores):
                if (ps > 0.3).sum() < 6:
                    continue
                foot = _foot_point(pk, ps)
                if foot is None:
                    continue
                nx, ny = foot[0] / w, foot[1] / h
                ud = "near" if ny > 0.5 else "far"
                key = ud if game == "singles" else f"{ud}_{'left' if nx < 0.5 else 'right'}"
                quad.setdefault(key, []).append((t, np.array(pk), np.array(ps), nx, ny))
        cap.release()

        if not quad:
            return fail("no players detected")
        duration = (total / fps) if total else max((q[-1][0] for q in quad.values()), default=0)
        mid_t = duration / 2

        rest("DELETE", f"analysis_shots?video_id=eq.{video_id}")
        shot_rows = []
        for tag in tags:
            tside = _side_at(tag.get("court_side") or "", events, mid_t)
            frames = quad.get(tside)
            if not frames or len(frames) < 5:
                continue
            for i, sh in enumerate(_detect_shots(frames, np, w, h)):
                shot_rows.append({"video_id": video_id, "tag_id": tag["id"], "idx": i, "t_s": sh["t"],
                                  "shot_type": sh["type"], "confidence": sh["conf"], "technique": sh["tech"],
                                  "is_mock": False})
        if not shot_rows:
            return fail("no shots detected — low resolution or the camera hides contact points")

        rest("POST", "analysis_shots", body=shot_rows)
        # Hand off to Gemini commentary (it writes analysis_commentary + finalize_deep + notify).
        _post(f"{URL}/functions/v1/generate-commentary",
              {"video_id": video_id, "secret": os.environ.get("ANALYZE_SHARED_SECRET", "")}, KEY)
        return {"ok": True, "shots": len(shot_rows)}
    except Exception as e:  # noqa
        return fail(f"{type(e).__name__}: {e}")


@app.function(image=image, secrets=[secret])
@modal.fastapi_endpoint(method="POST")
def web(data: dict):
    from fastapi import Response
    expected = os.environ.get("ANALYZE_SHARED_SECRET", "")
    if expected and data.get("secret") != expected:
        return Response(status_code=403, content="forbidden")
    video_id = data.get("video_id")
    if not video_id:
        return Response(status_code=400, content="missing video_id")
    if data.get("deep"):
        analyze_deep.spawn(video_id)
    else:
        analyze.spawn(video_id)
    return {"status": "queued", "video_id": video_id, "deep": bool(data.get("deep"))}
