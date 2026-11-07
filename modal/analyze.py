"""
Badminton 360 — AI analysis worker (Modal).

Three jobs, all writing to Supabase over PostgREST (works with the new sb_secret_ key):
  index_video   — quick pass: find the people, crop a photo of each, save tracks + thumbnails.
  analyze       — Simple analysis (movement / landing / lunge metrics per player) -> a VERSIONED run.
  analyze_deep  — Deep analysis (shot-by-shot) -> a VERSIONED run -> generate-commentary (Gemini).

Detection model (pose-v2), calibrated against a hand-labelled clip:
  * near vs far court decided by body-size clustering (2-means on bbox height) — NOT frame midline
    (with a low camera the far court sits below the midline);
  * one person per slot; identity followed by CONTINUITY per court side (doubles partners who swap
    left/right stay the same person); slots are named by STARTING position = what the user tagged;
  * wrist motion measured RELATIVE to the player's own shoulders, in torso-lengths/sec over a 0.2 s
    window, so handheld-camera pans and walking cancel out;
  * a stroke = wrist-speed peak >= SHOT_T with swing amplitude >= SHOT_A, kept only if an opponent
    stroke occurs 0.3–2.5 s before/after (drops warm-up gestures between rallies).
Honesty: stroke height (overhead / mid / low) and swing direction are reported; exact shot names,
placement, footwork recovery and shuttle speed are NOT claimed (need shuttle tracking — next phase).

Deploy:  python -m modal deploy modal/analyze.py
Secret "badminton-ai": SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, R2_ACCOUNT_ID, R2_VIDEO_ACCESS_KEY_ID,
  R2_VIDEO_SECRET_ACCESS_KEY, R2_VIDEO_BUCKET, ANALYZE_SHARED_SECRET.
"""
import json
import math
import os
import tempfile
import urllib.request

import modal

_PKGS = ["opencv-python-headless==4.10.0.84", "numpy==1.26.4", "rtmlib==0.0.13", "supervision==0.23.0",
         "boto3==1.34.162", "supabase==2.7.4", "fastapi==0.115.0", "tqdm==4.66.5"]

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0", "ffmpeg")
    .pip_install(*_PKGS, "onnxruntime==1.18.1")
)
# Deep analysis samples up to 15 fps -> GPU. onnxruntime-gpu 1.18 is built for CUDA 11.8 + cuDNN 8.
gpu_image = (
    modal.Image.from_registry("nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04", add_python="3.11")
    .apt_install("libgl1", "libglib2.0-0", "ffmpeg")
    .pip_install(*_PKGS, "onnxruntime-gpu==1.18.1")
)

app = modal.App("badminton-ai")
secret = modal.Secret.from_name("badminton-ai")

ENGINE = "pose-v2"
SHOT_T, SHOT_A, SHOT_GAP = 3.5, 0.6, 0.8       # torso-lengths/sec, torso-lengths, seconds
RALLY_LO, RALLY_HI = 0.3, 2.5                   # opponent stroke must fall in this window


# ---------------------------------------------------------------- small utils
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


def _post(url, payload, key):
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"content-type": "application/json", "apikey": key,
                 "Authorization": f"Bearer {key}", "x-analyze-secret": payload.get("secret", "")},
        method="POST")
    urllib.request.urlopen(req, timeout=140).read()


def _record(rest, feature, video_id, run_id, user_id, started, cpu_cores, mem_gib, gpu=None, extra=None):
    """Write one ai_usage row with the measured wall time (priced by the DB trigger). Never raises."""
    import time
    try:
        units = {"wall_s": round(time.time() - started, 2), "cpu_cores": cpu_cores, "mem_gib": mem_gib}
        if gpu:
            units["gpu"] = gpu
        units.update(extra or {})
        rest("POST", "ai_usage", [{"feature": feature, "provider": "modal", "video_id": video_id,
                                   "run_id": run_id, "user_id": user_id, "units": units}])
    except Exception:
        pass


def _ctx():
    URL, KEY = os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return URL, KEY, (lambda m, p, b=None, pr=None: _supa(m, p, KEY, URL, b, pr))


def _s3():
    import boto3
    from botocore.config import Config
    return boto3.client("s3", endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                        aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
                        aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
                        config=Config(signature_version="s3v4", region_name="auto"))


