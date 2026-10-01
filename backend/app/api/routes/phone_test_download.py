"""Direct download of a STAGING phone-test APK (never in production).

GET/HEAD /downloads/askodox-phone-test-<build>.apk

Only builds listed in PHONE_TEST_APKS are served. The file is fetched once
from its test-only GitHub prerelease, its SHA-256 is checked against the
pinned value, then it is served from local disk with plain download headers
(Content-Type application/vnd.android.package-archive, Content-Length,
Content-Disposition attachment) -- no redirects, no ZIP, no sign-in.
"""
from __future__ import annotations

import hashlib
import os
import re
import tempfile
import threading
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

router = APIRouter(tags=["phone-test"])

# build -> pinned SHA-256 of the signed, CI-verified APK
PHONE_TEST_APKS = {
    "1274": "217f1fb4e1957a9c2462adbb01683c15edbf52ca42cc163e4fa10ed9aa87bce1",
    "1275": "c1bba4815912d39bc9dfd8970a80ab039b40dd8564797f8e667cd35712b3c67f",
    "1276": "58d09a7fb35c9712794adc4cfd88e2085561558eff70b711de40571036db6f6f",
}
SOURCE = "https://github.com/podx-bot/askodox/releases/download/phone-test-{b}/askodox-phone-test-{b}.apk"
APK_MIME = "application/vnd.android.package-archive"
_NAME = re.compile(r"^askodox-phone-test-(\d{1,6})\.apk$")
_lock = threading.Lock()


def _cache_dir() -> Path:
    path = Path(os.getenv("ASKODOX_PHONE_TEST_CACHE", "") or Path(tempfile.gettempdir()) / "askodox-phone-test")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ensure(build: str, fetch=None) -> Path:
    target = _cache_dir() / f"askodox-phone-test-{build}.apk"
    with _lock:
        if target.exists() and _sha256(target) == PHONE_TEST_APKS[build]:
            return target
        partial = target.with_suffix(".part")
        (fetch or _download)(SOURCE.format(b=build), partial)
        if _sha256(partial) != PHONE_TEST_APKS[build]:
            partial.unlink(missing_ok=True)
            raise HTTPException(status_code=502, detail="phone-test APK failed its checksum")
        partial.replace(target)
        return target


def _download(url: str, dest: Path) -> None:
    with httpx.stream("GET", url, follow_redirects=True, timeout=httpx.Timeout(30.0, read=120.0)) as response:
        if response.status_code != 200:
            raise HTTPException(status_code=502, detail="phone-test APK source unavailable")
        with dest.open("wb") as handle:
            for chunk in response.iter_bytes(1 << 20):
                handle.write(chunk)


@router.api_route("/downloads/{filename}", methods=["GET", "HEAD"], include_in_schema=False)
def phone_test_apk(filename: str) -> FileResponse:
    from app.services.commerce_finance import is_production

    match = _NAME.match(filename)
    if is_production(dict(os.environ)) or not match or match.group(1) not in PHONE_TEST_APKS:
        raise HTTPException(status_code=404, detail="Not found")
    path = _ensure(match.group(1))
    return FileResponse(
        path,
        media_type=APK_MIME,
        filename=filename,
        content_disposition_type="attachment",
        headers={"Cache-Control": "no-store, no-transform", "X-Content-Type-Options": "nosniff"},
    )
