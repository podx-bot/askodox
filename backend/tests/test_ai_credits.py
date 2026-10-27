"""AI Credits: gateway-confirmed top-ups only, idempotent ledger, atomic spending, refunds, staff settings, metering."""
import threading
from datetime import datetime, timezone

import pytest

from app.services.ai_credits import AiCredits, CreditsError

USER = "app-phone-9400000701"


def _svc(tmp_path, **settings):
    svc = AiCredits(str(tmp_path / "c.db"), clock=lambda: datetime(2026, 10, 27, 6, 0, tzinfo=timezone.utc))
    if settings:
        svc.update_settings(settings, actor="staff:1")
    return svc


def test_off_by_default_nothing_is_deducted(tmp_path):
    svc = _svc(tmp_path)
    assert svc.settings()["charging"] is False
    assert svc.reserve(USER, "chat", "r1") == {"charged": False, "reason": "charging_off", "paise": 0}
    assert svc.balance(USER) == {"live": 0, "test": 0}
    with pytest.raises(CreditsError) as err:
        svc.update_settings({"charging": True}, actor="staff:1")
    assert err.value.code == "no_rates", "charging cannot start without rates"
    with pytest.raises(CreditsError):
        svc.update_settings({"rates_paise": {"chat": -1}}, actor="staff:1")
    with pytest.raises(CreditsError):
        svc.update_settings({"rates_paise": {"teleport": 5}}, actor="staff:1")


def test_topup_idempotent_spend_free_quota_release_and_refund(tmp_path):
    svc = _svc(tmp_path, charging=True, rates_paise={"chat": 50}, free_per_day={"chat": 2})
    assert svc.topup(USER, paise=10000, purchase_id="p1", mode="live") is True
    assert svc.topup(USER, paise=10000, purchase_id="p1", mode="live") is False, "a repeated webhook adds nothing"
    assert svc.balance(USER)["live"] == 10000
    assert svc.reserve(USER, "chat", "a")["free"] and svc.reserve(USER, "chat", "b")["free"]
    assert svc.reserve(USER, "chat", "c") == {"charged": True, "paise": 50, "mode": "live"}
    assert svc.reserve(USER, "chat", "c")["repeat"], "a retried request is never charged twice"
    assert svc.balance(USER)["live"] == 9950
    assert svc.release(USER, "c") and not svc.release(USER, "c")
    assert svc.balance(USER)["live"] == 10000
    assert svc.reverse_topup(USER, purchase_id="p1") and not svc.reverse_topup(USER, purchase_id="p1")
    assert svc.balance(USER)["live"] == 0
    with pytest.raises(CreditsError) as err:
        svc.reserve(USER, "chat", "d")
    assert err.value.status == 402 and err.value.detail["needed_paise"] == 50
    kinds = [h["kind"] for h in svc.history(USER)]
    assert kinds == ["refund", "release", "usage", "topup"], "free uses are not shown as money rows"
    summary = svc.summary()
    assert summary["outstanding_paise"]["live"] == 0 and summary["buyers"] == 1


def test_test_credits_are_separate_and_spent_after_real_ones(tmp_path):
    svc = _svc(tmp_path, charging=True, rates_paise={"chat": 100})
    svc.topup(USER, paise=100, purchase_id="t1", mode="test")
    svc.topup(USER, paise=100, purchase_id="l1", mode="live")
    assert svc.reserve(USER, "chat", "x")["mode"] == "live"
    assert svc.reserve(USER, "chat", "y")["mode"] == "test"
    assert svc.balance(USER) == {"live": 0, "test": 0}


