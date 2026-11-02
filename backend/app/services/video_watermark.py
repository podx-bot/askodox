"""ASKODOX mark on videos posted INSIDE ASKODOX (owner rule 2026-10-31).

Only native uploads (``platform == "askodox"``) get the mark; outside videos
(YouTube / Facebook / Instagram links) are never touched. The mark is the
ASKODOX logo in the bottom-right corner, sized to the video, slightly
transparent. The original upload is kept; the record's ``url`` moves to the
marked copy only when ffmpeg succeeded, so a failure leaves the video exactly
as uploaded (``watermark`` = ``failed`` with a short reason, never a claim it
was marked).

Runs in a background thread after the upload answer is sent, so the phone
never waits for the encode. Switch: feature flag ``videos.watermark``.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import threading
from typing import Any, Callable, Optional

LOGO = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "askodox_watermark.png")
MARGIN_FRACTION = 0.03   # gap from the edges, share of the shorter side
LOGO_FRACTION = 0.14     # logo width, share of the shorter side
MIN_LOGO_PX = 40
TIMEOUT_S = 240


def ffmpeg_exe() -> Optional[str]:
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return shutil.which("ffmpeg")


def video_size(exe: str, src: str) -> Optional[tuple[int, int]]:
    """Width / height of the first video stream, read from ffmpeg's own banner."""
    import re

    try:
        probe = subprocess.run([exe, "-hide_banner", "-i", src], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    for line in probe.stderr.splitlines():
        if "Video:" in line:
            m = re.search(r"\b(\d{2,5})x(\d{2,5})\b", line)
            if m:
                return int(m.group(1)), int(m.group(2))
    return None


def command(exe: str, src: str, logo: str, out: str, size: tuple[int, int]) -> list[str]:
    short = min(size)
    logo_px = max(MIN_LOGO_PX, int(round(short * LOGO_FRACTION)))
    margin = max(8, int(round(short * MARGIN_FRACTION)))
    graph = (f"[1:v]scale={logo_px}:-1,format=rgba,colorchannelmixer=aa=0.85[mark];"
             f"[0:v][mark]overlay=W-w-{margin}:H-h-{margin}:format=auto[v]")
    return [exe, "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-i", logo,
            "-filter_complex", graph, "-map", "[v]", "-map", "0:a?",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out]


def mark_file(src: str, out: str, *, exe: Optional[str] = None, logo: str = LOGO,
              run: Callable[..., Any] = subprocess.run) -> dict[str, Any]:
    """Write a marked MP4 copy of ``src`` to ``out``. Returns
    ``{"ok": True}`` or ``{"ok": False, "reason": ...}``; never raises."""
    exe = exe or ffmpeg_exe()
    if not exe:
        return {"ok": False, "reason": "ffmpeg_missing"}
    if not os.path.exists(logo):
        return {"ok": False, "reason": "logo_missing"}
    size = video_size(exe, src)
    if not size:
        return {"ok": False, "reason": "no_video_stream"}
    tmp = out + ".part.mp4"
    try:
        result = run(command(exe, src, logo, tmp, size), capture_output=True, text=True, timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        _remove(tmp)
        return {"ok": False, "reason": "timeout"}
    except Exception:
        _remove(tmp)
        return {"ok": False, "reason": "ffmpeg_error"}
    if getattr(result, "returncode", 1) != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
        _remove(tmp)
        return {"ok": False, "reason": "ffmpeg_error"}
    os.replace(tmp, out)
    return {"ok": True}


def _remove(path: str) -> None:
    try:
        os.remove(path)
    except OSError:
        pass


def marked_name(name: str) -> str:
    return os.path.splitext(name)[0] + "_ax.mp4"


def apply_to_record(repo: Any, record_id: str, folder: str, name: str, base_url: str, *,
                    marker: Callable[..., dict[str, Any]] = mark_file) -> dict[str, Any]:
    """Mark the uploaded file and point the video record at the marked copy.
    The record keeps ``original_url``; on failure only ``watermark`` changes."""
    out_name = marked_name(name)
    outcome = marker(os.path.join(folder, name), os.path.join(folder, out_name))
    record = repo.get(record_id)
    if not record:
        return {"ok": False, "reason": "record_missing"}
    data = dict(record.get("data") or {})
    if data.get("platform") != "askodox":
        return {"ok": False, "reason": "not_native"}
    if outcome.get("ok"):
        data.update({"original_url": data.get("url"), "url": f"{base_url}/media/videos/{out_name}",
                     "watermark": "applied"})
    else:
        data.update({"watermark": "failed", "watermark_reason": str(outcome.get("reason") or "error")[:40]})
    repo.update(record_id, actor="system:watermark", action="watermark", data=data)
    return outcome


def start(repo: Any, record_id: str, folder: str, name: str, base_url: str) -> threading.Thread:
    """Background mark after upload (daemon thread; the upload answer is not delayed)."""
    def work() -> None:
        try:
            apply_to_record(repo, record_id, folder, name, base_url)
        except Exception:
            pass

    thread = threading.Thread(target=work, name=f"watermark-{record_id}", daemon=True)
    thread.start()
    return thread
