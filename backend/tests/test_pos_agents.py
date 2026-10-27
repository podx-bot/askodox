"""Role-based AI agents on the existing POS permissions + audit + human approval:
agents follow the role, facts come from the shop's records, the model only re-words,
sensitive actions wait for owner / manager approval and run as the approver."""
import uuid
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app.services import rate_limit
from app.services.pos_agents import PosAgents, buyer_answer, buyer_facts
from app.services.pos_store import PosError, PosStore
from app.services.session_tokens import issue_token

OWNER = "app-phone-9500000001"
MANAGER = "app-phone-9500000002"
CASHIER = "app-phone-9500000003"
ACCOUNTANT = "app-phone-9500000004"


@pytest.fixture()
def env(tmp_path):
    clock = {"now": datetime(2026, 10, 27, 6, 0, tzinfo=timezone.utc)}
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: clock["now"])
    agents = PosAgents(store)
    biz = store.create_business(OWNER, {"name": "Sai Kirana", "registration_type": "unregistered", "state_code": "36",
                                        "template": "kirana", "invoice_prefix": "SK"})["id"]
    for phone, role in (("9500000002", "manager"), ("9500000003", "cashier"), ("9500000004", "accountant")):
        store.set_member(biz, OWNER, phone, role)
    rice = store.add_product(biz, OWNER, {"name": "Sona rice 25kg", "unit": "pcs", "price_paise": 140000,
                                          "track_stock": True, "low_stock_milli": 5000, "opening_stock_milli": 2000})
    cust = store.add_customer(biz, OWNER, {"name": "Lakshmi", "phone": "9876500000"})
    store.create_invoice(biz, CASHIER, {"client_txn_id": "t-" + uuid.uuid4().hex, "customer_id": cust["id"],
                                        "lines": [{"product_id": rice["id"], "qty_milli": 1000}],
                                        "payments": [{"method": "cash", "amount_paise": 40000}]})
    return store, agents, biz, rice["id"], cust["id"]


def test_agents_follow_the_pos_role(env):
    _, agents, biz, _, _ = env
    ids = lambda u: {a["id"] for a in agents.agents(biz, u)}
    assert ids(OWNER) == {"owner", "sales", "support", "finance", "inventory", "hr", "tax"}
    assert ids(CASHIER) == {"sales", "support"}
    assert ids(ACCOUNTANT) == {"finance", "tax"}
    assert "hr" not in ids(MANAGER)  # staff roles stay with the owner
    with pytest.raises(PosError) as e:
        agents.ask(biz, CASHIER, "finance", "dues?")
    assert e.value.status == 403
    with pytest.raises(PosError) as e:
        agents.ask(biz, "app-phone-9599999999", "owner", "")
    assert e.value.status == 404


def test_answers_are_grounded_and_the_model_only_rewords(env):
    _, agents, biz, _, _ = env
    out = agents.ask(biz, OWNER, "owner", "")
    text = out["answer"]
    assert out["answer_source"] == "rules"
    assert "1 bills" in text and "₹1,400" in text and "cash ₹400" in text
    assert "Low stock: 1 items." in text and "Lakshmi ₹1,000" in text
    seen = {}

    def fake_model(prompt):
        seen["prompt"] = prompt
        return "Today you made one bill of Rs 1,400; Lakshmi owes Rs 1,000."

    ai = agents.ask(biz, OWNER, "finance", "who owes me money?", phrase=fake_model)
    assert ai["answer_source"] == "ai" and "Lakshmi" in seen["prompt"] and "ONLY the facts" in seen["prompt"]
    assert list(ai["facts"]) == ["dues"]  # the question picked the skill
    te = agents.ask(biz, OWNER, "finance", "", te=True)
    assert "బాకీ" in te["answer"]
    assert agents.ask(biz, OWNER, "finance", "x", phrase=lambda p: "")["answer_source"] == "rules"


