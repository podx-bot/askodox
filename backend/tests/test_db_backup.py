"""Owner-only encrypted database backup: consistent read-only snapshot,
AES-256-GCM with a passphrase that is never stored, a verified restore into
an isolated database, one-time download, no row contents or secrets in any
response / log / audit entry, and the live database left unchanged."""
import dataclasses
import logging
import os
import sqlite3
import subprocess
import sys
import uuid
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.services import db_backup

PASS = "correct horse battery staple 42"
MARKER = "PRIVATE-ROW-" + uuid.uuid4().hex
OWNER_KEY = "owner-backup-key-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
TOOL = Path(__file__).resolve().parents[1] / "tools" / "askodox_backup_restore.py"


def _live_db(path: Path, rows: int = 300) -> Path:
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE users(id INTEGER PRIMARY KEY, phone TEXT, note TEXT)")
    conn.execute("CREATE TABLE orders(id INTEGER PRIMARY KEY, user_id INTEGER, total REAL)")
    conn.executemany("INSERT INTO users(phone, note) VALUES(?, ?)",
                     [(f"+9198{i:08d}", MARKER) for i in range(rows)])
    conn.executemany("INSERT INTO orders(user_id, total) VALUES(?, ?)", [(i, i * 1.5) for i in range(rows * 2)])
    conn.commit()
    conn.close()
    return path


@pytest.fixture(autouse=True)
def _workdir(monkeypatch, tmp_path):
    work = tmp_path / "backup-work"
    monkeypatch.setenv("ASKODOX_BACKUP_WORKDIR", str(work))
    db_backup.reset_for_tests()
    yield work
    db_backup.reset_for_tests()


# ---------------------------------------------------------------- service --

def test_encrypt_decrypt_round_trip_and_tamper_detection(tmp_path, monkeypatch):
    monkeypatch.setattr(db_backup, "CHUNK", 1024)  # several chunks
    src = tmp_path / "plain.bin"
    src.write_bytes(os.urandom(5000))
    enc, out = tmp_path / "x.enc", tmp_path / "out.bin"
    db_backup.encrypt_file(src, enc, PASS)
    assert src.read_bytes()[:64] not in enc.read_bytes()
    db_backup.decrypt_file(enc, out, PASS)
    assert out.read_bytes() == src.read_bytes()

    with pytest.raises(db_backup.BackupError, match="Wrong passphrase"):
        db_backup.decrypt_file(enc, tmp_path / "w.bin", PASS + "x")
    data = bytearray(enc.read_bytes())
    data[-5] ^= 1
    (tmp_path / "t.enc").write_bytes(bytes(data))
    with pytest.raises(db_backup.BackupError):
        db_backup.decrypt_file(tmp_path / "t.enc", tmp_path / "t.bin", PASS)
    # Dropping the final chunk is detected (no silent truncation).
    raw = enc.read_bytes()
    header = len(db_backup.MAGIC) + 16 + 12
    pos, chunks = header, []
    while pos < len(raw):
        length = int.from_bytes(raw[pos:pos + 4], "big")
        chunks.append((pos, pos + 4 + 12 + length))
        pos = chunks[-1][1]
    assert len(chunks) == 5
    (tmp_path / "cut.enc").write_bytes(raw[:chunks[-1][0]])
    with pytest.raises(db_backup.BackupError, match="truncated"):
        db_backup.decrypt_file(tmp_path / "cut.enc", tmp_path / "cut.bin", PASS)
    with pytest.raises(db_backup.BackupError, match="at least"):
        db_backup.encrypt_file(src, tmp_path / "short.enc", "short")


def test_create_backup_verifies_restore_and_leaves_live_db_unchanged(tmp_path, _workdir):
    live = _live_db(tmp_path / "live.db")
    before = db_backup.sha256(live)
    result = db_backup.create_backup(live, PASS)

    assert db_backup.sha256(live) == before                     # production data unchanged
    assert result["restore_test"] == {"integrity_check": "ok", "row_counts_match": True,
                                      "sha256_match": True, "verified": True}
    assert result["tables"] == {"orders": 600, "users": 300}
    assert result["source_opened_read_only"] is True
    # Only the encrypted file is left; no plaintext snapshot / restore copy.
    left = sorted(p.name for p in _workdir.iterdir())
    assert left == [result["file_name"]]
    encrypted = _workdir / result["file_name"]
    assert MARKER.encode() not in encrypted.read_bytes()
    assert oct(encrypted.stat().st_mode & 0o777) == "0o600"
    assert db_backup.sha256(encrypted) == result["encrypted_sha256"]

    # Isolated restore with the standalone tool proves recoverability.
    restored = tmp_path / "restored.db"
    run = subprocess.run([sys.executable, "-I", str(TOOL), str(encrypted), str(restored),
                          "--expect-sha256", result["database_sha256"]],
                         env={**os.environ, "ASKODOX_BACKUP_PASSPHRASE": PASS},
                         capture_output=True, text=True, timeout=120)
    assert run.returncode == 0, run.stderr
    assert "PASS" in run.stdout and MARKER not in run.stdout
    conn = sqlite3.connect(restored)
    assert conn.execute("SELECT COUNT(*) FROM users WHERE note=?", (MARKER,)).fetchone()[0] == 300
    conn.close()
    # Wrong passphrase: the tool fails and leaves no partial file.
    bad = subprocess.run([sys.executable, "-I", str(TOOL), str(encrypted), str(tmp_path / "bad.db")],
                         env={**os.environ, "ASKODOX_BACKUP_PASSPHRASE": "x" * 20},
                         capture_output=True, text=True, timeout=120)
    assert bad.returncode == 1 and not (tmp_path / "bad.db").exists()