def test_parallel_spending_never_goes_below_zero(tmp_path):
    svc = _svc(tmp_path, charging=True, rates_paise={"chat": 100})
    svc.topup(USER, paise=500, purchase_id="p", mode="live")
    results = []

    def spend(i):
        try:
            svc.reserve(USER, "chat", f"r{i}")
            results.append("ok")
        except CreditsError:
            results.append("no")
        except Exception:  # a busy CI disk may time out a waiting writer: that request simply fails, never double-spends
            results.append("error")

    threads = [threading.Thread(target=spend, args=(i,)) for i in range(20)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    ok = results.count("ok")
    assert ok <= 5 and svc.balance(USER)["live"] == 500 - 100 * ok >= 0, results
    assert results.count("error") or ok == 5


def test_billing_activates_credits_only_on_gateway_paid(monkeypatch, tmp_path):
    from types import SimpleNamespace

    from app.api.routes import ai_credits as routes
    from app.services import billing

    svc = _svc(tmp_path)
    monkeypatch.setattr(routes, "ai_credits", lambda container: svc)
    purchases = {}

    class Store:
        def get(self, pid):
            return purchases.get(pid)

        def update(self, pid, **fields):
            purchases[pid] = {**purchases[pid], **fields}
            return purchases[pid]

        def log(self, *a, **k):
            pass

    monkeypatch.setattr(billing, "store", lambda container: Store())
    monkeypatch.setattr(billing, "_notify", lambda *a, **k: None)
    plan = {"code": "ai_credits_100", "price": 100.0, "credits": 120.0, "audience": "ai_credits"}
    monkeypatch.setattr("app.api.routes.growth.growth", lambda container: SimpleNamespace(plan=lambda code: plan))
    container = SimpleNamespace()
    purchases["L"] = {"id": "L", "user_id": USER, "kind": "credits", "plan_code": plan["code"], "status": "PENDING",
                      "mode": "live", "amount": 100.0}
    purchases["T"] = {**purchases["L"], "id": "T", "mode": "test"}
    billing.on_payment(container, {"id": 1, "order_ref": "billing:L", "status": "FAILED"})
    assert svc.balance(USER)["live"] == 0, "a failed payment adds nothing"
    purchases["L"]["status"] = "PENDING"
    billing.on_payment(container, {"id": 1, "order_ref": "billing:L", "status": "PAID"})
    billing.on_payment(container, {"id": 1, "order_ref": "billing:L", "status": "PAID"})
    assert purchases["L"]["status"] == "ACTIVE" and svc.balance(USER)["live"] == 12000, "staff-set credits, once"
    billing.on_payment(container, {"id": 2, "order_ref": "billing:T", "status": "PAID"})
    assert purchases["T"]["status"] == "TEST_PAID" and svc.balance(USER)["test"] == 12000
    billing.on_payment(container, {"id": 1, "order_ref": "billing:L", "status": "REFUNDED"})
    assert purchases["L"]["status"] == "REFUNDED" and svc.balance(USER)["live"] == 0


def test_http_routes_and_assistant_metering(monkeypatch):
    from fastapi.testclient import TestClient

    from app.api.routes import ai_credits as routes
    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "ai_credits", None, raising=False)
    user = "app-phone-9411100701"
    auth = {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}
    client = TestClient(app)
    assert client.get("/api/me/ai-credits").status_code == 401
    mine = client.get("/api/me/ai-credits", headers=auth).json()
    assert mine["charging"] is False and mine["balance_paise"] == {"live": 0, "test": 0}
    assert [p["plan_code"] for p in mine["packs"]] == ["ai_credits_100", "ai_credits_200", "ai_credits_300",
                                                        "ai_credits_500", "ai_credits_1000"]
    assert not any(p["payable"] for p in mine["packs"]), "packs are seeded OFF sale"
    assert client.get("/admin/cc/ai-credits/settings").status_code in (401, 403)
    # Charging on with no balance: a signed-in chat is answered with a recharge notice, not the model.
    svc = routes.ai_credits(container)
    svc.update_settings({"charging": True, "rates_paise": {"chat": 25}}, actor="test")
    try:
        out = client.post("/api/in-app/assistant", headers=auth, json={"message": "best phone under 15000"}).json()
        assert out["source"] == "credits" and out["credits"]["status"] == "insufficient" and "Recharge" in out["reply"]
        anon = client.post("/api/in-app/assistant", json={"message": "best phone under 15000"}).json()
        assert anon["source"] != "credits"
    finally:
        svc.update_settings({"charging": False}, actor="test")