def test_sensitive_actions_wait_for_approval_and_run_as_the_approver(env):
    store, agents, biz, rice, cust = env
    prop = agents.propose(biz, ACCOUNTANT, "finance", "record_payment",
                          {"customer_id": cust, "amount_paise": 50000, "method": "upi", "reference": "UTR1"})
    assert prop["status"] == "PENDING_APPROVAL" and prop["risk"] == "sensitive"
    assert store.customer(biz, OWNER, cust)["balance_paise"] == 100000  # nothing moved yet
    with pytest.raises(PosError) as e:
        agents.decide(biz, CASHIER, prop["id"], True)
    assert e.value.status == 403
    done = agents.decide(biz, MANAGER, prop["id"], True)
    assert done["status"] == "DONE" and done["result"]["balance_paise"] == 50000
    with pytest.raises(PosError) as e:
        agents.decide(biz, OWNER, prop["id"], True)
    assert e.value.status == 409
    # four eyes: a manager cannot approve their own proposal
    stock = agents.propose(biz, MANAGER, "inventory", "stock_adjust",
                           {"product_id": rice, "kind": "count", "qty_milli": 8000, "reason": "Counted shelf"})
    with pytest.raises(PosError) as e:
        agents.decide(biz, MANAGER, stock["id"], True)
    assert e.value.code == "four_eyes"
    rejected = agents.decide(biz, OWNER, stock["id"], False, "count again")
    assert rejected["status"] == "REJECTED"
    assert store.product(biz, OWNER, rice)["stock_milli"] == 1000
    # staff role changes: owner only
    role = agents.propose(biz, OWNER, "hr", "set_member_role", {"phone": "9500000003", "role": "manager"})
    assert role["params"]["phone"] == "…0003"
    agents.decide(biz, OWNER, role["id"], True)
    actions = [a["action"] for a in store.audit(biz, OWNER)[:6]]
    assert "agent.execute" in actions and "agent.approve" in actions and "agent.propose" in actions


def test_safe_actions_run_at_once_and_failures_are_recorded(env):
    store, agents, biz, _, cust = env
    lead = agents.crm.add_lead(biz, CASHIER, {"name": "Ramu"})
    f = agents.propose(biz, CASHIER, "sales", "crm_followup", {"lead_id": lead["id"], "due_at": "tomorrow",
                                                               "note": "Call back"})
    assert f["status"] == "DONE"
    assert agents.crm.lead(biz, CASHIER, lead["id"])["next_followup"]["due_at"].startswith("2026-10-28")
    bad = agents.propose(biz, CASHIER, "sales", "crm_stage", {"lead_id": lead["id"], "stage": "lost"})
    assert bad["status"] == "FAILED" and "why" in bad["error"]  # lost needs a reason: the CRM rule still applies
    with pytest.raises(PosError):
        agents.propose(biz, CASHIER, "sales", "record_payment", {"customer_id": cust, "amount_paise": 1})
    with pytest.raises(PosError):
        agents.propose(biz, ACCOUNTANT, "finance", "record_payment", {"customer_id": cust, "amount_paise": 10**9,
                                                                      "method": "cash"})


def test_buyer_agent_reads_only_my_records(env):
    store, _, _, _, _ = env
    facts = buyer_facts(store, "app-phone-9876500000")
    assert facts["shop_advances_waiting"] == 0 and facts["my_shops"] == 0
    assert "never pay" in " ".join(buyer_answer(facts, False))


@pytest.fixture()
def api(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    for attr in ("pos_store", "pos_crm", "pos_agents"):
        monkeypatch.setattr(container, attr, None, raising=False)
    secret = container.settings.session_token_secret
    return TestClient(app), (lambda user: {"Authorization": f"Bearer {issue_token(user, secret)}"})


def test_http_agents(api):
    client, auth = api
    owner = "app-phone-9500000101"
    biz = client.post("/api/pos/businesses", json={"name": "Agent Shop", "state_code": "36"}, headers=auth(owner)).json()["id"]
    base = f"/api/pos/businesses/{biz}"
    assert client.get(base + "/agents").status_code == 401
    assert {a["id"] for a in client.get(base + "/agents", headers=auth(owner)).json()["agents"]} >= {"owner", "tax"}
    out = client.post(base + "/agents/owner/ask", json={"question": "", "use_ai": False}, headers=auth(owner)).json()
    assert out["answer_source"] == "rules" and "Today: 0 bills" in out["answer"]
    assert client.post(base + "/agents/payroll/ask", json={}, headers=auth(owner)).status_code == 404
    me = client.post("/api/pos/me/agents/buyer/ask", json={"question": "anything pending?"}, headers=auth(owner)).json()
    assert me["agent"] == "buyer" and me["facts"]["my_shops"] == 1