def _load_video(rest, video_id):
    rows = rest("GET", f"match_videos?id=eq.{video_id}&select=storage_path,game_type")
    vid = rows[0] if rows else None
    if not vid or not vid.get("storage_path"):
        raise RuntimeError("video missing")
    tags = rest("GET", f"video_player_tags?video_id=eq.{video_id}&select=id,court_side,is_subject") or []
    events = rest("GET", f"video_court_events?video_id=eq.{video_id}&select=at_s&order=at_s.asc") or []
    ext = vid["storage_path"].rsplit(".", 1)[-1]
    local = os.path.join(tempfile.gettempdir(), f"{video_id}.{ext}")
    if not os.path.exists(local):
        _s3().download_file(os.environ["R2_VIDEO_BUCKET"], vid["storage_path"], local)
    return vid, tags, events, local


# ---------------------------------------------------------------- pose pass
def _people(kpts, scores):
    import numpy as np
    out = []
    if kpts is None or scores is None:
        return out
    for pk, ps in zip(kpts, scores):
        good = ps > 0.3
        if good.sum() < 6:
            continue
        pts = pk[good]
        x1, y1, x2, y2 = float(pts[:, 0].min()), float(pts[:, 1].min()), float(pts[:, 0].max()), float(pts[:, 1].max())
        feet = [pk[i] for i in (15, 16) if ps[i] > 0.3] or [pk[i] for i in (11, 12) if ps[i] > 0.3]
        if not feet:
            continue
        fx, fy = (float(v) for v in np.mean(feet, axis=0))
        out.append({"k": np.array(pk), "s": np.array(ps), "bh": y2 - y1, "bbox": (x1, y1, x2, y2),
                    "fx": fx, "fy": fy, "conf": float(ps.mean())})
    return out


def _pose_pass(path, model, target_fps, max_frames, t_max=None, kf_every=1.0, kf_until=120.0):
    """Run pose on sampled frames. Also keeps 1-per-second JPEG keyframes (for photo crops)."""
    import cv2
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    W = cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1280
    H = cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 720
    step = max(1, int(round(fps / target_fps)))
    if total and max_frames:
        limit = min(total, int((t_max or 1e9) * fps))
        step = max(step, math.ceil(limit / max_frames))
    frames, keyframes, idx, next_kf = [], {}, -1, 0.0
    scale = min(1.0, 1280.0 / max(W, H))
    while True:
        if not cap.grab():
            break
        idx += 1
        if idx % step:
            continue
        t = idx / fps
        if t_max is not None and t > t_max:
            break
        ok, frame = cap.retrieve()
        if not ok:
            continue
        kpts, scores = model(frame)
        frames.append((t, _people(kpts, scores)))
        if t >= next_kf and t <= kf_until:
            next_kf = t + kf_every
            small = cv2.resize(frame, (int(W * scale), int(H * scale))) if scale < 1 else frame
            keyframes[round(t, 3)] = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 88])[1].tobytes()
    cap.release()
    duration = (total / fps) if total else (frames[-1][0] if frames else 0.0)
    return frames, keyframes, {"fps": fps, "W": W, "H": H, "duration": duration, "step": step, "scale": scale}


def _height_threshold(hs):
    import numpy as np
    if len(hs) < 4:
        return None
    x = np.log(np.array(hs))
    c1, c2 = np.percentile(x, 25), np.percentile(x, 75)
    for _ in range(25):
        a, b = x[np.abs(x - c1) <= np.abs(x - c2)], x[np.abs(x - c1) > np.abs(x - c2)]
        if len(a) == 0 or len(b) == 0:
            break
        c1, c2 = a.mean(), b.mean()
    if abs(c2 - c1) < math.log(1.35):
        return None                      # one size cluster -> everyone on one side of the net
    return float(math.exp((c1 + c2) / 2))


def _dist(prev, p):
    if prev is None:
        return 1e6
    return math.hypot(p["fx"] - prev["fx"], p["fy"] - prev["fy"]) / max(p["bh"], 1.0)


