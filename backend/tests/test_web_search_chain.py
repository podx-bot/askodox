"""Online discovery never depends on Brave alone (web-search chain)."""
import pytest
from fastapi.testclient import TestClient

from app.services.web_search_chain import GoogleCseProvider, WebSearchChain, build_chain


class _Provider:
    configured = True

    def __init__(self, name, rows=None, error=False, stale=None):
        self.name, self.rows, self.error, self.stale = name, rows or [], error, stale
        self.calls = 0
        self.last_error = False
        self.last_stale_at = None

    def __call__(self, query, limit):
        self.calls += 1
        self.last_error = self.error
        self.last_stale_at = self.stale
        return [] if self.error else list(self.rows)

    def videos(self, query, limit):
        return []


ROW = {"title": "Walking shoes men", "url": "https://shop.example/w", "snippet": "Walking shoes Rs. 1,499"}


def test_next_provider_only_when_the_previous_one_failed():
    brave, cse = _Provider("brave", error=True), _Provider("google_cse", rows=[ROW])
    chain = WebSearchChain([brave, cse])
    assert chain("walking shoes", 5) == [ROW]
    assert chain.last_provider == "google_cse" and not chain.last_error


def test_an_honest_empty_answer_is_not_a_failure():
    brave, cse = _Provider("brave", rows=[]), _Provider("google_cse", rows=[ROW])
    chain = WebSearchChain([brave, cse])
    assert chain("walking shoes", 5) == []
    assert cse.calls == 0, "the fallback is not called when the primary answered (even with nothing)"


def test_every_provider_failing_is_reported_as_a_failure_never_fabricated():
    chain = WebSearchChain([_Provider("brave", error=True), _Provider("google_cse", error=True)])
    assert chain("walking shoes", 5) == []
    assert chain.last_error is True


def test_a_live_answer_beats_the_primary_stale_copy():
    brave = _Provider("brave", rows=[dict(ROW, title="old")], stale="2026-10-01T00:00:00")
    cse = _Provider("google_cse", rows=[ROW])
    chain = WebSearchChain([brave, cse])
    assert chain("walking shoes", 5) == [ROW] and chain.last_stale_at is None
    chain_no_live = WebSearchChain([brave, _Provider("google_cse", error=True)])
    rows = chain_no_live("walking shoes", 5)
    assert rows[0]["title"] == "old" and chain_no_live.last_stale_at == "2026-10-01T00:00:00"


def test_google_cse_maps_rows_and_reports_quota_as_error():
    calls = []

    def ok(url, params, timeout):
        calls.append(params)
        return {"items": [{"link": "https://shop.example/w", "title": "Walking shoes", "snippet": "Rs 1,499",
                           "displayLink": "shop.example",
                           "pagemap": {"cse_thumbnail": [{"src": "https://img.example/t.jpg"}]}}]}

    cse = GoogleCseProvider("k", "cx", http_get=ok)
    rows = cse("walking shoes", 5)
    assert rows[0]["url"] == "https://shop.example/w" and rows[0]["thumbnail"] == "https://img.example/t.jpg"
    assert calls[0]["gl"] == "in" and not cse.last_error

    def quota(url, params, timeout):
        raise RuntimeError("HTTP 429")

    failing = GoogleCseProvider("k", "cx", http_get=quota)
    assert failing("walking shoes", 5) == [] and failing.last_error
    assert not GoogleCseProvider("", "").configured


def test_build_chain_reads_backend_only_env_names_and_stays_brave_only_without_them():
    primary = _Provider("brave")
    chain = build_chain(primary, {"GOOGLE_CSE_API_KEY": "k", "GOOGLE_CSE_ID": "cx"})
    assert chain.providers[0] is primary and chain.providers[1].configured
    bare = build_chain(primary, {})
    assert not bare.providers[1].configured


@pytest.fixture()
def client(monkeypatch, tmp_path):
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "chain.db"))
    from server import app, container

    class _NoMaps:
        enabled = False

    monkeypatch.setattr(container, "google_maps_service", _NoMaps())
    return container, TestClient(app)


def _discover(client):
    body = {"user_id": "guest", "raw_text": "walking shoes", "subject": "walking shoes", "intent": "buy",
            "category": "PRODUCT", "trace": {"query": "walking shoes"}}
    response = client.post("/deals/discover", json=body)
    assert response.status_code == 200, response.text
    return response.json()


def test_brave_out_of_credit_online_results_still_come_from_the_fallback(client, monkeypatch):
    container, http = client
    brave = _Provider("brave", error=True)
    monkeypatch.setattr(container, "brave_web_search_provider", brave)
    monkeypatch.setattr(container, "web_search_chain", WebSearchChain([brave, _Provider("google_cse", rows=[ROW])]))
    body = _discover(http)
    online = next(s for s in body["sections"] if s["kind"] == "online")
    assert online["count"] >= 1, body["source_status"]
    assert body["source_status"]["online"] == "ok"


def test_brave_down_and_no_fallback_the_staff_catalog_still_answers(client, monkeypatch):
    container, http = client
    from app.api.routes.affiliate_catalog import catalog

    catalog(container).create({"title": "Walking shoes for men", "item_type": "product", "platform": "amazon",
                               "original_product_url": "https://www.amazon.in/dp/B0WALK0002"},
                              actor="staff:test", commission_status="inactive")
    brave = _Provider("brave", error=True)
    monkeypatch.setattr(container, "brave_web_search_provider", brave)
    monkeypatch.setattr(container, "web_search_chain", WebSearchChain([brave, _Provider("google_cse", error=True)]))
    body = _discover(http)
    kinds = {s["kind"]: s for s in body["sections"]}
    assert kinds["online"]["count"] >= 1, "a LIVE catalog item is shown organically while web search is down"
    assert "online" in body["answer"]["unavailable"] or body["source_status"]["online"] == "error"
