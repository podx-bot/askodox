"""Commission engine on the Partner Hub ledger: every commission model, a
click is never a conversion, partner-confirmed only, forward-only lifecycle
PENDING -> CONFIRMED -> PAYABLE -> PAID (+ REJECTED / REVERSED), hold period,
attribution window + fraud flags, duplicate prevention, read-only
reconciliation. Partners are test fixtures, not real companies."""
import dataclasses
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.repositories.partner_revenue_repository import PartnerRevenueRepository
from app.services import commission_engine as ce
from app.services import rate_limit
from app.services.secret_box import SecretBox

KEY = SecretBox.generate_key()
OWNER_KEY = "owner-com-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                                                   public_base_url="https://api.askodox.test",
                                                                   secrets_key=KEY))
    monkeypatch.setattr(container, "command_center_repository",
                        CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    repo = PartnerRevenueRepository(str(tmp_path / "p.db"), secret_box=SecretBox(KEY), click_key="ck-key")
    monkeypatch.setattr(container, "partner_revenue_repository", repo, raising=False)
    return TestClient(app), repo


def _partner(client, name, commission):
    r = client.post("/admin/cc/partners", headers=OWNER, json={
        "name": name, "categories": ["apps"], "countries": ["IN"], "signup_url": "https://example.test/join",
        "commission": commission, "active": True})
    assert r.status_code == 200, r.text
    partner = r.json()
    token = client.post(f"/admin/cc/partners/{partner['id']}/postback-token", headers=OWNER).json()["postback_url"]
    return partner, token.split("token=")[1].split("&")[0]


def _click(repo, partner_id, minutes_ago=60):
    click = repo.new_click_id()
    repo.record_event("impression", partner_id=partner_id, click_id=click, category="apps")
    when = (datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)).isoformat()
    with repo._connect() as conn:
        conn.execute("UPDATE revenue_events SET occurred_at=? WHERE click_id=?", (when, click))
    return click


def test_rules_for_every_model():
    assert ce.expected({"model": "cps", "percent": 5}, "sale", 2000) == 100
    assert ce.expected({"model": "cpi", "flat": 30}, "install", None) == 30
    assert ce.expected({"model": "cpl", "flat": 80}, "lead", None) == 80
    assert ce.expected({"model": "cpa", "per_event": {"signup": 150}}, "signup", None) == 150
    assert ce.expected({"model": "revenue_share", "percent": 20}, "subscription", 500) == 100
    assert ce.expected({"model": "recurring", "percent": 10}, "renewal", 300) == 30
    assert ce.expected({"model": "cpc", "flat": 2}, "sale", 100) is None, "a click is never a conversion"
    assert ce.expected({"percent": 4, "per_category": {"tv": 6}}, "sale", 1000, "tv") == 60, "old rules still work"
    for bad in ({"model": "magic"}, {"percent": 150}, {"attribution_days": 0}, {"per_event": {"click": 1}},
                {"flat": "x"}):
        with pytest.raises(ValueError):
            ce.validate_rule(bad)