def _assign_slots(frames, game, events, W):
    """{slot: [(t, person), ...]}; slot = the player's STARTING position (what the user tagged)."""
    thr = _height_threshold([p["bh"] for _, ppl in frames for p in ppl])
    per = 2 if game == "doubles" else 1
    swaps = sorted(float(e.get("at_s", 0)) for e in events)
    slots, state, last_n = {}, {}, 0
    for t, ppl in frames:
        n = sum(1 for s in swaps if s <= t)
        if n != last_n:                  # ends changed: re-initialise identities
            state, last_n = {}, n
        for side in ("near", "far"):
            if thr is None:
                grp = ppl if side == "near" else []
            else:
                grp = [p for p in ppl if (p["bh"] >= thr) == (side == "near")]
            grp = sorted(grp, key=lambda p: -p["conf"])[:per]
            if not grp:
                continue
            if per == 1:
                key = _flip_side(side) if n % 2 else side
                slots.setdefault(key, []).append((t, grp[0]))
                continue
            st = state.setdefault(side, {})
            if len(grp) == 2 and not st:
                l, r = sorted(grp, key=lambda p: p["fx"])
                assign = [("A", l), ("B", r)]
            elif len(grp) == 2:
                a, b = grp
                same = _dist(st.get("A"), a) + _dist(st.get("B"), b)
                cross = _dist(st.get("A"), b) + _dist(st.get("B"), a)
                assign = [("A", a), ("B", b)] if same <= cross else [("A", b), ("B", a)]
            else:
                p = grp[0]
                if not st:
                    assign = [("A" if p["fx"] < W / 2 else "B", p)]
                else:
                    assign = [("A" if _dist(st.get("A"), p) <= _dist(st.get("B"), p) else "B", p)]
            for lbl, p in assign:
                st[lbl] = p
                base = f"{side}_{'left' if lbl == 'A' else 'right'}"
                slots.setdefault(_flip_side(base) if n % 2 else base, []).append((t, p))
    return slots


# ---------------------------------------------------------------- photo crops
def _inside(p, meta):
    x1, y1, x2, y2 = p["bbox"]
    return x1 > 4 and y1 > 4 and x2 < meta["W"] - 4 and y2 < meta["H"] - 4


def _overlap(a, b, pad=0.10):
    """Boxes touch (each widened by pad) -> a crop of one would show part of the other."""
    ax1, ay1, ax2, ay2 = a["bbox"]
    bx1, by1, bx2, by2 = b["bbox"]
    pa, pb = (ax2 - ax1) * pad, (bx2 - bx1) * pad
    return ax1 - pa < bx2 + pb and bx1 - pb < ax2 + pa and ay1 < by2 and by1 < ay2


def _is_fixture(p, frames, i, window=30.0, near=0.35, share=0.75):
    """A spectator / umpire / coach by the post keeps the same spot; a player leaves it once rallies start.
    True when p's foot position stays occupied in >= share of the frames over the next `window` seconds."""
    t0, seen, hit = frames[i][0], 0, 0
    for t, ppl in frames[i + 1:]:
        if t - t0 > window:
            break
        seen += 1
        if any(_dist(p, q) < near for q in ppl):
            hit += 1
    return seen >= 8 and hit / seen >= share


def _formation_frame(frames, keyframes, meta, events, game):
    """Earliest keyframe (normally the first serve) where EVERY player is visible at once, inside the frame,
    clear of everyone else and standing still. Photos all come from this one frame, with left/right read
    from it, so two slots can never get the same person (the per-slot tracker can briefly hand one
    player to both partner slots when the other is undetected)."""
    per = 2 if game == "doubles" else 1
    first_swap = min((float(e.get("at_s", 0)) for e in events), default=1e9)
    thr = _height_threshold([p["bh"] for _, ppl in frames for p in ppl])
    if thr is None:
        return None
    at = {round(t, 3): i for i, (t, _) in enumerate(frames)}
    for kt in sorted(keyframes):
        if kt >= first_swap:
            break
        i = at.get(kt)
        if i is None:
            continue
        everyone = frames[i][1]
        ppl = [p for p in everyone if p["conf"] > 0.45 and not _is_fixture(p, frames, i)]
        near = sorted([p for p in ppl if p["bh"] >= thr], key=lambda p: -p["conf"])[:per]
        far = sorted([p for p in ppl if p["bh"] < thr], key=lambda p: -p["conf"])[:per]
        if len(near) < per or len(far) < per:
            continue
        chosen = near + far
        if not all(_inside(p, meta) for p in chosen):
            continue
        if any(_overlap(a, b) for a in chosen for b in everyone if a is not b):
            continue
        if i + 1 < len(frames) and frames[i + 1][0] - kt < 1.5:
            nxt = frames[i + 1][1]
            if not nxt or any(min(_dist(c, q) for q in nxt) > 0.4 for c in chosen):
                continue                   # someone is moving -> not a set formation
        if per == 1:
            return kt, {"near": near[0], "far": far[0]}
        out = {}
        for side, grp in (("near", near), ("far", far)):
            l, r = sorted(grp, key=lambda p: p["fx"])
            out[f"{side}_left"], out[f"{side}_right"] = l, r
        return kt, out
    return None


