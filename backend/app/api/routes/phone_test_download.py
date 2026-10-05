"""Direct download mirror for test phones (served by staging only, never production).

GET/HEAD /downloads/askodox-phone-test-<build>.apk   staging phone-test builds
GET/HEAD /downloads/askodox-<build>.apk              exact MAIN release builds (they
                                                     still call the production backend)

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
    "1277": "04ab19d2462f21aae4f1bb7e101df1402a3b8f03e8601910dafb81732f9ee9bb",
}
# build -> pinned SHA-256 of the exact signed MAIN build on the in-app update
# channel (askodox-latest); mirrored byte-for-byte, never rebuilt.
MAIN_APKS = {
    "1283": "2db5535798f3791e6b5b983466eeaf8576ea095b6d5bfa387f4526fe099952e7",
    "1284": "31231e43591c71d5ab7ed27fad49762d8a2527ab4012a6648c5a3965307e96d1",
    "1285": "ddf62b03d9d42092f036f98e64dc324bda3c3d45c74d9c51ba327b38bd4804ee",
    "1286": "995974ef3c7b7749166d35c611293488538899baa5e7de4ee54dde2ddcd95922",
    "1287": "8b24ae111a01978cabe0c1664ddaa88b137114a4acea91031d38e137d2fd754d",
    "1288": "e8bd3c009c66da55fc27f55c90593ef782462b42def944cfa0a9e74dbefefb3e",
    "1289": "b6efc3797951c13402063c478530b020f4cb6c4575a24bfaa709bcfc002280a9",
    "1290": "502b3c542a56447a83ed10097d57b8d6b46a6842c34b4a4d3086f319b7bc6ae1",
    "1291": "4bc78abe17aa65663b4c14d0319292658f62ff61a8000bf272674b4396a5b13a",
    "1292": "3713241692e230dc674b569b699d6346c4b17d22424ccd7b5e9f3dd8ea46dfae",
    "1293": "389974d5f71ff7719ccb0a86dbee71d3129b3accf9ac4d096334a0ac96c8365d",
    "1294": "accc5b3c4bcbb893228da91cc3f1408a4afba4042f8685dba7924bc6a0e464e9",
    "1295": "a938ed69ecc7c6c5769720524bdf1373c68500e7482e4d74d56d1cbea9d144a3",
    "1296": "78f0c7b6f35906ad52b4cee6fce33b9c738bd5b0633b4560e5dcb4b32f83e526",
    "1297": "d3d56948bd3ea7e610cd54825254626a777a0195de7b80100d3a9071069ed0a7",
    "1298": "2779f729297dda4b651647b17ccac42bbaeedb8b3d52c016d5d10f08787daa18",
    "1300": "8907242bd6cc24611205b8f03291cd8a6fd5931257fba4de8e4c7687d93d417a",
    "1302": "7091c48304813f98081f0fc16b438d374fdc33d2566d2d940e6493a341026771",
}
SOURCE = "https://github.com/podx-bot/askodox/releases/download/phone-test-{b}/askodox-phone-test-{b}.apk"
MAIN_SOURCE = "https://github.com/podx-bot/askodox/releases/download/askodox-latest/askodox-{b}.apk"
APK_MIME = "application/vnd.android.package-archive"
_NAME = re.compile(r"^askodox-phone-test-(\d{1,6})\.apk$")
_MAIN_NAME = re.compile(r"^askodox-(\d{1,6})\.apk$")
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


def _ensure(build: str, fetch=None, *, main: bool = False) -> Path:
    pins, source = (MAIN_APKS, MAIN_SOURCE) if main else (PHONE_TEST_APKS, SOURCE)
    target = _cache_dir() / (f"askodox-{build}.apk" if main else f"askodox-phone-test-{build}.apk")
    with _lock:
        if target.exists() and _sha256(target) == pins[build]:
            return target
        partial = target.with_suffix(".part")
        (fetch or _download)(source.format(b=build), partial)
        if _sha256(partial) != pins[build]:
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

    match, main = _NAME.match(filename), False
    if match is None:
        match, main = _MAIN_NAME.match(filename), True
    if is_production(dict(os.environ)) or not match or match.group(1) not in (MAIN_APKS if main else PHONE_TEST_APKS):
        raise HTTPException(status_code=404, detail="Not found")
    path = _ensure(match.group(1), main=main)
    return FileResponse(
        path,
        media_type=APK_MIME,
        filename=filename,
        content_disposition_type="attachment",
        headers={"Cache-Control": "no-store, no-transform", "X-Content-Type-Options": "nosniff"},
    )