def test_snapshot_never_writes_to_a_read_only_source(tmp_path):
    live = _live_db(tmp_path / "ro.db", rows=5)
    os.chmod(live, 0o444)
    try:
        snap = tmp_path / "snap.db"
        db_backup.snapshot(live, snap)
        assert db_backup.inspect(snap)["tables"]["users"] == 5
    finally:
        os.chmod(live, 0o644)


def test_download_is_one_time_and_exports_expire(tmp_path, _workdir):
    live = _live_db(tmp_path / "live.db", rows=3)
    result = db_backup.create_backup(live, PASS)
    with pytest.raises(db_backup.BackupError):
        db_backup.take_download(result["backup_id"], "wrong-token")
    path = db_backup.take_download(result["backup_id"], result["download_token"])
    assert path.exists()
    with pytest.raises(db_backup.BackupError):
        db_backup.take_download(result["backup_id"], result["download_token"])

    second = db_backup.create_backup(live, PASS)
    db_backup.purge_expired(now=10 ** 12)
    assert not (_workdir / second["file_name"]).exists()
    with pytest.raises(db_backup.BackupError):
        db_backup.take_download(second["backup_id"], second["download_token"])


# ------------------------------------------------------------------ routes --

@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    live = _live_db(tmp_path / "prod-like.db")
    monkeypatch.setattr(container, "settings", dataclasses.replace(
        container.settings, admin_seed_key=OWNER_KEY, database_path=str(live)))
    from app.repositories.command_center_repository import CommandCenterRepository

    repo = CommandCenterRepository(str(tmp_path / "cc.db"))
    monkeypatch.setattr(container, "command_center_repository", repo, raising=False)
    yield TestClient(app), repo, live


def test_backup_routes_are_owner_only(api):
    client, repo, _ = api
    assert client.post("/admin/cc/backup/export", json={"passphrase": PASS}).status_code == 401
    from app.repositories.command_center_repository import PERMISSIONS

    staff = repo.create_staff("Full staff", "super_admin", list(PERMISSIONS), "owner")
    assert set(repo.get_staff(staff["id"])["permissions"]) == set(PERMISSIONS)
    resp = client.post("/admin/cc/backup/export", headers={"X-ASKODOX-Staff-Token": staff["token"]},
                       json={"passphrase": PASS})
    assert resp.status_code == 403
    assert client.get("/admin/cc/backup/download/x", headers={"X-ASKODOX-Staff-Token": staff["token"]}
                      ).status_code == 403


def test_short_passphrase_is_refused_without_echoing_it(api):
    client, _, _ = api
    resp = client.post("/admin/cc/backup/export", headers=OWNER, json={"passphrase": "tiny-secret"})
    assert resp.status_code == 422
    assert "tiny-secret" not in resp.text


def test_owner_export_download_and_restore_end_to_end(api, tmp_path, caplog):
    client, repo, live = api
    before = db_backup.sha256(live)
    caplog.set_level(logging.DEBUG)
    resp = client.post("/admin/cc/backup/export", headers=OWNER, json={"passphrase": PASS})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["restore_test"]["verified"] is True and body["tables"]["users"] == 300
    assert MARKER not in resp.text and "+9198" not in resp.text and PASS not in resp.text

    dl = client.get(f"/admin/cc/backup/download/{body['backup_id']}",
                    headers={**OWNER, "X-ASKODOX-Backup-Token": body["download_token"]})
    assert dl.status_code == 200 and dl.headers["cache-control"] == "no-store"
    blob = tmp_path / body["file_name"]
    blob.write_bytes(dl.content)
    assert db_backup.sha256(blob) == body["encrypted_sha256"]
    assert MARKER.encode() not in dl.content
    again = client.get(f"/admin/cc/backup/download/{body['backup_id']}",
                       headers={**OWNER, "X-ASKODOX-Backup-Token": body["download_token"]})
    assert again.status_code == 404

    restored = tmp_path / "isolated-restore.db"
    db_backup.decrypt_file(blob, restored, PASS)
    assert db_backup.sha256(restored) == body["database_sha256"]
    assert db_backup.inspect(restored)["tables"] == body["tables"]
    assert db_backup.sha256(live) == before

    logged = caplog.text + str(repo.audit_log(20))
    for secret in (PASS, OWNER_KEY, body["download_token"], MARKER):
        assert secret not in logged
    actions = [row["action"] for row in repo.audit_log(20)]
    assert "db_backup_export" in actions and "db_backup_download" in actions


def test_backup_page_holds_no_secrets(api):
    client, _, _ = api
    page = client.get("/admin/backup")
    assert page.status_code == 200 and page.headers["cache-control"] == "no-store"
    assert OWNER_KEY not in page.text and "noindex" in page.text