def _crop_jpeg(keyframe, bbox, meta):
    import cv2
    import numpy as np
    img = cv2.imdecode(np.frombuffer(keyframe, np.uint8), cv2.IMREAD_COLOR)
    s = meta["scale"]
    x1, y1, x2, y2 = (v * s for v in bbox)
    pw, ph = (x2 - x1) * 0.18, (y2 - y1) * 0.08
    X1, Y1 = int(max(0, x1 - pw)), int(max(0, y1 - ph))
    X2, Y2 = int(min(img.shape[1], x2 + pw)), int(min(img.shape[0], y2 + ph))
    crop = img[Y1:Y2, X1:X2]
    if crop.size == 0:
        return None
    hh = 260
    crop = cv2.resize(crop, (max(1, int(crop.shape[1] * hh / crop.shape[0])), hh))
    return cv2.imencode(".jpg", crop, [cv2.IMWRITE_JPEG_QUALITY, 85])[1].tobytes()


def _crops(slots, keyframes, meta, events, frames=None, game=None):
    """Player photos -> {slot: JPEG}. Prefer one formation frame for everybody; otherwise fall back to
    each slot's clearest isolated view, never reusing the same box for two slots. No photo beats a wrong one."""
    out = {}
    form = _formation_frame(frames, keyframes, meta, events, game) if frames else None
    if form:
        kt, people = form
        for slot, p in people.items():
            if slot in slots:
                jpg = _crop_jpeg(keyframes[kt], p["bbox"], meta)
                if jpg:
                    out[slot] = jpg
        return out
    first_swap = min((float(e.get("at_s", 0)) for e in events), default=1e9)
    everyone_at = {round(t, 3): ppl for t, ppl in (frames or [])}
    used = []
    for slot, items in slots.items():
        best, best_score = None, -1.0
        for t, p in items:
            kt = round(t, 3)
            if t >= first_swap or kt not in keyframes:
                continue
            if any(_overlap(p, q) for q in everyone_at.get(kt, []) if q is not p):
                continue
            if any(u[0] == kt and u[1] == p["bbox"] for u in used):
                continue
            score = p["conf"] * (1.0 if _inside(p, meta) else 0.4) * p["bh"]
            if score > best_score:
                best, best_score = (kt, p["bbox"]), score
        if not best:
            continue
        used.append(best)
        jpg = _crop_jpeg(keyframes[best[0]], best[1], meta)
        if jpg:
            out[slot] = jpg
    return out


def _save_people(rest, video_id, storage_path, slots, crops):
    """Replace tracks with one per slot (+ photo) and attach photos to the matching tags."""
    club = storage_path.split("/")[0]
    s3 = _s3()
    rest("DELETE", f"video_person_tracks?video_id=eq.{video_id}")
    for slot, items in slots.items():
        thumb = None
        if slot in crops:
            thumb = f"{club}/thumbs/{video_id}/{slot}.jpg"
            s3.put_object(Bucket=os.environ["R2_VIDEO_BUCKET"], Key=thumb, Body=crops[slot], ContentType="image/jpeg")
        row = rest("POST", "video_person_tracks", [{
            "video_id": video_id, "track_label": slot, "court_side": slot, "thumb_path": thumb,
            "first_seen_s": round(items[0][0], 2), "last_seen_s": round(items[-1][0], 2),
            "confidence": round(sum(p["conf"] for _, p in items) / len(items), 2), "is_mock": False,
        }], "return=representation")
        tid = row[0]["id"] if row else None
        patch = {"track_id": tid}
        if thumb:
            patch["thumb_path"] = thumb
        rest("PATCH", f"video_player_tags?video_id=eq.{video_id}&court_side=eq.{slot}", patch)


# ---------------------------------------------------------------- motion + strokes
def _rel(p):
    import numpy as np
    k, s = p["k"], p["s"]
    if s[5] < 0.4 or s[6] < 0.4:
        return None
    sh = (k[5] + k[6]) / 2
    torso = float(np.linalg.norm((k[11] + k[12]) / 2 - sh)) if (s[11] > 0.4 and s[12] > 0.4) else p["bh"] * 0.3
    torso = max(torso, 1.0)
    return {i: (k[i] - sh) / torso for i in (9, 10) if s[i] > 0.5}, sh, torso


