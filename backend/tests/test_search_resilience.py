"""Brave failures are recorded with the real cause, paced/retried, broken
off while a quota is exhausted, and the last REAL answer is served stale."""
import threading

import httpx
import pytest

from app.services import external_call_budget
from app.services.brave_web_search_provider import BraveWebSearchProvider, LastGoodStore


def _resp(status, body, headers=None):
    return httpx.Response(status, json=body, headers=headers or {},
                          request=httpx.Request("GET", "https://api.search.brave.com/res/v1/web/search"))


class _Client:
    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = 0

    def get(self, url, headers=None, params=None):
        self.calls += 1
        return self.responses.pop(0) if self.responses else self.last

    @property
    def last(self):
        return _resp(500, {})


OK = {"web": {"results": [{"url": "https://www.amazon.in/dp/B0X", "title": "Running Shoes",
                           "description": "Lightweight running shoes"}]}}
QUOTA = {"type": "ErrorResponse", "error": {"code": "USAGE_LIMIT_EXCEEDED", "detail": "monthly limit"}}
RATE = {"type": "ErrorResponse", "error": {"code": "RATE_LIMITED"}}


@pytest.fixture(autouse=True)
def _clean():
    external_call_budget.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


def test_quota_exhaustion_is_recorded_breaks_the_circuit_and_serves_last_good(tmp_path):
    store = LastGoodStore(str(tmp_path / "s.db"))
    ok = _Client([_resp(200, OK, {"X-RateLimit-Limit": "20, 2000", "X-RateLimit-Remaining": "19, 1",
                                  "X-RateLimit-Reset": "1, 3600"})])
    provider = BraveWebSearchProvider("k", client=ok)
    provider.attach_store(store)
    assert provider("running shoes", 5)[0]["title"] == "Running Shoes"
    assert provider.health_snapshot()["state"] == "ok"

    external_call_budget.reset_for_tests()  # new process: no in-memory cache
    down = _Client([_resp(429, QUOTA, {"X-RateLimit-Limit": "20, 2000", "X-RateLimit-Remaining": "19, 0",
                                       "X-RateLimit-Reset": "1, 7200"})])
    provider.client = down
    rows = provider("running shoes", 5)
    snap = provider.health_snapshot()
    assert snap["state"] == "quota_exhausted" and snap["http_status"] == 429
    assert snap["provider_code"] == "USAGE_LIMIT_EXCEEDED" and snap["paused_for_seconds"] > 0
    # The last REAL answer, labelled stale; not an error.
    assert rows and rows[0]["title"] == "Running Shoes"
    assert provider.last_stale_at and provider.last_error is False
    # Circuit open: Brave is not called again until the reset.
    calls = down.calls
    assert provider("something never searched", 5) == []
    assert down.calls == calls and provider.last_error is True


def test_per_second_limit_is_retried_once():
    client = _Client([_resp(429, RATE, {"X-RateLimit-Limit": "1, 2000", "X-RateLimit-Remaining": "0, 1500",
                                        "X-RateLimit-Reset": "1, 9000"}),
                      _resp(200, OK, {"X-RateLimit-Limit": "1, 2000"})])
    provider = BraveWebSearchProvider("k", client=client)
    assert provider("running shoes", 5) and client.calls == 2
    assert provider.health_snapshot()["state"] == "ok"


def test_bad_key_is_named_and_errors_are_per_thread():
    client = _Client([_resp(401, {"type": "ErrorResponse", "error": {"code": "SUBSCRIPTION_TOKEN_INVALID"}})])
    provider = BraveWebSearchProvider("k", client=client)
    assert provider("x", 3) == [] and provider.last_error is True
    assert provider.health_snapshot()["state"] == "auth_failed"
    seen = {}
    t = threading.Thread(target=lambda: seen.setdefault("other", provider.last_error))
    t.start(); t.join()
    assert seen["other"] is False  # another source's thread is not marked failed


def test_public_search_health_never_leaks_the_key():
    from fastapi.testclient import TestClient
    from server import app

    data = TestClient(app).get("/health/search").json()
    assert "state" in data and "k" not in str(data.get("provider_code") or "")
    assert "web_search" in TestClient(app).get("/readiness").json()


def test_production_402_credit_exhausted_opens_the_breaker():
    """The exact answer production got on 2026-10-04 (probe run 37172903519)."""
    body = {"type": "ErrorResponse", "error": {"code": "CREDIT_EXHAUSTED", "detail": "credits used up"}}
    client = _Client([_resp(402, body, {"X-RateLimit-Limit": "50, 0", "X-RateLimit-Remaining": "45, 0",
                                        "X-RateLimit-Reset": "1, 2408219"})])
    provider = BraveWebSearchProvider("k", client=client)
    assert provider("washing machine", 5) == [] and provider.last_error is True
    snap = provider.health_snapshot()
    assert snap["state"] == "quota_exhausted" and snap["http_status"] == 402
    assert snap["provider_code"] == "CREDIT_EXHAUSTED" and snap["paused_for_seconds"] > 3600
    calls = client.calls
    assert provider("face sunscreen", 5) == [] and client.calls == calls, "no more paid calls while exhausted"
