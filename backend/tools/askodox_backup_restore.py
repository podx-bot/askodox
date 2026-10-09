"""Decrypt + verify an ASKODOX database backup into a NEW SQLite file.

    ASKODOX_BACKUP_PASSPHRASE=... python -I backend/tools/askodox_backup_restore.py \
        askodox-db-<id>.sqlite.enc restored.db [--expect-sha256 <database_sha256>]

Never writes over an existing file (restore into an isolated copy first,
compare, and only then swap it in -- see docs/DATABASE_BACKUP.md). Prints
table names + row counts only, never row contents. The passphrase is read
from the environment or prompted for, never taken on the command line.
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services import db_backup  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("encrypted")
    parser.add_argument("output")
    parser.add_argument("--expect-sha256", default="")
    args = parser.parse_args(argv)
    out = Path(args.output)
    if out.exists():
        print(f"refusing to overwrite {out}", file=sys.stderr)
        return 2
    passphrase = os.environ.get("ASKODOX_BACKUP_PASSPHRASE") or getpass.getpass("Backup passphrase: ")
    try:
        db_backup.decrypt_file(Path(args.encrypted), out, passphrase)
    except db_backup.BackupError as exc:
        out.unlink(missing_ok=True)
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    info = db_backup.inspect(out)
    digest = db_backup.sha256(out)
    for name, count in info["tables"].items():
        print(f"{name}\t{count}")
    print(f"integrity_check={info['integrity']} tables={len(info['tables'])} "
          f"rows={sum(info['tables'].values())} sha256={digest}")
    if info["integrity"] != "ok" or (args.expect_sha256 and args.expect_sha256 != digest):
        print("FAIL: restored database does not verify", file=sys.stderr)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
