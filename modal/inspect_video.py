"""
Dev tool — visually inspect what the pose pipeline sees in a match video.

  python -m modal run modal/inspect_video.py --video-id <uuid> --out <dir>

Writes annotated JPEG frames (skeleton, bbox, court quadrant, body-normalised wrist speed) plus
stats.json (per-frame, per-person) and one crop per quadrant, so detector behaviour can be checked by eye.
Not part of the production app.
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
        "opencv-python-headless==4.10.0.84", "numpy==1.26.4", "onnxruntime==1.18.1", "rtmlib==0.0.13",
        "supervision==0.23.0", "boto3==1.34.162", "supabase==2.7.4", "fastapi==0.115.0", "tqdm==4.66.5",
    )
)
app = modal.App("badminton-ai-inspect")
secret = modal.Secret.from_name("badminton-ai")

EDGES = [(5, 7), (7, 9), (6, 8), (8, 10), (5, 6), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14), (14, 16)]


def _rest(path):
    url, key = os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    req = urllib.request.Request(f"{url}/rest/v1/{path}", headers={"apikey": key, "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


@app.function(image=image, timeout=900, cpu=2.0, memory=4096, secrets=[secret])
def inspect(video_id: str, every: int = 2, snap_every_s: float = 1.0, snap_from: float = 0.0,
            snap_to: float = 1e9, snap_px: int = 720):
    import cv2
    import numpy as np
    import boto3
    from botocore.config import Config
    from rtmlib import Body

    vid = _rest(f"match_videos?id=eq.{video_id}&select=storage_path,game_type")[0]
    s3 = boto3.client("s3", endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                      aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
                      aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
                      config=Config(signature_version="s3v4", region_name="auto"))
    ext = vid["storage_path"].rsplit(".", 1)[-1]
    local = os.path.join(tempfile.gettempdir(), f"{video_id}.{ext}")
    s3.download_file(os.environ["R2_VIDEO_BUCKET"], vid["storage_path"], local)

    cap = cv2.VideoCapture(local)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    w = cap.get(cv2.CAP_PROP_FRAME_WIDTH); h = cap.get(cv2.CAP_PROP_FRAME_HEIGHT)
    model = Body(mode="balanced", backend="onnxruntime", device="cpu")

    stats, images, prev, next_snap, raw = [], {}, {}, 0.0, []
    idx = -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        idx += 1
        if idx % every:
            continue
        t = idx / fps
        kpts, scores = model(frame)
        raw.append({"t": round(t, 3), "p": [{"k": np.round(pk, 1).tolist(), "s": np.round(ps, 2).tolist()}
                                            for pk, ps in zip(kpts if kpts is not None else [], scores if scores is not None else [])]})
        people = []
        for pk, ps in zip(kpts if kpts is not None else [], scores if scores is not None else []):
            good = ps > 0.3
            if good.sum() < 6:
                continue
            pts = pk[good]
            x1, y1, x2, y2 = pts[:, 0].min(), pts[:, 1].min(), pts[:, 0].max(), pts[:, 1].max()
            feet = [pk[i] for i in (15, 16) if ps[i] > 0.3] or [pk[i] for i in (11, 12) if ps[i] > 0.3]
            if not feet:
                continue
            fx, fy = np.mean(feet, axis=0)
            q = ("near" if fy / h > 0.5 else "far") + ("_left" if fx / w < 0.5 else "_right")
            sh = [pk[i][1] for i in (5, 6) if ps[i] > 0.3]; hp = [pk[i][1] for i in (11, 12) if ps[i] > 0.3]
            torso = abs(np.mean(hp) - np.mean(sh)) if (sh and hp) else (y2 - y1) * 0.35
            wr = [pk[i] for i in (9, 10)]
            v = None
            if q in prev and prev[q][0] < t:
                pt, pw, pps = prev[q]
                d = max((float(np.linalg.norm(wr[j] - pw[j])) for j in range(2) if ps[9 + j] > 0.5 and pps[9 + j] > 0.5), default=0.0)
                v = round(d / max(torso, 1.0) / (t - pt), 2)   # torso-lengths per second
            prev[q] = (t, wr, ps)
            people.append({"q": q, "conf": round(float(ps.mean()), 2), "torso_px": round(float(torso), 1),
                           "h_px": round(float(y2 - y1), 1), "wrist_v_torso_s": v,
                           "wrist_conf": [round(float(ps[9]), 2), round(float(ps[10]), 2)],
                           "bbox": [int(x1), int(y1), int(x2), int(y2)]})
            # annotate
            for a, b in EDGES:
                if ps[a] > 0.3 and ps[b] > 0.3:
                    cv2.line(frame, tuple(map(int, pk[a])), tuple(map(int, pk[b])), (0, 255, 255), 2)
            cv2.rectangle(frame, (int(x1), int(y1)), (int(x2), int(y2)), (0, 200, 0), 2)
            cv2.putText(frame, f"{q} c{ps.mean():.2f} v{v}", (int(x1), max(15, int(y1) - 6)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
        stats.append({"t": round(t, 2), "people": people})
        if t >= max(next_snap, snap_from) and t <= snap_to:
            next_snap = t + snap_every_s
            small = cv2.resize(frame, (int(w * snap_px / max(w, h)), int(h * snap_px / max(w, h))))
            images[f"frame_{t:05.2f}.jpg"] = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 70])[1].tobytes()
    cap.release()
    return {"meta": {"fps": fps, "total": total, "w": w, "h": h}, "stats": stats, "images": images, "raw": raw}


@app.function(image=image, secrets=[secret])
def fetch(keys: list):
    import boto3
    from botocore.config import Config
    s3 = boto3.client("s3", endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
                      aws_access_key_id=os.environ["R2_VIDEO_ACCESS_KEY_ID"],
                      aws_secret_access_key=os.environ["R2_VIDEO_SECRET_ACCESS_KEY"],
                      config=Config(signature_version="s3v4", region_name="auto"))
    return {k: s3.get_object(Bucket=os.environ["R2_VIDEO_BUCKET"], Key=k)["Body"].read() for k in keys}


@app.local_entrypoint()
def thumbs(keys: str, out: str = "thumbs_out"):
    """python -m modal run modal/inspect_video.py::thumbs --keys k1,k2 --out dir"""
    os.makedirs(out, exist_ok=True)
    for k, b in fetch.remote(keys.split(",")).items():
        with open(os.path.join(out, k.rsplit("/", 1)[-1]), "wb") as f:
            f.write(b)
    print("WROTE thumbs to", out)


@app.local_entrypoint()
def main(video_id: str, out: str = "inspect_out", every: int = 2, snap_every_s: float = 1.0,
         snap_from: float = 0.0, snap_to: float = 1e9, snap_px: int = 720):
    res = inspect.remote(video_id, every, snap_every_s, snap_from, snap_to, snap_px)
    os.makedirs(out, exist_ok=True)
    for name, b in res["images"].items():
        with open(os.path.join(out, name), "wb") as f:
            f.write(b)
    with open(os.path.join(out, "stats.json"), "w") as f:
        json.dump({"meta": res["meta"], "stats": res["stats"]}, f, indent=1)
    with open(os.path.join(out, "raw.json"), "w") as f:
        json.dump({"meta": res["meta"], "raw": res["raw"]}, f)
    print("WROTE", len(res["images"]), "images to", out)
