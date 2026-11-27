"""App Links (owner 2026-11-27): askodox.com video / shop / product links open the app."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAY_SHA256 = ("15:6C:E6:73:A0:5A:61:4F:CC:8A:BA:67:76:9A:BF:24:EF:02:C5:D9:CD:B9:2A:D3:17:C0:7D:BE:83:A5:D1:8D")


def test_assetlinks_served_with_the_play_signing_certificate():
    caddy = (ROOT / "website/server/Caddyfile").read_text(encoding="utf-8")
    assert "/.well-known/assetlinks.json" in caddy
    body = re.search(r"respond `(\[.*?\])` 200", caddy, re.S).group(1)
    link = json.loads(body)[0]
    assert link["relation"] == ["delegate_permission/common.handle_all_urls"]
    assert link["target"]["package_name"] == "com.askodox.askodox"
    assert link["target"]["sha256_cert_fingerprints"] == [PLAY_SHA256]
    assert "@askodox_video_share path /v/*" in caddy, "the shared video page must reach the backend"


def test_manifest_verifies_the_same_paths():
    manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
    assert 'android:autoVerify="true"' in manifest
    for prefix in ("/v/", "/s/", "/p/"):
        assert f'android:host="askodox.com" android:pathPrefix="{prefix}"' in manifest