def _wseries(items, win=0.2):
    """Body-relative wrist speed (torso-lengths/sec) over a ~0.2 s window — fps independent."""
    import numpy as np
    out = [(t, p, _rel(p)) for t, p in items]
    sp = []
    for i, (t, p, r) in enumerate(out):
        j = i
        while j > 0 and t - out[j - 1][0] <= win + 0.02:
            j -= 1
        v = 0.0
        if j < i and r and out[j][2] and (t - out[j][0]) > 0.05:
            r0 = out[j][2]
            for w_ in (9, 10):
                if w_ in r[0] and w_ in r0[0]:
                    v = max(v, float(np.linalg.norm(r[0][w_] - r0[0][w_]) / (t - out[j][0])))
        sp.append(v)
    return out, np.array(sp)


def _strokes(items):
    """Candidate strokes for one slot: [(t, info)]."""
    import numpy as np
    out, sp = _wseries(items)
    res, last = [], -9.0
    for i in range(1, len(sp) - 1):
        if not (sp[i] >= SHOT_T and sp[i] >= sp[i - 1] and sp[i] >= sp[i + 1] and out[i][0] - last > SHOT_GAP):
            continue
        t = out[i][0]
        win = [o for o in out if abs(o[0] - t) <= 0.3 and o[2]]
        pos = [r[0][j] for _, _, r in win for j in r[0]]
        if len(pos) < 2:
            continue
        arr = np.array(pos)
        amp = float(np.ptp(arr[:, 1]) + np.ptp(arr[:, 0]))
        if amp < SHOT_A:
            continue
        last = t
        r = out[i][2]
        p = out[i][1]
        # fastest wrist at the peak -> stroke height relative to the shoulder (y grows downward)
        wy = min(r[0][j][1] for j in r[0]) if r and r[0] else 0.0
        contact = -float(wy)                      # >0 above shoulder, <0 below
        height = "overhead" if contact > 0.3 else ("low" if contact < -1.0 else "mid")
        k, s = p["k"], p["s"]
        elbow_up = bool(min((k[e][1] for e in (7, 8) if s[e] > 0.4), default=1e9) <
                        min((k[q][1] for q in (5, 6) if s[q] > 0.4), default=-1e9))
        before = [o for o in out if 0 < t - o[0] <= 0.2 and o[2]]
        after = [o for o in out if 0 < o[0] - t <= 0.2 and o[2]]
        swing = "flat"
        if before and after:
            yb = np.mean([min(v[1] for v in o[2][0].values()) for o in before if o[2][0]] or [0])
            ya = np.mean([min(v[1] for v in o[2][0].values()) for o in after if o[2][0]] or [0])
            swing = "downward" if ya - yb > 0.25 else ("upward" if yb - ya > 0.25 else "flat")
        res.append((t, {
            "type": height if height != "mid" else "drive",
            "conf": 0.45 if height == "overhead" else 0.35,
            "tech": {"height": height, "elbow_up": elbow_up, "swing": swing,
                     "pace": "fast" if sp[i] >= 2 * SHOT_T else "moderate"},
        }))
    return res


BASE_R, REC_WIN, LATE_S, LUNGE_DEG = 0.45, 2.0, 1.2, 135.0   # body-heights, s, s, knee angle


def _knee_deg(p):
    import numpy as np
    k, s = p["k"], p["s"]
    best = None
    for hip, knee, ank in ((11, 13, 15), (12, 14, 16)):
        if min(s[hip], s[knee], s[ank]) > 0.3:
            ba, bc = k[hip] - k[knee], k[ank] - k[knee]
            c = float(np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6))
            a = math.degrees(math.acos(max(-1, min(1, c))))
            best = a if best is None else min(best, a)
    return best


