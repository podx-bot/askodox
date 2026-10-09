"""Encrypted, verified backup of the SQLite database (owner-only export).

Flow (``create_backup``):
1. Consistent snapshot through SQLite's online backup API from a READ-ONLY
   connection (``mode=ro``) -- the live database is never written.
2. ``PRAGMA integrity_check`` + per-table row counts of the snapshot.
3. Encryption: scrypt(passphrase) -> AES-256-GCM in 4 MiB chunks. The header
   and each chunk's index + final flag are authenticated, so a reordered,
   truncated or altered file fails to decrypt. The passphrase is never
   stored, logged or returned; without it the file is unreadable.
4. Restore test: the encrypted file is decrypted into a SEPARATE temporary
   database, which must pass ``integrity_check``, carry the same table row
   counts and hash to the same SHA-256 as the snapshot.
5. Every plaintext copy (snapshot, restore test) is deleted; only the
   encrypted file remains, in a private temp directory, until it is
   downloaded once or expires.

The manifest holds table NAMES and row COUNTS only -- never row contents.
"""
from __future__ import annotations

import hashlib
import os
import secrets
import shutil
import sqlite3
import struct
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b"ASKODOXBK1\n"
CHUNK = 4 * 1024 * 1024
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2 ** 15, 8, 1
MIN_PASSPHRASE = 16
TTL_SECONDS = 30 * 60
DISK_FACTOR = 3.2  # snapshot + encrypted copy + restore test, with headroom


class BackupError(Exception):
    """A backup step failed; the message is safe to show (no secrets)."""


# ------------------------------------------------------------ encryption --

def _key(passphrase: str, salt: bytes, n: int, r: int, p: int) -> bytes:
    return Scrypt(salt=salt, length=32, n=n, r=r, p=p).derive(passphrase.encode("utf-8"))


def encrypt_file(src: Path, dst: Path, passphrase: str) -> None:
    if len(passphrase or "") < MIN_PASSPHRASE:
        raise BackupError(f"Passphrase must be at least {MIN_PASSPHRASE} characters")
    salt = os.urandom(16)
    header = MAGIC + salt + struct.pack(">III", SCRYPT_N, SCRYPT_R, SCRYPT_P)
    aead = AESGCM(_key(passphrase, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P))
    size = src.stat().st_size
    with src.open("rb") as fin, dst.open("wb") as fout:
        fout.write(header)
        index, done = 0, 0
        while True:
            block = fin.read(CHUNK)
            done += len(block)
            final = done >= size
            nonce = os.urandom(12)
            sealed = aead.encrypt(nonce, block, header + struct.pack(">QB", index, 1 if final else 0))
            fout.write(struct.pack(">I", len(sealed)) + nonce + sealed)
            index += 1
            if final:
                break


def decrypt_file(src: Path, dst: Path, passphrase: str) -> None:
    with src.open("rb") as fin, dst.open("wb") as fout:
        magic = fin.read(len(MAGIC))
        if magic != MAGIC:
            raise BackupError("Not an ASKODOX backup file")
        salt = fin.read(16)
        params = fin.read(12)
        if len(salt) != 16 or len(params) != 12:
            raise BackupError("Backup file is damaged")
        n, r, p = struct.unpack(">III", params)
        header = magic + salt + params
        aead = AESGCM(_key(passphrase, salt, n, r, p))
        index, finished = 0, False
        while True:
            raw_len = fin.read(4)
            if not raw_len:
                break
            if finished:
                raise BackupError("Backup file is damaged (data after the final chunk)")
            (length,) = struct.unpack(">I", raw_len)
            nonce, sealed = fin.read(12), fin.read(length)
            if len(nonce) != 12 or len(sealed) != length:
                raise BackupError("Backup file is damaged (truncated)")
            plain = None
            for flag in (0, 1):
                try:
                    plain = aead.decrypt(nonce, sealed, header + struct.pack(">QB", index, flag))
                    finished = bool(flag)
                    break
                except InvalidTag:
                    continue
            if plain is None:
                raise BackupError("Wrong passphrase or damaged backup file")
            fout.write(plain)
            index += 1
        if not finished:
            raise BackupError("Backup file is damaged (truncated)")


# ---------------------------------------------------------------- sqlite --

def snapshot(db_path: str | Path, dest: Path) -> None:
    """Consistent copy of a live database; the source is opened read-only."""
    source = sqlite3.connect(f"file:{Path(db_path).resolve()}?mode=ro", uri=True, timeout=30)
    try:
        target = sqlite3.connect(str(dest))
        try:
            source.backup(target)
        finally:
            target.close()
    finally:
        source.close()


