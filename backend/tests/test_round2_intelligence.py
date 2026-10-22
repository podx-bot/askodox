"""Round 2: tax / GST, fraud & market reality, smart tricks.

Numbers are checked against the official rules recorded in
tax_intelligence.SOURCES (verified 2026-10-23); the gate attaches cards only
when the user's own words ask, and how-to-evade / how-to-scam asks are
answered with awareness, never steps."""
import pytest
from fastapi.testclient import TestClient

from app.services import fraud_awareness, intelligence_gate, rate_limit, smart_tricks, tax_intelligence as ti


# ------------------------------------------------------------ income tax

@pytest.mark.parametrize("salary, expected", [
    (1275000, 0),        # Rs 12.75 lakh salary: nil after the Rs 75,000 standard deduction + rebate
    (1300000, 26000),    # marginal relief: tax limited to the 25,000 above 12 lakh, + 4% cess
    (1675000, 124800),   # taxable 16 lakh: 20,000 + 40,000 + 60,000 = 1,20,000, + 4% cess
])
def test_new_regime_salaried(salary, expected):
    result = ti.compute_income_tax(year="2025-26", regime="new", salary_income=salary)
    assert result["total_tax"] == expected
    assert result["sources"] and all(s["url"].startswith("https://") for s in result["sources"])


def test_old_regime_with_deductions_and_senior_slabs():
    young = ti.compute_income_tax(year="2025-26", regime="old", salary_income=1000000, deductions=150000)
    # taxable 10,00,000 - 50,000 - 1,50,000 = 8,00,000: 12,500 + 60,000 = 72,500 (+4% = 75,400)
    assert young["taxable_income"] == 800000 and young["total_tax"] == 75400
    senior = ti.compute_income_tax(year="2025-26", regime="old", other_income=800000, age_band="60_to_80")
    assert senior["slab_tax"] == 70000  # 3-5L 10,000 + 5-8L 60,000
    rebate = ti.compute_income_tax(year="2025-26", regime="old", other_income=500000)
    assert rebate["total_tax"] == 0


def test_new_regime_ignores_deductions_and_says_so():
    r = ti.compute_income_tax(regime="new", salary_income=1500000, deductions=200000)
    assert r["deductions_used"] == 0 and any("not allowed in the new regime" in n for n in r["notes"])


def test_surcharge_and_marginal_relief_at_50_lakh():
    just_over = ti.compute_income_tax(regime="new", other_income=5010000)
    at = ti.compute_income_tax(regime="new", other_income=5000000)
    # crossing Rs 50 lakh by Rs 10,000 can raise tax (before cess) by at most Rs 10,000
    assert (just_over["slab_tax"] + just_over["surcharge"]) - (at["slab_tax"] + at["surcharge"]) <= 10000 + 1
    assert any("marginal relief" in n for n in just_over["notes"])


def test_regime_comparison_and_unknown_year():
    c = ti.compare_regimes(salary_income=900000, deductions=150000)
    assert c["lower_tax"] == "new" and c["new"]["total_tax"] == 0
    with pytest.raises(ti.TaxInputError):
        ti.compute_income_tax(year="2030-31", salary_income=1)
    with pytest.raises(ti.TaxInputError):
        ti.compute_income_tax(salary_income=-1)


def test_tax_year_2026_27_rates_marked_carried_forward():
    r = ti.compute_income_tax(year="2026-27", regime="new", salary_income=1275000)
    assert r["total_tax"] == 0 and r["law"] == "Income-tax Act, 2025"
    assert r["rule_status"] == "rates_verified_other_amounts_carried_forward"


# ------------------------------------------------------------ GST

@pytest.mark.parametrize("state, supply, turnover, required", [
    ("Andhra Pradesh", "goods", 3500000, False),
    ("Telangana", "goods", 3500000, True),        # Rs 20 lakh goods State
    ("Andhra Pradesh", "services", 2500000, True),
    ("Manipur", "services", 1500000, True),        # Rs 10 lakh services State
    ("Karnataka", "both", 2500000, True),          # any services -> services threshold
])
def test_gst_registration_threshold_by_state(state, supply, turnover, required):
    r = ti.gst_registration_check(turnover=turnover, supply=supply, state=state)
    assert r["registration_required_by_turnover"] is required
    assert "not automatically illegal" in r["no_invoice_note"]


