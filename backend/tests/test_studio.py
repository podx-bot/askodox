"""ASKODOX Studio (owner 2026-11-21): bought to shoot -> return deadline from the delivery date -> stages -> return /
keep -> reminders once per purchase and kind. Plus the staff page JavaScript still parses."""
import datetime as dt
import re
import shutil
import subprocess

import pytest

from app.services import studio_store as ss
from test_sources_workspace_early_access import OWNER, api  # noqa: F401  (fixture)

NOW = dt.datetime(2026, 11, 21, 4, 0, tzinfo=dt.timezone.utc)  # 09:30 IST


def _clock(moment=NOW):
    return lambda: moment


def test_deadline_bucket_and_warnings():
    assert ss.deadline("2026-11-20", "return", 7) == "2026-11-27"
    assert ss.deadline("2026-11-20", "exchange", 7) == "" and ss.deadline("", "return", 7) == ""
    assert [ss.bucket(x) for x in (-1, 0, 1, 2, None)] == ["today", "today", "tomorrow", "time", ""]
    assert ss.warnings({"return_option": "none", "account_label": "x", "account_whitelisted": 0}) == \
        ["keep", "not_whitelisted"]


def test_store_flow(tmp_path):
    store = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock())
    acct = store.save_account("meesho", "Wife 7227", True)
    assert acct["store"] == "Meesho" and acct["whitelisted"] == 1
    p = store.create({"title": "Silver anklets", "store": "Meesho", "account_id": acct["id"], "paid": "249",
                      "pack": "pair", "order_date": "2026-11-12", "delivery_date": "2026-11-15",
                      "return_option": "return", "return_days": 7}, actor="staff-1")
    assert p["return_deadline"] == "2026-11-22" and p["days_left"] == 1 and p["bucket"] == "tomorrow"
    assert p["stage"] == "delivered" and p["paid_paise"] == 24900 and p["pack_count"] == 2 and p["warnings"] == []
    with pytest.raises(ss.StudioError):
        store.create({"title": "x", "store": "Meesho", "order_date": "2026-11-20", "delivery_date": "2026-11-18"},
                     actor="staff-1")
    with pytest.raises(ss.StudioError):
        store.create({"title": "x", "store": "Meesho", "affiliate_link": "http://bad"}, actor="staff-1")
    p = store.set_stage(p["id"], "shot")
    with pytest.raises(ss.StudioError):
        store.set_stage(p["id"], "delivered")  # forward only
    p = store.set_stage(p["id"], "posted")
    assert p["next_action"] == "return"
    p = store.record_return(p["id"], {"return_id": "RT-1", "fee": "0", "refund_status": "sent"})
    assert p["refund_status"] == "sent" and p["next_action"] == "refund"
    p = store.record_return(p["id"], {"refund_status": "refunded"})
    assert p["stage"] == "returned" and p["days_left"] is None
    with pytest.raises(ss.StudioError):
        store.keep(p["id"], "studio")  # closed
    e = store.create({"title": "Kurti", "store": "Flipkart", "paid": 399, "return_option": "exchange"},
                     actor="staff-2")
    assert e["return_deadline"] == "" and "keep" in e["warnings"] and e["stage"] == "bought"
    store.keep(e["id"], "no_return")
    s = store.summary(store.list())
    assert s["open"] == 0 and s["spent"] == 399.0
    assert [r["id"] for r in store.list(actor="staff-2")] == [e["id"]]


def test_reminders_once_per_kind(tmp_path):
    store = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock())
    tomorrow = store.create({"title": "Anklets", "store": "Meesho", "delivery_date": "2026-11-15",
                             "return_option": "return", "return_days": 7}, actor="staff-1")
    today = store.create({"title": "Kurti", "store": "Meesho", "delivery_date": "2026-11-14",
                          "return_option": "return", "return_days": 7}, actor="staff-1")
    store.set_stage(today["id"], "posted")
    kinds = {(d["purchase"]["id"], d["kind"]) for d in store.due_reminders()}
    assert (tomorrow["id"], "d1") in kinds and (tomorrow["id"], "not_shot") in kinds
    assert (today["id"], "d0") in kinds and (today["id"], "send_return") in kinds
    assert store.mark_sent(today["id"], "d0") and not store.mark_sent(today["id"], "d0")
    early = ss.StudioStore(str(tmp_path / "s.db"), clock=_clock(dt.datetime(2026, 11, 21, 1, 0, tzinfo=dt.timezone.utc)))
    assert all(d["kind"] != "d0" for d in early.due_reminders())  # 06:30 IST: the deadline-day push waits for 08:00
    assert ss.reminder_text(today, "d0")["title"].startswith("ఈరోజే return ఆఖరు")


def test_studio_routes_and_reminder_push(api, monkeypatch):  # noqa: F811
    client, container, _ = api
    container.studio_store = ss.StudioStore(container.settings.database_path, clock=_clock())
    home = client.get("/admin/cc/workspace/studio", headers=OWNER)
    assert home.status_code == 200 and home.json()["summary"]["open"] == 0 and "Meesho" in home.json()["stores"]
    acct = client.post("/admin/cc/workspace/studio/accounts", headers=OWNER,
                       json={"store": "Meesho", "label": "Shop 7227", "whitelisted": False}).json()["account"]
    made = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={
        "title": "Silver anklets", "store": "Meesho", "account_id": acct["id"], "paid": 249,
        "delivery_date": "2026-11-15", "return_option": "return", "return_days": 7})
    assert made.status_code == 200, made.text
    p = made.json()["purchase"]
    assert p["bucket"] == "tomorrow" and "not_whitelisted" in p["warnings"]
    bad = client.post("/admin/cc/workspace/studio/purchases", headers=OWNER, json={"title": "x", "store": "Meesho",
                                                                                    "order_date": "21-11-2026"})
    assert bad.status_code == 422
    got = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/stage", headers=OWNER, json={"stage": "shot"})
    assert got.json()["purchase"]["stage"] == "shot"
    back = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/stage", headers=OWNER,
                       json={"stage": "bought"})
    assert back.status_code == 422
    sent = []
    from app.api.routes import studio as studio_routes

    class _Push:
        def notify(self, user_id, **kw):
            sent.append((user_id, kw["event_key"]))
            return 1

    monkeypatch.setattr("app.services.push_service.push_service", lambda c: _Push())
    first = studio_routes.send_reminders(container)
    again = studio_routes.send_reminders(container)
    assert first["sent"] >= 1 and again["sent"] == 0  # once per purchase and kind
    ret = client.post(f"/admin/cc/workspace/studio/purchases/{p['id']}/return", headers=OWNER,
                      json={"return_id": "RT-9", "refund_status": "refunded", "fee": 0})
    assert ret.json()["purchase"]["stage"] == "returned"
    assert client.post("/admin/cc/workspace/studio/purchases/999/keep", headers=OWNER, json={}).status_code == 404


@pytest.mark.skipif(not shutil.which("node"), reason="node not available")
def test_staff_page_script_parses(api, tmp_path):  # noqa: F811
    client, _, _ = api
    html = client.get("/staff").text
    scripts = re.findall(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", html, re.S)
    assert scripts and "async function studio()" in html
    path = tmp_path / "page.js"
    path.write_text("\n;\n".join(scripts))
    proc = subprocess.run(["node", "--check", str(path)], capture_output=True, text=True)
    assert proc.returncode == 0, proc.stderr[-800:]
