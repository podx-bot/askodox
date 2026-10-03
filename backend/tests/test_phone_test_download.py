"""Staging phone-test APK download: exact headers, checksum-pinned, never in production."""
import hashlib

import pytest
from fastapi.testclient import TestClient

from app.api.routes import phone_test_download as dl

APK = b"PK\x03\x04" + b"apk-bytes" * 1000


@pytest.fixture()
def client(monkeypatch, tmp_path):
    from server import app

    monkeypatch.setenv("ASKODOX_PHONE_TEST_CACHE", str(tmp_path))
    monkeypatch.delenv("RAILWAY_ENVIRONMENT_NAME", raising=False)
    monkeypatch.delenv("ASKODOX_ENV", raising=False)
    monkeypatch.setitem(dl.PHONE_TEST_APKS, "9999", hashlib.sha256(APK).hexdigest())
    fetched = []
    monkeypatch.setattr(dl, "_download", lambda url, dest: (fetched.append(url), dest.write_bytes(APK)))
    return TestClient(app), fetched


def test_apk_is_served_with_download_headers_and_cached(client):
    c, fetched = client
    r = c.get("/downloads/askodox-phone-test-9999.apk")
    assert r.status_code == 200 and r.content == APK
    assert r.headers["content-type"] == "application/vnd.android.package-archive"
    assert r.headers["content-length"] == str(len(APK))
    assert r.headers["content-disposition"] == 'attachment; filename="askodox-phone-test-9999.apk"'
    assert "content-encoding" not in r.headers
    h = c.head("/downloads/askodox-phone-test-9999.apk")
    assert h.status_code == 200 and h.headers["content-length"] == str(len(APK))
    assert fetched == [dl.SOURCE.format(b="9999")], "fetched once, then served from disk"


def test_unknown_builds_bad_checksums_and_production_are_refused(client, monkeypatch):
    c, _ = client
    assert c.get("/downloads/askodox-phone-test-1.apk").status_code == 404
    assert c.get("/downloads/..%2Fetc%2Fpasswd").status_code == 404
    monkeypatch.setitem(dl.PHONE_TEST_APKS, "9998", "0" * 64)
    assert c.get("/downloads/askodox-phone-test-9998.apk").status_code == 502
    monkeypatch.setenv("RAILWAY_ENVIRONMENT_NAME", "production")
    assert c.get("/downloads/askodox-phone-test-9999.apk").status_code == 404


def test_main_build_mirror_is_byte_exact_and_refused_in_production(client, monkeypatch):
    c, fetched = client
    monkeypatch.setitem(dl.MAIN_APKS, "9997", hashlib.sha256(APK).hexdigest())
    r = c.get("/downloads/askodox-9997.apk")
    assert r.status_code == 200 and r.content == APK
    assert r.headers["content-disposition"] == 'attachment; filename="askodox-9997.apk"'
    assert fetched[-1] == dl.MAIN_SOURCE.format(b="9997")
    assert c.get("/downloads/askodox-9999.apk").status_code == 404, "phone-test builds never under a main name"
    assert c.get("/downloads/askodox-phone-test-9997.apk").status_code == 404
    assert dl.MAIN_APKS["1283"] == "2db5535798f3791e6b5b983466eeaf8576ea095b6d5bfa387f4526fe099952e7"
    monkeypatch.setenv("RAILWAY_ENVIRONMENT_NAME", "production")
    assert c.get("/downloads/askodox-9997.apk").status_code == 404