def test_composition_rules():
    ok = ti.composition_check(turnover=10000000, business="trader", state="Andhra Pradesh")
    assert ok["eligible"] and ok["rate_percent_of_turnover"] == 1.0
    no = ti.composition_check(turnover=10000000, business="trader", state="Sikkim", interstate_outward=True)
    assert not no["eligible"] and len(no["blockers"]) == 2
    svc = ti.composition_check(turnover=6000000, business="services", state="Kerala")
    assert not svc["eligible"] and svc["rate_percent_of_turnover"] == 6.0


def test_gst_amount_split():
    intra = ti.gst_amount(amount=118, rate_percent=18, inclusive=True)
    assert intra["taxable_value"] == 100 and intra["split"] == {"cgst": 9.0, "sgst": 9.0}
    inter = ti.gst_amount(amount=1000, rate_percent=5, interstate=True)
    assert inter["split"] == {"igst": 50.0} and inter["total"] == 1050
    with pytest.raises(ti.TaxInputError):
        ti.gst_amount(amount=10, rate_percent=50)


# ------------------------------------------------------------ evasion vs awareness

@pytest.mark.parametrize("text", [
    "how to make fake gst invoices to claim itc",
    "can you get me fake rent receipts for HRA",
    "how do I hide my cash sales from GST",
    "how to evade income tax",
    "నకిలీ బిల్లులు ఎలా తయారు చేయాలి",
])
def test_evasion_asks_detected(text):
    assert ti.evasion_intent(text)


@pytest.mark.parametrize("text", [
    "is this a fake invoice?",
    "my shop bill has no GST, is that illegal?",
    "how can I legally reduce my income tax",
    "what is the GST rate on cement",
])
def test_lawful_and_victim_questions_not_flagged(text):
    assert not ti.evasion_intent(text)


# ------------------------------------------------------------ fraud

def test_every_scheme_has_complete_checklist_and_official_channels():
    for s in fraud_awareness.SCHEMES:
        card = fraud_awareness.scheme(s["id"], "te")
        assert card["warning_signs"] and card["verify"] and card["evidence"] and card["report"]
        assert card["normal_practice"], "legitimate practice stated, so sellers are not falsely accused"
        for channel in card["report"]:
            assert channel["source"].startswith("https://")


@pytest.mark.parametrize("text, scheme", [
    ("someone asked my OTP for a refund, is it a scam?", "online_payment_scam"),
    ("used car odometer looks tampered, fraud?", "vehicle_resale_fraud"),
    ("job offer asks registration fee, is it a scam", "employment_scam"),
    ("is this gold genuine or fake, no hallmark", "counterfeit_goods"),
    ("ఉద్యోగం ఫీజు అడుగుతున్నారు మోసమా", "employment_scam"),
])
def test_fraud_matching(text, scheme):
    assert fraud_awareness.fraud_intent(text)
    assert fraud_awareness.match(text) == scheme


def test_how_to_commit_is_refused():
    assert fraud_awareness.commit_intent("how to roll back odometer of my car")
    assert fraud_awareness.commit_intent("how can I make fake hallmark")
    assert not fraud_awareness.commit_intent("how to check odometer tampering")


# ------------------------------------------------------------ smart tricks

def test_smart_tricks_use_only_given_numbers():
    up = smart_tricks.unit_price([{"name": "1 kg", "price": 120, "quantity": 1, "unit": "kg"},
                                  {"name": "5 kg", "price": 500, "quantity": 5, "unit": "kg"}])
    assert up["cheapest"] == "5 kg" and up["saving_vs_costliest_percent"] == 16.7
    rent = smart_tricks.buy_vs_rent(purchase_price=60000, resale_value=20000, yearly_upkeep=1200,
                                    rent_per_month=2000, months_needed=12)
    assert rent["cheaper"] == "rent" and rent["breakeven_months"] == 21.1
    rr = smart_tricks.repair_vs_replace(repair_cost=6000, replacement_price=30000, age_years=8, expected_life_years=12)
    assert rr["suggestion"] == "repair"
    rr_old = smart_tricks.repair_vs_replace(repair_cost=6000, replacement_price=30000, age_years=13, expected_life_years=12)
    assert rr_old["suggestion"] == "replace"
    bulk = smart_tricks.bulk_buy(unit_price_small=60, unit_price_bulk=50, units_needed=12, bulk_units=30,
                                 monthly_use=2, shelf_life_months=6)
    assert bulk["expected_waste_units"] == 18 and bulk["worth_it"] is False
    with pytest.raises(smart_tricks.TrickInputError):
        smart_tricks.unit_price([{"price": 1, "quantity": 1, "unit": "kg"}, {"price": 1, "quantity": 1, "unit": "l"}])