def _footwork(items, strokes, off):
    """Annotate each stroke with measured footwork facts (camera-compensated, in body-heights):
    how far from the player's usual base they played it, whether / how fast they got back to base
    before their next stroke, and how deep they bent the knee. Returns (strokes, motion summary)."""
    import numpy as np
    if not items:
        return strokes, {}
    bh = float(np.median([p["bh"] for _, p in items])) or 1.0
    ts = np.array([t for t, _ in items])
    xs = np.array([(p["fx"] - off.get(round(t, 3), (0, 0))[0]) / bh for t, p in items])
    ys = np.array([(p["fy"] - off.get(round(t, 3), (0, 0))[1]) / bh for t, p in items])
    step = np.hypot(np.diff(xs), np.diff(ys)) if len(xs) > 1 else np.array([])
    step = step[step < 0.6]                       # drop identity jumps / camera glitches
    times = [t for t, _ in strokes]
    out = []
    for n, (t, info) in enumerate(strokes):
        near = np.abs(ts - t) <= 15
        base = (float(np.median(xs[near])), float(np.median(ys[near])))
        dist = np.hypot(xs - base[0], ys - base[1])
        i0 = int(np.argmin(np.abs(ts - t)))
        d0 = float(dist[i0])
        t_next = times[n + 1] if n + 1 < len(times) else t + 2.5
        win = np.where((ts >= t + 0.25) & (ts <= min(t + REC_WIN, t_next)))[0]
        if d0 < BASE_R:
            rec, rec_s = True, 0.0
        else:
            back = [i for i in win if dist[i] < BASE_R]
            rec, rec_s = (True, round(float(ts[back[0]] - t), 2)) if back else (False, None)
        knees = [a for tt, p in items if abs(tt - t) <= 0.15 for a in [_knee_deg(p)] if a is not None]
        knee = round(min(knees), 1) if knees else None
        tech = dict(info["tech"])
        tech.update({"from_base": round(d0, 2), "off_base": d0 >= BASE_R, "recovered": rec,
                     "recovery_s": rec_s, "late_recovery": bool(rec and rec_s is not None and rec_s > LATE_S),
                     "knee_deg": knee, "lunge": bool(knee is not None and knee < LUNGE_DEG)})
        out.append((t, {**info, "tech": tech}))
    motion = {"distance_bh": round(float(step.sum()), 1), "tracked_s": round(float(ts[-1] - ts[0]), 1)}
    return out, motion


def _rally_filter(by_slot, events):
    flat = [(t, _side_at(slot, events, t).split("_")[0]) for slot, v in by_slot.items() for t, _ in v]
    keep = {}
    for slot, v in by_slot.items():
        keep[slot] = []
        for t, info in v:
            side = _side_at(slot, events, t).split("_")[0]
            if any(os_ != side and RALLY_LO <= abs(t - ot) <= RALLY_HI for ot, os_ in flat):
                keep[slot].append((t, info))
    return keep


# ---------------------------------------------------------------- simple metrics (camera-compensated)
def _camera_offsets(slots):
    """Estimate handheld-camera pan as the median frame-to-frame shift of everyone visible."""
    import numpy as np
    by_t = {}
    for slot, items in slots.items():
        for t, p in items:
            by_t.setdefault(round(t, 3), {})[slot] = (p["fx"], p["fy"], p["bh"])
    ts = sorted(by_t)
    cx = cy = 0.0
    off, prev = {}, None
    for t in ts:
        if prev is not None:
            common = [s for s in by_t[t] if s in by_t[prev]]
            if len(common) >= 2:
                dx = [by_t[t][s][0] - by_t[prev][s][0] for s in common]
                dy = [by_t[t][s][1] - by_t[prev][s][1] for s in common]
                cx += float(np.median(dx)); cy += float(np.median(dy))
        off[t] = (cx, cy)
        prev = t
    return off


def _metrics(items, off):
    import numpy as np
    bh = float(np.median([p["bh"] for _, p in items])) or 1.0
    xs = np.array([(p["fx"] - off.get(round(t, 3), (0, 0))[0]) / bh for t, p in items])
    ys = np.array([(p["fy"] - off.get(round(t, 3), (0, 0))[1]) / bh for t, p in items])
    ts = [t for t, _ in items]
    dur = max(1e-3, ts[-1] - ts[0])
    coverage = _clamp((float(np.ptp(xs)) + float(np.ptp(ys))) * 25)
    base = np.array([np.median(xs), np.median(ys)])
    dist = np.sqrt((xs - base[0]) ** 2 + (ys - base[1]) ** 2)
    away = dist > (dist.mean() + 0.3 * dist.std()) if len(dist) else np.array([False])
    recovery = _clamp(0.6 + float(away.mean()) * 2.0, 0.6, 3.0)
    hops = sum(1 for i in range(1, len(ys)) if ys[i] < ys[i - 1] - 0.04)
    split = _clamp((hops / dur) * 60)
    knees = []
    for _, p in items:
        k, s = p["k"], p["s"]
        for hip, knee, ank in ((11, 13, 15), (12, 14, 16)):
            if min(s[hip], s[knee], s[ank]) > 0.3:
                ba, bc = k[hip] - k[knee], k[ank] - k[knee]
                c = float(np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6))
                knees.append(math.degrees(math.acos(max(-1, min(1, c)))))
    landing = _clamp(((float(np.mean(knees)) - 90) / 80) * 65 + 30) if knees else 60.0
    spreads = [abs(p["k"][15][0] - p["k"][16][0]) / (0.5 * p["bh"]) for _, p in items
               if p["s"][15] > 0.3 and p["s"][16] > 0.3 and p["bh"] > 0]
    deep = [v for v in spreads if v > 0.8]
    lunge_risk = _clamp(float(np.mean(deep)) * 60) if deep else 30.0
    metrics = {"coverage_pct": round(coverage, 1), "recovery_s": round(recovery, 2),
               "split_step_pct": round(split, 1), "landing_score": round(landing, 1),
               "lunge_depth_risk": round(lunge_risk, 1)}
    confidence = {"coverage_pct": 0.45, "recovery_s": 0.4, "split_step_pct": 0.35, "landing_score": 0.45,
                  "lunge_depth_risk": 0.4, "_note": "pose estimate, camera-pan compensated; no court homography yet"}
    return {"metrics": metrics, "confidence": confidence}


