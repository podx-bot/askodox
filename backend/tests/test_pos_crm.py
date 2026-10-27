"""Business CRM inside My Business, on the ONE POS core: leads / enquiries, stage rules,
follow-ups + reminders, quotations = the sale screen's quotation drafts, complaints,
customer history from real bills / payments / ledger, pipeline, reports, roles."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit
from app.services.pos_crm import PosCrm, parse_due
from app.services.pos_store import PosError, PosStore
from app.services.session_tokens import issue_token

OWNER = "app-phone-9400000001"
CASHIER = "app-phone-9400000002"
ACCOUNTANT = "app-phone-9400000003"
STRANGER = "app-phone-9400000009"


def _txn():
    return "t-" + uuid.uuid4().hex


@pytest.fixture()
def env(tmp_path):
    clock = {"now": datetime(2026, 10, 27, 6, 0, tzinfo=timezone.utc)}  # 11:30 IST
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: clock["now"])
    crm = PosCrm(store)
    biz = store.create_business(OWNER, {"name": "Lakshmi Furniture", "registration_type": "unregistered",
                                        "state_code": "36", "template": "general", "invoice_prefix": "LF"})["id"]
    store.set_member(biz, OWNER, "9400000002", "cashier")
    store.set_member(biz, OWNER, "9400000003", "accountant")
    item = store.add_product(biz, OWNER, {"name": "Teak dining table", "unit": "pcs", "price_paise": 2500000})
    return store, crm, biz, item["id"], clock


def test_lead_lifecycle_stage_rules_and_timeline(env):
    store, crm, biz, _, _ = env
    lead = crm.add_lead(biz, CASHIER, {"name": "Ravi", "phone": "9876543210", "source": "walk_in",
                                       "need": "6-seater dining table", "value_paise": 2500000,
                                       "followup_at": "2026-10-28", "followup_note": "Call with photos"})
    assert lead["stage"] == "new" and lead["assigned_to"]["me"] is True
    assert lead["next_followup"]["due_at"].startswith("2026-10-28T10:00")
    lead = crm.update_lead(biz, CASHIER, lead["id"], {"stage": "contacted"})
    with pytest.raises(PosError) as e:
        crm.update_lead(biz, CASHIER, lead["id"], {"stage": "lost"})
    assert e.value.code == "lost_reason"  # a lost lead always says why
    with pytest.raises(PosError) as e:
        crm.update_lead(biz, CASHIER, lead["id"], {"stage": "contacted", "version": lead["version"] - 1})
    assert e.value.status == 409  # someone else changed it
    lead = crm.update_lead(biz, CASHIER, lead["id"], {"stage": "lost", "lost_reason": "Price too high"})
    assert lead["closed_at"]
    with pytest.raises(PosError) as e:  # a cashier cannot reopen a closed lead
        crm.update_lead(biz, CASHIER, lead["id"], {"stage": "contacted"})
    assert e.value.status == 403
    lead = crm.update_lead(biz, OWNER, lead["id"], {"stage": "negotiation"})
    assert lead["stage"] == "negotiation" and lead["closed_at"] is None
    texts = [t["text"] for t in lead["timeline"]]
    assert any("(reopened)" in t for t in texts) and any("contacted → lost" in t for t in texts)
    assert store.audit(biz, OWNER)[0]["action"] == "crm.lead.update"


def test_enquiry_from_askodox_is_saved_once_and_becomes_a_pos_customer(env):
    store, crm, biz, _, _ = env
    first = crm.add_lead(biz, OWNER, {"kind": "enquiry", "name": "Asha", "source": "askodox", "source_ref": "deal-41"})
    again = crm.add_lead(biz, OWNER, {"kind": "enquiry", "name": "Asha", "source": "askodox", "source_ref": "deal-41"})
    assert again["id"] == first["id"]
    lead = crm.lead_to_customer(biz, OWNER, first["id"], {"phone": "9000000001"})
    assert lead["customer_id"]
    # the ONE customer list: the lead's person is now a normal POS customer
    assert [c["name"] for c in store.customers(biz, OWNER)] == ["Asha"]
    assert crm.lead_to_customer(biz, OWNER, first["id"], {})["customer_id"] == lead["customer_id"]
    with pytest.raises(PosError):
        crm.add_lead(biz, OWNER, {"name": "x", "source": "billboard"})


def test_quotation_is_the_sale_screen_draft_linked_to_the_lead(env):
    store, crm, biz, item, _ = env
    lead = crm.add_lead(biz, OWNER, {"name": "Kiran", "need": "table"})
    draft = store.save_draft(biz, CASHIER, {"kind": "quotation", "title": "Kiran · 1 items",
                                            "payload": {"lines": [{"product_id": item, "qty_milli": 1000}],
                                                        "estimate_paise": 2400000, "lead_id": lead["id"]}})
    crm.link_quote(biz, CASHIER, draft["id"], {"lead_id": lead["id"]})
    lead = crm.lead(biz, OWNER, lead["id"])
    assert lead["stage"] == "quoted" and lead["value_paise"] == 2400000
    assert lead["quotations"][0]["draft_id"] == draft["id"] and lead["quotations"][0]["status"] == "draft"
    quotes = crm.quotations(biz, OWNER)
    assert quotes[0]["lead_name"] == "Kiran" and quotes[0]["lines"] == 1
    with pytest.raises(PosError) as e:  # billed needs the real bill
        crm.link_quote(biz, OWNER, draft["id"], {"status": "billed"})
    assert e.value.code == "invoice_id"
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "lines": [{"product_id": item, "qty_milli": 1000}],
                                              "payments": [{"method": "cash", "amount_paise": 2500000}]})
    assert crm.link_quote(biz, OWNER, draft["id"], {"status": "billed", "invoice_id": inv["id"]})["status"] == "billed"
    won = crm.update_lead(biz, OWNER, lead["id"], {"stage": "won", "won_invoice_id": inv["id"]})
    assert won["won_invoice_id"] == inv["id"]
    with pytest.raises(PosError):
        crm.link_quote(biz, OWNER, "drf_missing", {})


def test_followups_due_today_close_with_next_and_reminders_once(env):
    store, crm, biz, _, clock = env
    lead = crm.add_lead(biz, OWNER, {"name": "Meena"})
    crm.add_followup(biz, OWNER, {"lead_id": lead["id"], "due_at": "2026-10-27T09:00", "note": "Send price list"})
    crm.add_followup(biz, OWNER, {"lead_id": lead["id"], "due_at": "2026-10-30", "note": "Visit shop"})
    due = crm.followups(biz, OWNER, when="due")
    assert [f["note"] for f in due] == ["Send price list"] and due[0]["overdue"] is True
    assert [f["note"] for f in crm.followups(biz, OWNER, when="upcoming")] == ["Visit shop"]
    reminders = crm.due_reminders()
    assert len(reminders) == 1 and reminders[0]["app_user_id"] == OWNER
    assert crm.due_reminders() == []  # each follow-up is reminded only once
    crm.close_followup(biz, OWNER, due[0]["id"], {"outcome": "Sent on WhatsApp", "next_at": "2026-10-29T18:30",
                                                  "next_note": "Ask decision"})
    with pytest.raises(PosError) as e:
        crm.close_followup(biz, OWNER, due[0]["id"], {})
    assert e.value.status == 409
    assert [f["note"] for f in crm.followups(biz, OWNER, when="upcoming")] == ["Ask decision", "Visit shop"]
    pipe = crm.pipeline(biz, OWNER)
    assert pipe["followups_overdue"] == 0 and pipe["stages"][0] == {"stage": "new", "count": 1, "value_paise": 0}
    with pytest.raises(PosError):
        parse_due("tomorrow")
    assert parse_due("2026-10-27T18:00").hour == 12  # 18:00 IST = 12:30 UTC


def test_complaints_need_a_resolution_and_feed_customer_history(env):
    store, crm, biz, item, clock = env
    cust = store.add_customer(biz, OWNER, {"name": "Suresh", "phone": "9123456780"})
    inv = store.create_invoice(biz, CASHIER, {"client_txn_id": _txn(), "customer_id": cust["id"],
                                              "lines": [{"product_id": item, "qty_milli": 1000}],
                                              "payments": [{"method": "cash", "amount_paise": 1000000}]})
    comp = crm.add_complaint(biz, CASHIER, {"customer_id": cust["id"], "invoice_id": inv["id"],
                                            "subject": "Table leg loose", "priority": "high"})
    assert comp["name"] == "Suresh" and comp["status"] == "open"
    with pytest.raises(PosError) as e:
        crm.update_complaint(biz, CASHIER, comp["id"], {"status": "resolved"})
    assert e.value.code == "resolution"
    clock["now"] += timedelta(hours=5)
    done = crm.update_complaint(biz, CASHIER, comp["id"], {"status": "resolved", "resolution": "Carpenter fixed it"})
    assert done["resolved_at"] and "Carpenter" in done["timeline"][0]["text"]
    crm.add_activity(biz, CASHIER, {"customer_id": cust["id"], "kind": "call", "text": "Thanked for the fix"})
    hist = crm.customer_history(biz, OWNER, cust["id"])
    assert hist["summary"]["bills"] == 1 and hist["summary"]["billed_paise"] == 2500000
    assert hist["summary"]["due_paise"] == 1500000  # from the real customer ledger
    assert hist["complaints"][0]["status"] == "resolved" and hist["payments"][0]["amount_paise"] == 1000000
    assert any(t["kind"] == "call" for t in hist["timeline"])
    report = crm.report(biz, OWNER, "2026-10-01", "2026-10-31")
    assert report["complaints"] == {"raised": 1, "solved": 1, "avg_hours_to_solve": 5.0}
    assert report["top_customers"][0]["name"] == "Suresh" and report["dues"][0]["due_paise"] == 1500000


def test_roles_assignment_and_reports_permission(env):
    store, crm, biz, _, _ = env
    staff = crm.staff(biz, OWNER)
    cashier_ref = next(s["ref"] for s in staff if s["role"] == "cashier")
    assert all(len(s["last4"]) == 4 for s in staff)  # phone numbers never leave the shop list
    lead = crm.add_lead(biz, OWNER, {"name": "Divya", "assigned_to": cashier_ref, "source": "phone_call"})
    assert [x["name"] for x in crm.leads(biz, CASHIER, mine=True)] == ["Divya"]
    assert crm.leads(biz, OWNER, mine=True) == []
    with pytest.raises(PosError) as e:
        crm.add_lead(biz, OWNER, {"name": "x", "assigned_to": "not-a-member"})
    assert e.value.code == "assigned_to"
    with pytest.raises(PosError) as e:
        crm.leads(biz, ACCOUNTANT)  # accountant: reports only
    assert e.value.status == 403
    assert crm.report(biz, ACCOUNTANT, "2026-10-01", "2026-10-31")["leads"] == 1
    with pytest.raises(PosError) as e:
        crm.report(biz, CASHIER, "2026-10-01", "2026-10-31")
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        crm.leads(biz, STRANGER)
    assert e.value.status == 404  # another shop's CRM does not exist for you
    crm.update_lead(biz, OWNER, lead["id"], {"stage": "won"})
    assert crm.report(biz, OWNER, "2026-10-01", "2026-10-31")["by_source"][0]["win_rate_pct"] == 100.0


# --------------------------------------------------------------------- HTTP
@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_crm", None, raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    return TestClient(app), auth


def test_http_crm_flow(api):
    client, auth = api
    owner = "app-phone-9400000101"
    biz = client.post("/api/pos/businesses", json={"name": "Ganesh Hardware", "state_code": "36"},
                      headers=auth(owner)).json()["id"]
    base = f"/api/pos/businesses/{biz}/crm"
    assert client.get(base + "/pipeline").status_code == 401
    lead = client.post(base + "/leads", json={"name": "Venkat", "kind": "enquiry", "source": "whatsapp",
                                              "need": "PVC pipes 50", "followup_at": "2026-12-01"},
                       headers=auth(owner)).json()
    assert lead["kind"] == "enquiry"
    patched = client.patch(f"{base}/leads/{lead['id']}", json={"stage": "contacted"}, headers=auth(owner)).json()
    assert patched["stage"] == "contacted" and patched["need"] == "PVC pipes 50"  # PATCH never blanks fields
    draft = client.post(f"/api/pos/businesses/{biz}/drafts", json={
        "kind": "quotation", "title": "Venkat", "payload": {"lines": [], "lead_id": lead["id"],
                                                            "estimate_paise": 50000}}, headers=auth(owner)).json()
    assert draft["crm_linked"] is True
    assert client.get(f"{base}/leads/{lead['id']}", headers=auth(owner)).json()["stage"] == "quoted"
    assert client.get(base + "/pipeline", headers=auth(owner)).json()["open_value_paise"] == 50000
    comp = client.post(base + "/complaints", json={"name": "Venkat", "subject": "Wrong size sent"},
                       headers=auth(owner)).json()
    assert client.get(base + "/complaints?status=active", headers=auth(owner)).json()["complaints"][0]["id"] == comp["id"]
    assert client.get(base + "/leads", headers=auth("app-phone-9400000199")).status_code == 404
    assert client.get(base + "/report?date_from=2026-01-01&date_to=2026-12-31", headers=auth(owner)).status_code == 200