# ------------------------------------------------------------ gate

@pytest.mark.parametrize("text, kind", [
    ("What is my income tax on 15 lakh salary?", "income_tax"),
    ("ఆదాయపు పన్ను ఎంత కట్టాలి", "income_tax"),
    ("do I need GST registration for my shop", "gst"),
    ("is this UPI refund call a scam", "fraud"),
    ("should I buy or rent a camera for a month", "smart_tricks"),
    ("how to make fake gst invoices", "tax_evasion_awareness"),
    ("how to roll back the odometer", "fraud_refusal"),
])
def test_gate_kinds(text, kind):
    assert intelligence_gate.build(text)["kind"] == kind


@pytest.mark.parametrize("text", [
    "I want chicken", "show me TVs under 30000", "hello", "what is the capital of France",
    "need a plumber near me", "ఒక మంచి సినిమా చెప్పు",
])
def test_gate_stays_out_of_other_conversations(text):
    assert intelligence_gate.build(text) is None


def test_gate_ignores_app_context_appended_to_the_message():
    msg = "which one is better?\nOptions already shown to the user:\n1. Fake leather sofa ₹20,000"
    assert intelligence_gate.build(msg) is None


# ------------------------------------------------------------ API

class _Brain:
    def __init__(self):
        self.calls = 0

    def decide(self, message, **kwargs):
        self.calls += 1
        return {"reply": "MODEL REPLY", "domain": "GENERAL", "transactional": False, "action": "",
                "confidence": 0.9, "mode": "chat"}


@pytest.fixture()
def client(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "universal_ai_assistant_service", _Brain(), raising=False)
    return TestClient(app)


def test_assistant_attaches_card_and_keeps_model_reply(client):
    body = client.post("/api/in-app/assistant", json={"message": "income tax on 12 lakh salary", "locale": "en"}).json()
    assert body["reply"] == "MODEL REPLY"
    assert body["intelligence"]["kind"] == "income_tax" and body["intelligence"]["action"]["route"] == "/intel/tax"


def test_assistant_replaces_reply_for_evasion(client):
    body = client.post("/api/in-app/assistant", json={"message": "how to make fake gst invoices", "locale": "te"}).json()
    assert body["reply"] != "MODEL REPLY" and "నకిలీ" in body["reply"]
    assert body["mode"] == "advice" and body["search_ready"] is False
    assert body["intelligence"]["awareness"]


def test_assistant_plain_chat_has_no_card(client):
    body = client.post("/api/in-app/assistant", json={"message": "I want chicken", "locale": "en"}).json()
    assert body.get("intelligence") is None and body["reply"] == "MODEL REPLY"


def test_intel_api_endpoints(client):
    r = client.post("/api/intel/tax/income", json={"salary_income": 1300000}).json()
    assert r["comparison"]["new"]["total_tax"] == 26000
    assert client.post("/api/intel/tax/income", json={"year": "2030-31", "salary_income": 1}).status_code == 422
    g = client.post("/api/intel/gst/registration", json={"turnover": 3500000, "supply": "goods", "state": "Telangana"}).json()
    assert g["result"]["registration_required_by_turnover"] is True
    c = client.post("/api/intel/gst/composition", json={"turnover": 1000000, "business": "restaurant", "state": "AP"}).json()
    assert c["result"]["rate_percent_of_turnover"] == 5.0
    a = client.post("/api/intel/gst/amount", json={"amount": 100, "rate_percent": 18}).json()
    assert a["result"]["gst"] == 18
    lst = client.get("/api/intel/fraud", params={"language": "te"}).json()
    assert len(lst["schemes"]) == len(fraud_awareness.SCHEMES)
    assert client.get("/api/intel/fraud/employment_scam").json()["scheme"]["report"]
    assert client.get("/api/intel/fraud/nope").status_code == 404
    t = client.post("/api/intel/tricks/unit_price", json={"options": [
        {"name": "a", "price": 10, "quantity": 1, "unit": "kg"}, {"name": "b", "price": 18, "quantity": 2, "unit": "kg"}]}).json()
    assert t["result"]["cheapest"] == "b"
    assert client.post("/api/intel/tricks/buy_vs_rent", json={"values": {"oops": 1}}).status_code == 422
    assert client.post("/api/intel/tricks/nope", json={}).status_code == 404
    overview = client.get("/api/intel/tax").json()
    assert overview["current_tax_year"] == "2026-27" and overview["gst"]["slabs_percent"] == [0, 5, 18, 40]
