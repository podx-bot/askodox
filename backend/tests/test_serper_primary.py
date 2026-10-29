"""Serper first, Brave second (owner decision 2026-10-29). Serper failures
(credits, key, outage) move the chain to Brave; an honest empty answer does
not. Rows keep the Brave row shape, carry dates from "N days ago", and news
(topStories) is included. Without a key the old order stays."""
from datetime import datetime, timezone
from types import SimpleNamespace

from app.services import external_call_budget
from app.services.serper_web_search_provider import SerperWebSearchProvider, parse_date
from app.services.web_search_chain import build_chain


class Resp:
    def __init__(self, status, payload=None, text=""):
        self.status_code, self._payload, self.text = status, payload or {}, text

    def json(self):
        return self._payload


PAYLOAD = {
    "organic": [{"title": "OPPO Find X10 - Official", "link": "https://www.oppo.com/in/find-x10/",
                 "snippet": "Find X10 series.", "date": "Oct 22, 2026"},
                {"title": "no snippet", "link": "https://x.example/"}],
    "topStories": [{"title": "Find X10 launched in India", "link": "https://news.example/x10",
                    "source": "News Example", "date": "3 days ago", "imageUrl": "https://img.example/a.jpg"}],
    "credits": 2400,
}


class Brave:
    name = "brave"
    configured = True
    last_error = False
    last_stale_at = None

    def __init__(self, rows):
        self.rows, self.calls = rows, 0

    def __call__(self, q, n):
        self.calls += 1
        return list(self.rows)


def setup_function():
    external_call_budget.reset_for_tests() if hasattr(external_call_budget, "reset_for_tests") else None


def test_parse_dates_never_guess():
    now = datetime(2026, 10, 29, tzinfo=timezone.utc)
    assert parse_date("3 days ago", now).startswith("2026-10-26")
    assert parse_date("Oct 22, 2026").startswith("2026-10-22")
    assert parse_date("sometime") is None and parse_date("") is None


def test_rows_have_the_brave_shape_with_news_and_dates():
    sent = []

    def post(url, json, headers, timeout):
        sent.append((url, json, headers))
        return Resp(200, PAYLOAD)

    provider = SerperWebSearchProvider("k-1", http_post=post)
    rows = provider("Oppo Find X10 unique-a", 5)
    assert [r["url"] for r in rows] == ["https://www.oppo.com/in/find-x10/", "https://news.example/x10"]
    assert rows[1]["source_type"] == "news" and rows[1]["published_at"] and rows[1]["snippet"] == "News Example"
    assert sent[0][1]["gl"] == "in" and sent[0][2]["X-API-KEY"] == "k-1"
    assert provider.last_error is False and provider.health["state"] == "ok"
    assert provider.health_snapshot()["credits_left"] == 2400


def test_serper_failure_moves_the_chain_to_brave_but_an_empty_answer_does_not():
    brave = Brave([{"title": "b", "url": "https://b.example", "snippet": "s"}])
    no_credit = SerperWebSearchProvider("k", http_post=lambda *a, **k: Resp(400, text="Not enough credits"))
    chain = build_chain(brave, env={}, serper=no_credit)
    assert [getattr(p, "name", "") for p in chain.providers][:2] == ["serper", "brave"]
    assert chain("tractor unique-b", 3)[0]["url"] == "https://b.example" and chain.last_provider == "brave"
    assert no_credit.health["state"] == "quota_exhausted" and no_credit.health_snapshot()["paused_for_seconds"] > 0
    empty = SerperWebSearchProvider("k", http_post=lambda *a, **k: Resp(200, {"organic": []}))
    chain2 = build_chain(Brave([{"title": "b", "url": "https://b.example", "snippet": "s"}]), env={}, serper=empty)
    assert chain2("nothing unique-c", 3) == [] and chain2.last_error is False, "honest empty is not a failure"
    bad_key = SerperWebSearchProvider("k", http_post=lambda *a, **k: Resp(403, text="Unauthorized"))
    bad_key("q unique-d", 2)
    assert bad_key.health["state"] == "auth_failed" and bad_key.last_error_kind == "auth_failed"


def test_without_a_key_brave_stays_primary():
    brave = Brave([])
    chain = build_chain(brave, env={})
    assert chain.primary is brave
    chain_with_key = build_chain(brave, env={"SERPER_API_KEY": "abc"})
    assert getattr(chain_with_key.primary, "name", "") == "serper"


def test_discovery_and_live_research_use_the_chain():
    from app.api.routes.universal_deals import _web_search

    brave = Brave([])
    serper = SerperWebSearchProvider("k", http_post=lambda *a, **k: Resp(200, PAYLOAD))
    chain = build_chain(brave, env={}, serper=serper)
    container = SimpleNamespace(brave_web_search_provider=brave, web_search_chain=chain)
    assert _web_search(container) is chain
    container.brave_web_search_provider = Brave([])  # a test replaced Brave alone
    assert _web_search(container) is container.brave_web_search_provider
