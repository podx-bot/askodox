"""Test session isolation: every pytest run gets its own fresh database.

The app's server container resolves its sqlite path from PODX_DATABASE_PATH
at import time; without this, runs shared ./podx_v2.db and data from a
previous run (listings, leads, offers) leaked into the next one. Set it
before `server` is imported by any test, unless the caller chose a path.
"""
import os
import tempfile

if not os.getenv("PODX_DATABASE_PATH"):
    _session_dir = tempfile.mkdtemp(prefix="askodox-tests-")
    os.environ["PODX_DATABASE_PATH"] = os.path.join(_session_dir, "podx_test.db")
