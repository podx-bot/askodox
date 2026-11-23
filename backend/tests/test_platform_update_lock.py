"""Platform record updates are serialized (no lost status from a background writer)."""
def test_platform_update_never_writes_back_a_stale_status(tmp_path):
    """Regression for the flaky native-video DM test: a writer that read the row before a concurrent approve must not
    put the old status back (update is now a read-modify-write under BEGIN IMMEDIATE)."""
    import sqlite3
    import threading

    from app.repositories.platform_repository import PlatformRepository

    repo = PlatformRepository(str(tmp_path / "pf.db"))
    rec = repo.create("videos", "vid", name="v", status="PENDING_REVIEW", data={"platform": "askodox"}, actor="t")
    holder = sqlite3.connect(str(tmp_path / "pf.db"), isolation_level=None)
    holder.execute("BEGIN IMMEDIATE")  # an approve in flight holds the write lock
    holder.execute("UPDATE pf_records SET status='ACTIVE' WHERE id=?", (rec["id"],))
    done = threading.Event()

    def watermark() -> None:
        repo.update(rec["id"], actor="system:watermark", action="watermark", data={"platform": "askodox", "w": 1})
        done.set()

    t = threading.Thread(target=watermark)
    t.start()
    assert not done.wait(0.3), "the background writer waits for the approve"
    holder.execute("COMMIT")
    t.join(5)
    assert repo.get(rec["id"])["status"] == "ACTIVE" and repo.get(rec["id"])["data"]["w"] == 1
