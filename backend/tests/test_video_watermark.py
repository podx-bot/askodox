"""ASKODOX mark on videos posted inside ASKODOX (owner rule 2026-10-31): only
native uploads, the original kept, a failure never claims the mark."""
import os
import shutil
import subprocess

import pytest

from app.services import video_watermark as wm


class Repo:
    def __init__(self, data):
        self.record = {"id": "v1", "data": data}
        self.updates = []

    def get(self, record_id):
        return self.record if record_id == "v1" else None

    def update(self, record_id, *, actor, action, data):
        self.updates.append((actor, action))
        self.record = {"id": record_id, "data": data}
        return self.record


def test_success_moves_url_to_marked_copy_and_keeps_original():
    repo = Repo({"platform": "askodox", "url": "https://x/media/videos/abc.mp4"})
    out = wm.apply_to_record(repo, "v1", "/tmp", "abc.mp4", "https://x", marker=lambda src, dst: {"ok": True})
    assert out == {"ok": True}
    data = repo.record["data"]
    assert data["url"] == f"https://x/media/videos/{wm.marked_name('abc.mp4')}"
    assert data["original_url"] == "https://x/media/videos/abc.mp4"
    assert data["watermark"] == "applied"


def test_failure_keeps_the_uploaded_video_and_says_so():
    repo = Repo({"platform": "askodox", "url": "https://x/media/videos/abc.webm"})
    wm.apply_to_record(repo, "v1", "/tmp", "abc.webm", "https://x",
                       marker=lambda src, dst: {"ok": False, "reason": "no_video_stream"})
    data = repo.record["data"]
    assert data["url"] == "https://x/media/videos/abc.webm"
    assert data["watermark"] == "failed" and data["watermark_reason"] == "no_video_stream"


def test_outside_videos_are_never_touched():
    repo = Repo({"platform": "youtube", "url": "https://youtube.com/watch?v=1"})
    out = wm.apply_to_record(repo, "v1", "/tmp", "abc.mp4", "https://x", marker=lambda src, dst: {"ok": True})
    assert out["reason"] == "not_native" and repo.updates == []


def test_logo_size_follows_the_video():
    cmd = wm.command("ffmpeg", "in.mp4", "logo.png", "out.mp4", (720, 1280))
    graph = cmd[cmd.index("-filter_complex") + 1]
    assert "scale=101:-1" in graph and "overlay=W-w-22:H-h-22" in graph


def test_missing_ffmpeg_or_logo_fails_honestly(tmp_path):
    assert wm.mark_file("a.mp4", "b.mp4", exe=None, logo=str(tmp_path / "none.png"))["ok"] is False
    assert wm.mark_file("a.mp4", "b.mp4", exe="ffmpeg", logo=str(tmp_path / "none.png")) == {
        "ok": False, "reason": "logo_missing"}


@pytest.mark.skipif(not wm.ffmpeg_exe(), reason="ffmpeg not available")
def test_real_ffmpeg_marks_a_video_and_keeps_audio(tmp_path):
    exe = wm.ffmpeg_exe()
    src = str(tmp_path / "in.mp4")
    made = subprocess.run([exe, "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                           "testsrc=size=320x568:rate=15:duration=1", "-f", "lavfi", "-i",
                           "sine=frequency=440:duration=1", "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                           "-c:a", "aac", src], capture_output=True)
    if made.returncode != 0:
        pytest.skip("this ffmpeg cannot make a test clip")
    out = str(tmp_path / "in_ax.mp4")
    assert wm.mark_file(src, out, exe=exe) == {"ok": True}
    assert os.path.getsize(out) > 0 and wm.video_size(exe, out) == (320, 568)
    assert not os.path.exists(out + ".part.mp4")
    assert os.path.exists(wm.LOGO)


def test_garbage_bytes_fail_without_raising(tmp_path):
    exe = wm.ffmpeg_exe() or shutil.which("ffmpeg")
    if not exe:
        pytest.skip("ffmpeg not available")
    bad = tmp_path / "bad.mp4"
    bad.write_bytes(b"\x00\x00\x00\x18ftypmp42" + b"0" * 64)
    assert wm.mark_file(str(bad), str(tmp_path / "bad_ax.mp4"), exe=exe)["ok"] is False


def test_marked_name_is_one_the_media_route_serves():
    from app.api.routes.native_video import _NAME

    name = "0123456789abcdef0123456789abcdef.webm"
    assert _NAME.fullmatch(wm.marked_name(name)) and wm.marked_name(name) != name
