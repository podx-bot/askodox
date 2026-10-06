"""Price provenance + budget truth: MRP / offer / bank-card / starting-from /
page prices are told apart; a conditional price is never the row's price;
'only 40,000 or below' removes over-budget rows; non-strict budgets rank."""
import dataclasses

from fastapi.testclient import TestClient

from app.services import price_truth as pt


def test_classify_distinguishes_price_kinds():
    a = pt.classify("Reliance Digital: Voltas 1.5T ₹41,490 ₹36,433* with SBI credit card")
    assert (a["price"], a["price_kind"], a["offer_price"]) == (41490, "page_level", 36433)
    assert "sbi credit card" in a["offer_condition"]
    b = pt.classify("Voltas 1.5 Ton ₹42,990 M.R.P: ₹67,990")
    assert (b["price"], b["list_price"]) == (42990, 67990)
    assert pt.classify("LG AC starting from ₹31,990")["price_kind"] == "starting_from"
    assert pt.classify("Samsung ACs ₹29,990 onwards")["price_kind"] == "starting_from"
    assert pt.classify("Deal price: ₹39,990 M.R.P.: ₹64,990")["price_kind"] == "offer"
    c = pt.classify("Buy AC online, ₹38,490 with bank offer. MRP ₹59,000")
    assert c["price"] is None and c["offer_price"] == 38490, "conditional only -> no normal price claimed"
    assert pt.classify("no price here")["price"] is None


def test_budget_fit_states():
    assert pt.budget_fit({"price": 38990}, 40000) == "within"
    assert pt.budget_fit({"price": 41490, "offer_price": 36433}, 40000) == "within_with_offer"
    assert pt.budget_fit({"price": 42990}, 40000) == "over"
    assert pt.budget_fit({"price": 31990, "price_kind": "starting_from"}, 40000) == "unknown"
    assert pt.budget_fit({"price": None}, 40000) == "unknown"
    assert pt.is_strict("AC 40000 or below only") and not pt.is_strict("AC under 40000")


def test_annotate_strict_removes_and_ranks():
    rows = [{"id": "a", "price": 42990, "source": "online"}, {"id": "b", "price": None, "source": "online"},
            {"id": "c", "price": 41490, "offer_price": 36433, "source": "online"},
            {"id": "d", "price": 38990, "source": "online"}, {"id": "v", "source": "video"}]
    out = pt.annotate([dict(r) for r in rows], budget_max=40000, strict=False)
    assert [r["id"] for r in out["kept"]] == ["v", "d", "c", "b", "a"] or \
        [r["id"] for r in out["kept"] if r["id"] != "v"] == ["d", "c", "b", "a"]
    strict = pt.annotate([dict(r) for r in rows], budget_max=40000, strict=True)
    assert "a" not in [r["id"] for r in strict["kept"]]
    assert strict["rejected"][0]["reason"] == "over_budget_strict"


class _Web:
    configured = True
    last_error = False

    def __call__(self, query, limit):
        return [
            {"title": "Voltas 1.5 Ton 3 Star Inverter Split AC", "url": "https://www.croma.com/voltas-1-5-ton-ac/p/1",
             "snippet": "Voltas 1.5 Ton AC ₹42,990 M.R.P: ₹67,990"},
            {"title": "Voltas 1.5T Inverter AC", "url": "https://www.reliancedigital.in/voltas-1-5t-ac/p/2",
             "snippet": "₹41,490 ₹36,433* with SBI credit card"},
            {"title": "Lloyd 1.5 Ton Inverter AC", "url": "https://www.vijaysales.com/lloyd-1-5-ton-ac/p/3",
             "snippet": "Lloyd 1.5 Ton Inverter ₹36,990"},
        ]


def _discover(client, said):
    body = {"user_id": "", "raw_text": said, "intent": "buy", "subject": "1.5 ton inverter AC", "category": "electronics",
            "location": {"label": "Vijayawada"}, "dynamic_fields": {"budget_max": 40000}, "trace": {"query": said}}
    r = client.post("/deals/discover", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def test_discovery_labels_prices_and_honours_strict_budget(monkeypatch, tmp_path):
    from server import app, container

    monkeypatch.setattr(container, "settings", dataclasses.replace(container.settings,
                                                                   database_path=str(tmp_path / "p.db")))
    monkeypatch.setattr(container, "brave_web_search_provider", _Web())
    client = TestClient(app)
    data = _discover(client, "1.5 ton inverter AC under 40000")
    online = {m["title"]: m for m in data["matches"] if m.get("source") == "online"}
    assert online, data.get("errors")
    reliance = next(m for t, m in online.items() if "Voltas 1.5T" in t)
    assert reliance["price"] == 41490 and reliance["offer_price"] == 36433
    assert reliance["budget_fit"] == "within_with_offer"
    croma = next(m for t, m in online.items() if "3 Star" in t)
    assert croma["budget_fit"] == "over" and croma["list_price"] == 67990
    strict = _discover(client, "1.5 ton inverter AC 40000 or below only")
    titles = [m["title"] for m in strict["matches"]]
    assert not any("3 Star" in t for t in titles), "over-budget row removed when strict"
    assert any(r["reason"] == "over_budget_strict" for r in strict["rejected"])