def test_install_postbacks_lifecycle_and_fraud_flags(api):
    client, repo = api
    partner, token = _partner(client, "Example Apps", {"model": "cpi", "flat": 25, "attribution_days": 7,
                                                       "hold_days": 0})
    base = f"/api/partners/{partner['slug']}/postback"
    click = _click(repo, partner["id"])
    assert client.get(base, params={"token": "wrong", "event": "install", "install_id": "i1"}).status_code == 403
    ok = client.get(base, params={"token": token, "event": "install", "install_id": "i1", "click_id": click}).json()
    assert ok["recorded"] == "install" and ok["status"] == "PENDING" and ok["flags"] == []
    conv = repo.get_conversion(ok["conversion_id"])
    assert conv["event"] == "install" and conv["commission"] == 25 and conv["commission_source"] == "rule"
    # Same install reported twice: one conversion only.
    again = client.get(base, params={"token": token, "event": "install", "install_id": "i1", "click_id": click}).json()
    assert again["conversion_id"] == ok["conversion_id"]
    # A second install on the same click, and installs without / with a stale click, are flagged.
    dup = client.get(base, params={"token": token, "event": "install", "install_id": "i2", "click_id": click}).json()
    assert "repeat_conversion_for_click" in dup["flags"]
    blind = client.get(base, params={"token": token, "event": "install", "install_id": "i3"}).json()
    assert "no_click_id" in blind["flags"]
    old = _click(repo, partner["id"], minutes_ago=60 * 24 * 10)
    late = client.get(base, params={"token": token, "event": "install", "install_id": "i4", "click_id": old}).json()
    assert "outside_attribution_window" in late["flags"]
    fast = _click(repo, partner["id"], minutes_ago=0)
    quick = client.get(base, params={"token": token, "event": "install", "install_id": "i5", "click_id": fast}).json()
    assert "too_fast_after_click" in quick["flags"]
    with pytest.raises(Exception):
        client.get(base, params={"token": token, "event": "click", "install_id": "i9"}).raise_for_status()

    # Forward-only lifecycle (staff, confirmation, audit).
    cid = ok["conversion_id"]
    t = lambda to, confirm=True: client.post(f"/admin/cc/commissions/conversions/{cid}/transition",  # noqa: E731
                                             headers=OWNER, json={"to": to, "confirm": confirm})
    assert t("PAID").status_code == 409, "PENDING cannot jump to PAID"
    assert t("CONFIRMED", confirm=False).status_code == 409
    assert t("CONFIRMED").json()["conversion"]["status"] == "CONFIRMED"
    # A re-sent partner report never moves it backwards.
    client.get(base, params={"token": token, "event": "install", "install_id": "i1", "status": "pending"})
    assert repo.get_conversion(cid)["status"] == "CONFIRMED"
    moved = client.post("/admin/cc/commissions/promote-payable", headers=OWNER, json={"confirm": True}).json()
    assert cid in moved["moved_to_payable"], "hold_days=0 -> payable now"
    flagged_confirmed = dup["conversion_id"]
    client.post(f"/admin/cc/commissions/conversions/{flagged_confirmed}/transition", headers=OWNER,
                json={"to": "CONFIRMED", "confirm": True})
    assert flagged_confirmed not in client.post("/admin/cc/commissions/promote-payable", headers=OWNER,
                                                json={"confirm": True}).json()["moved_to_payable"], \
        "flagged conversions never become payable automatically"
    assert t("PAID").json()["conversion"]["status"] == "PAID"
    assert t("REVERSED").json()["conversion"]["status"] == "REVERSED", "refund / chargeback after payment"
    assert t("PAID").status_code == 409, "REVERSED is final"
    history = client.get(f"/admin/cc/commissions/conversions/{cid}", headers=OWNER).json()["history"]
    assert [h["to_state"] for h in history] == ["PENDING", "CONFIRMED", "PAYABLE", "PAID", "REVERSED"]

    summary = client.get("/admin/cc/commissions/summary", headers=OWNER).json()
    assert summary["by_state"]["PENDING"]["count"] >= 3
    assert {f["external_id"] for f in summary["fraud_review"]} >= {"i2", "i3", "i4", "i5"}
    assert client.get("/admin/cc/commissions/summary").status_code in (401, 403)


def test_cpl_cps_cpc_and_reconciliation(api):
    client, repo = api
    leads, ltok = _partner(client, "Example Loans", {"model": "cpl", "flat": 120})
    lead = client.get(f"/api/partners/{leads['slug']}/postback", params={
        "token": ltok, "event": "lead", "lead_id": "L1", "click_id": _click(repo, leads["id"]), "status": "approved"}).json()
    assert lead["recorded"] == "lead" and lead["status"] == "CONFIRMED"
    assert repo.get_conversion(lead["conversion_id"])["commission"] == 120
    shop, stok = _partner(client, "Example Shop", {"model": "cps", "percent": 5})
    sale = client.get(f"/api/partners/{shop['slug']}/postback", params={
        "token": stok, "order_id": "S1", "order_value": "2000", "commission": "90",
        "click_id": _click(repo, shop["id"])}).json()
    conv = repo.get_conversion(sale["conversion_id"])
    assert sale["recorded"] == "order" and conv["commission"] == 90 and conv["commission_source"] == "partner"
    # CPC: clicks only produce an EXPECTED amount, never a conversion.
    cpc, _ = _partner(client, "Example Ads", {"model": "cpc", "flat": 2})
    for _ in range(3):
        repo.record_event("click", partner_id=cpc["id"], click_id=repo.new_click_id())
    summary = client.get("/admin/cc/commissions/summary", headers=OWNER).json()
    row = next(c for c in summary["cpc_expected"] if c["partner"] == "Example Ads")
    assert row["clicks"] == 3 and row["expected_cpc_amount"] == 6 and "EXPECTED" in row["label"]
    assert "Example Ads" not in summary["by_partner"]
    # Reconciliation is read-only.
    csv_text = "order_id,status,commission\nS1,approved,95\nS9,approved,10\n"
    rec = client.post(f"/admin/cc/commissions/reconcile/{shop['id']}", headers=OWNER, json={"csv": csv_text}).json()
    assert rec["amount_mismatch"] == [{"order_id": "S1", "askodox": 90.0, "partner": 95.0}]
    assert rec["missing_in_askodox"] == ["S9"]
    assert repo.get_conversion(sale["conversion_id"])["commission"] == 90, "nothing changed"