# ---------------------------------------------------------------- jobs
def _body(device):
    from rtmlib import Body
    return Body(mode="balanced", backend="onnxruntime", device=device)


@app.function(image=image, timeout=900, cpu=2.0, memory=4096, secrets=[secret])
def index_video(video_id: str, user_id: str = None):
    import time
    URL, KEY, rest = _ctx()
    t0 = time.time()
    try:
        vid, tags, events, local = _load_video(rest, video_id)
        frames, kf, meta = _pose_pass(local, _body("cpu"), target_fps=3, max_frames=240, t_max=90, kf_until=90)
        slots = _assign_slots(frames, vid.get("game_type") or "singles", events, meta["W"])
        if not slots:
            raise RuntimeError("no players detected")
        _save_people(rest, video_id, vid["storage_path"], slots, _crops(slots, kf, meta, events, frames, vid.get("game_type") or "singles"))
        rest("PATCH", f"match_videos?id=eq.{video_id}", {"index_status": "done"})
        return {"ok": True, "slots": list(slots)}
    except Exception as e:  # noqa
        try:
            rest("PATCH", f"match_videos?id=eq.{video_id}", {"index_status": "failed"})
        except Exception:
            pass
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}
    finally:
        _record(rest, "index", video_id, None, user_id, t0, 2.0, 4.0)


@app.function(image=image, timeout=1200, cpu=2.0, memory=4096, secrets=[secret])
def analyze(video_id: str, run_id: str = None, user_id: str = None):
    import time
    URL, KEY, rest = _ctx()
    t0 = time.time()
    try:
        return _analyze(video_id, run_id, URL, KEY, rest)
    finally:
        _record(rest, "quick_report", video_id, run_id, user_id, t0, 2.0, 4.0)


def _analyze(video_id, run_id, URL, KEY, rest):

    def fail(msg):
        try:
            rest("POST", "rpc/fail_analysis", {"p_video_id": video_id, "p_error": str(msg)[:480], "p_run_id": run_id})
        except Exception:
            pass
        return {"ok": False, "error": str(msg)}

    try:
        vid, tags, events, local = _load_video(rest, video_id)
        if not tags:
            return fail("no player tags — tag the video before analysing")
        frames, kf, meta = _pose_pass(local, _body("cpu"), target_fps=5, max_frames=900)
        slots = _assign_slots(frames, vid.get("game_type") or "singles", events, meta["W"])
        if not slots:
            return fail("no players detected — check camera angle / lighting")
        _save_people(rest, video_id, vid["storage_path"], slots, _crops(slots, kf, meta, events, frames, vid.get("game_type") or "singles"))
        off = _camera_offsets(slots)
        rows = []
        for tag in tags:
            items = slots.get(tag.get("court_side") or "")
            if not items or len(items) < 5:
                continue
            m = _metrics(items, off)
            rows.append({"video_id": video_id, "tag_id": tag["id"], "run_id": run_id,
                         "metrics": m["metrics"], "confidence": m["confidence"], "is_mock": False})
        if not rows:
            return fail("could not match detected players to the tagged positions")
        rows = _retag(rest, video_id, tags, rows)
        if not rows:
            return fail("player tags were removed while the analysis was running — tag the players and try again")
        rest("POST", "player_metrics?on_conflict=run_id,tag_id", rows, "resolution=merge-duplicates")
        rest("PATCH", f"match_videos?id=eq.{video_id}", {"duration_s": int(meta["duration"])})
        rest("POST", "rpc/finalize_analysis", {"p_video_id": video_id, "p_run_id": run_id})
        _notify(video_id, URL, KEY)
        return {"ok": True, "players": len(rows)}
    except Exception as e:  # noqa
        return fail(f"{type(e).__name__}: {e}")


