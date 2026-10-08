"""A provider failure is never an honest "no results": quota / rate limit /
auth failures reach the source status (and the app) by name."""
import httpx
import pytest

from app.services import external_call_budget
from app.services.brave_web_search_provider import BraveWebSearchProvider
from app.services.provider_failure import failure_kind
from app.services.result_orchestrator import build
from app.services.universal_external_result_service import UniversalOnlineFallbackService
from app.services.universal_multi_source_result_service import UniversalMultiSourceResultService
from app.services.web_search_chain import WebSearchChain


def _resp(status, body):
    return httpx.Response(status, json=body,
                          request=httpx.Request("GET", "https://api.search.brave.com/res/v1/web/search"))


class _Client:
    def __init__(self, *responses):
        self.responses = list(responses)

    def get(self, url, headers=None, params=None):
        return self.responses.pop(0) if self.responses else _resp(500, {})


CREDIT = {"type": "ErrorResponse", "error": {"code": "CREDIT_EXHAUSTED"}}
OK = {"web": {"results": [{"url": "https://www.amazon.in/dp/B0X", "title": "Laptop", "description": "Laptop"}]}}


@pytest.fixture(autouse=True)
def _clean():
    external_call_budget.reset_for_tests()
    yield
    external_call_budget.reset_for_tests()


def test_brave_names_the_failure_kind_and_a_success_clears_it():
    brave = BraveWebSearchProvider("k", client=_Client(_resp(402, CREDIT)))
    assert brave("laptop", 5) == []
    assert brave.last_error and brave.last_error_kind == "quota_exhausted"
    # Breaker open: still the quota, not a generic error.
    assert brave("something else", 5) == [] and brave.last_error_kind == "quota_exhausted"
    assert failure_kind(brave) == "quota_exhausted"

    auth = BraveWebSearchProvider("k", client=_Client(_resp(401, {"error": {"code": "SUBSCRIPTION_TOKEN_INVALID"}})))
    auth("laptop", 5)
    assert failure_kind(auth) == "auth_failed"

    ok = BraveWebSearchProvider("k", client=_Client(_resp(200, OK)))
    assert ok("laptop", 5) and ok.last_error_kind is None and failure_kind(ok) is None


class _Down:
    """A web search whose last call failed for [kind]."""
    configured = True

    def __init__(self, kind):
        self.last_error = True
        self.last_error_kind = kind
        self.last_stale_at = None

    def __call__(self, query, limit):
        return []


class _Empty(_Down):
    def __init__(self):
        super().__init__(None)
        self.last_error = False


def test_chain_keeps_the_primary_reason_when_the_fallback_is_not_configured():
    class _Off:
        configured = False

    chain = WebSearchChain([_Down("quota_exhausted"), _Off()])
    assert chain("laptop", 5) == [] and chain.last_error and chain.last_error_kind == "quota_exhausted"
    assert failure_kind(WebSearchChain([_Empty()])) is None


@pytest.mark.parametrize("kind", ["quota_exhausted", "rate_limited", "auth_failed"])
def test_online_status_names_the_provider_failure(kind):
    service = UniversalOnlineFallbackService(_Down(kind))
    assert service.online(category="", subject="laptop") == []
    assert service.status["online"] == kind


def test_unknown_failure_is_error_and_an_honest_empty_answer_is_no_results():
    service = UniversalOnlineFallbackService(_Down("bad_request"))
    service.online(category="", subject="laptop")
    assert service.status["online"] == "error"
    empty = UniversalOnlineFallbackService(_Empty())
    empty.online(category="", subject="laptop")
    assert empty.status["online"] == "no_results"


def test_used_and_deals_status_is_the_failure_not_no_results():
    service = UniversalMultiSourceResultService(web_search=_Down("quota_exhausted"))
    service.collect({"subject": "laptop", "domain": "electronics"})
    assert service.source_status()["used_deals"] == "quota_exhausted"
    honest = UniversalMultiSourceResultService(web_search=_Empty())
    honest.collect({"subject": "laptop", "domain": "electronics"})
    assert honest.source_status()["used_deals"] == "no_results"


def test_orchestrator_lists_provider_failures_as_unavailable():
    out = build([], demand={"subject": "laptop"},
                      source_status={"online": "quota_exhausted", "jobs": "rate_limited", "askodox": "no_results"})
    assert out["answer"]["unavailable"] == ["jobs", "online"]
    assert out["answer"]["may_claim_results"] is False