def inspect(path: Path) -> dict[str, Any]:
    """integrity_check + table row counts (names and counts only)."""
    conn = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    try:
        integrity = str(conn.execute("PRAGMA integrity_check").fetchone()[0])
        names = [row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        counts = {name: int(conn.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0]) for name in names}
    finally:
        conn.close()
    return {"integrity": integrity, "tables": counts}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _unlink(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


# ---------------------------------------------------------------- export --

_lock = threading.Lock()
_exports: dict[str, dict[str, Any]] = {}


def _workdir() -> Path:
    base = Path(os.getenv("ASKODOX_BACKUP_WORKDIR", "") or Path(tempfile.gettempdir()) / "askodox-backup")
    base.mkdir(parents=True, exist_ok=True)
    os.chmod(base, 0o700)
    return base


def purge_expired(now: float | None = None) -> None:
    now = time.time() if now is None else now
    with _lock:
        for backup_id in [k for k, v in _exports.items() if v["expires_at"] <= now]:
            _unlink(_exports.pop(backup_id)["path"])


def create_backup(db_path: str | Path, passphrase: str) -> dict[str, Any]:
    """Snapshot -> encrypt -> verified restore test. Returns the manifest
    plus a one-time download token (only its hash is kept)."""
    if len(passphrase or "") < MIN_PASSPHRASE:
        raise BackupError(f"Passphrase must be at least {MIN_PASSPHRASE} characters")
    db = Path(db_path)
    if not db.is_file():
        raise BackupError("Database file not found")
    purge_expired()
    work = _workdir()
    free = shutil.disk_usage(work).free
    if free < db.stat().st_size * DISK_FACTOR:
        raise BackupError("Not enough free temporary disk space for a verified backup")
    backup_id = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + secrets.token_hex(4)
    snap, restored = work / f"{backup_id}.snapshot.db", work / f"{backup_id}.restore-test.db"
    encrypted = work / f"askodox-db-{backup_id}.sqlite.enc"
    try:
        snapshot(db, snap)
        source = inspect(snap)
        if source["integrity"] != "ok":
            raise BackupError("The database snapshot failed its integrity check")
        snap_hash = sha256(snap)
        encrypt_file(snap, encrypted, passphrase)
        os.chmod(encrypted, 0o600)
        decrypt_file(encrypted, restored, passphrase)
        restored_info = inspect(restored)
        restored_hash = sha256(restored)
        verified = (restored_info["integrity"] == "ok" and restored_info["tables"] == source["tables"]
                    and restored_hash == snap_hash)
        if not verified:
            raise BackupError("Restore test did not match the snapshot")
        token = secrets.token_urlsafe(32)
        manifest = {
            "backup_id": backup_id,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "file_name": encrypted.name,
            "encrypted_bytes": encrypted.stat().st_size,
            "encrypted_sha256": sha256(encrypted),
            "database_bytes": snap.stat().st_size,
            "database_sha256": snap_hash,
            "encryption": "AES-256-GCM, scrypt(n=2^15,r=8,p=1) passphrase key, 4 MiB authenticated chunks",
            "restore_test": {"integrity_check": restored_info["integrity"], "row_counts_match": True,
                             "sha256_match": True, "verified": True},
            "table_count": len(source["tables"]),
            "row_total": sum(source["tables"].values()),
            "tables": source["tables"],
            "source_opened_read_only": True,
            "expires_in_seconds": TTL_SECONDS,
        }
        with _lock:
            _exports[backup_id] = {"path": encrypted, "expires_at": time.time() + TTL_SECONDS,
                                   "token_sha256": hashlib.sha256(token.encode()).hexdigest()}
        return {**manifest, "download_token": token}
    except BackupError:
        _unlink(encrypted)
        raise
    except Exception as exc:  # never echo paths / SQL / passphrase material
        _unlink(encrypted)
        raise BackupError(f"Backup failed ({type(exc).__name__})") from None
    finally:
        _unlink(snap)
        _unlink(restored)


def take_download(backup_id: str, token: str) -> Path:
    """One-time: a valid token releases the file and forgets the export."""
    purge_expired()
    with _lock:
        entry = _exports.get(backup_id)
        if not entry or not secrets.compare_digest(
                entry["token_sha256"], hashlib.sha256((token or "").encode()).hexdigest()):
            raise BackupError("Unknown, expired or already downloaded backup")
        _exports.pop(backup_id)
    return entry["path"]


def discard(backup_id: str) -> bool:
    with _lock:
        entry = _exports.pop(backup_id, None)
    if entry:
        _unlink(entry["path"])
    return entry is not None


def reset_for_tests() -> None:
    with _lock:
        for entry in _exports.values():
            _unlink(entry["path"])
        _exports.clear()