@app.function(image=gpu_image, gpu="L4", timeout=1800, memory=8192, secrets=[secret])
def analyze_deep(video_id: str, run_id: str = None, user_id: str = None):
    import time
    URL, KEY, rest = _ctx()
    t0 = time.time()
    try:
        return _analyze_deep(video_id, run_id, user_id, URL, KEY, rest)
    finally:
        _record(rest, "deep_coaching", video_id, run_id, user_id, t0, 0.125, 8.0, gpu="L4")


def _analyze_deep(video_id, run_id, user_id, URL, KEY, rest):

    def fail(msg):
        try:
            rest("POST", "rpc/fail_deep", {"p_video_id": video_id, "p_error": str(msg)[:480], "p_run_id": run_id})
        except Exception:
            pass
        return {"ok": False, "error": str(msg)}

    try:
        import onnxruntime as ort
        device = "cuda" if "CUDAExecutionProvider" in ort.get_available_providers() else "cpu"
        vid, tags, events, local = _load_video(rest, video_id)
        if not tags:
            return fail("no player tags")
        frames, kf, meta = _pose_pass(local, _body(device), target_fps=15, max_frames=4000)
        slots = _assign_slots(frames, vid.get("game_type") or "singles", events, meta["W"])
        if not slots:
            return fail("no players detected")
        _save_people(rest, video_id, vid["storage_path"], slots, _crops(slots, kf, meta, events, frames, vid.get("game_type") or "singles"))
        strokes = _rally_filter({s: _strokes(items) for s, items in slots.items()}, events)
        off = _camera_offsets(slots)
        tag_by_side = {t.get("court_side"): t["id"] for t in tags}
        shot_rows, motion_rows = [], []
        for slot, lst in strokes.items():
            tag_id = tag_by_side.get(slot)
            if not tag_id:
                continue
            lst, motion = _footwork(slots.get(slot) or [], lst, off)
            motion_rows.append({"video_id": video_id, "run_id": run_id, "tag_id": tag_id, "motion": motion})
            for i, (t, info) in enumerate(lst):
                shot_rows.append({"video_id": video_id, "run_id": run_id, "tag_id": tag_id, "idx": i,
                                  "t_s": round(t, 2), "shot_type": info["type"], "confidence": info["conf"],
                                  "technique": info["tech"], "meta": {"engine": ENGINE, "device": device},
                                  "is_mock": False})
        shot_rows = _retag(rest, video_id, tags, shot_rows)
        motion_rows = _retag(rest, video_id, tags, motion_rows)
        if shot_rows:
            rest("POST", "analysis_shots", shot_rows)
        if motion_rows and run_id:
            rest("POST", "analysis_player_summary", motion_rows)
        # Commentary step also handles the "no strokes" case and finalises the run.
        _post(f"{URL}/functions/v1/generate-commentary",
              {"video_id": video_id, "run_id": run_id, "user_id": user_id,
               "secret": os.environ.get("ANALYZE_SHARED_SECRET", "")}, KEY)
        return {"ok": True, "shots": len(shot_rows), "device": device, "frames": len(frames)}
    except Exception as e:  # noqa
        return fail(f"{type(e).__name__}: {e}")


def _retag(rest, video_id, tags, rows):
    """Tags can be re-saved (new ids) while a long analysis runs; writing the stale ids then fails the
    tag_id foreign key (PostgREST 409). Re-read the current tags and remap each row by court side."""
    side_of = {t["id"]: t.get("court_side") for t in tags}
    now = rest("GET", f"video_player_tags?video_id=eq.{video_id}&select=id,court_side") or []
    current = {t.get("court_side"): t["id"] for t in now}
    out = []
    for r in rows:
        new_id = current.get(side_of.get(r["tag_id"]))
        if new_id:
            out.append({**r, "tag_id": new_id})
    return out


def _notify(video_id, url, key):
    try:
        _post(f"{url}/functions/v1/notify-analysis",
              {"video_id": video_id, "secret": os.environ.get("ANALYZE_SHARED_SECRET", "")}, key)
    except Exception:
        pass


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
    mode = data.get("mode") or ("deep" if data.get("deep") else "simple")
    run_id, user_id = data.get("run_id"), data.get("user_id")
    if mode == "index":
        index_video.spawn(video_id, user_id)
    elif mode == "deep":
        analyze_deep.spawn(video_id, run_id, user_id)
    else:
        analyze.spawn(video_id, run_id, user_id)
    return {"status": "queued", "video_id": video_id, "mode": mode, "run_id": run_id}
