"""Things one applies for (a bank account, a loan, admission, a licence)
come back as links to the place to apply -- the named organisation's own site
first -- instead of being dropped because nothing on the page has a price.
Owner report 2026-11-09: "ICICI current account" showed only the branch, no link."""
from app.services.universal_external_result_service import (
    PAGE_APPLY,
    PAGE_ARTICLE,
    PAGE_INFO,
    PAGE_OFFICIAL,
    UniversalOnlineFallbackService,
    classify_page,
    is_official_site,
)


class FakeSearch:
    configured = True
    last_error = None

    def __init__(self, rows):
        self.rows, self.queries = rows, []

    def __call__(self, query, count):
        self.queries.append(query)
        return self.rows


ICICI = [
    {"url": "https://www.bankbazaar.com/current-account/icici.html", "title": "ICICI Current Account: how to apply",
     "snippet": "Compare rates"},
    {"url": "https://www.hdfcbank.com/sme/current-account", "title": "Open Current Account Online - HDFC Bank",
     "snippet": "Apply for a current account for your business"},
    {"url": "https://www.icicibank.com/business-banking/accounts/current-account",
     "title": "How to Open Current Account Online | ICICI Bank",
     "snippet": "Open an ICICI Bank current account online in minutes. Apply now."},
]


def test_the_named_organisations_own_page_is_the_place_to_act():
    subject = "ICICI bank current account opening"
    assert is_official_site("https://www.icicibank.com/x", subject)
    # Everyday words name no one: "bank" does not make bankbazaar / hdfcbank official.
    assert not is_official_site("https://www.bankbazaar.com/x", subject)
    assert not is_official_site("https://www.hdfcbank.com/x", subject)
    assert classify_page(ICICI[2]["url"], ICICI[2]["title"], ICICI[2]["snippet"], subject=subject) == PAGE_OFFICIAL
    assert classify_page(ICICI[1]["url"], ICICI[1]["title"], ICICI[1]["snippet"], subject=subject) == PAGE_APPLY
    # A comparison article stays an article; without a subject nothing changes.
    assert classify_page(ICICI[0]["url"], ICICI[0]["title"], ICICI[0]["snippet"], subject=subject) == PAGE_ARTICLE
    assert classify_page(ICICI[2]["url"], "ICICI Bank", "Welcome") == PAGE_INFO


def test_online_results_give_the_apply_links_official_first_and_search_for_applying():
    search = FakeSearch(ICICI)
    service = UniversalOnlineFallbackService(search)
    rows = service.online(category="banking", subject="ICICI bank current account opening", location_text="Vuyyuru")
    assert "apply online" in search.queries[0] and "price buy" not in search.queries[0]
    assert [r["page_type"] for r in rows] == [PAGE_OFFICIAL, PAGE_APPLY]
    assert rows[0]["destination_url"].startswith("https://www.icicibank.com/")
    assert service.status["online"] == "ok"


def test_works_the_same_for_any_kind_of_application():
    cases = [
        ("LIC jeevan policy", {"url": "https://www.licindia.in/plans/jeevan", "title": "LIC Jeevan policy - apply online",
                               "snippet": ""}),
        ("passport renewal", {"url": "https://www.passportindia.gov.in/renewal",
                              "title": "Passport renewal: register online", "snippet": ""}),
        ("engineering college admission", {"url": "https://admissions.example.ac.in/btech",
                                           "title": "Engineering college admission - apply now", "snippet": ""}),
    ]
    for subject, row in cases:
        rows = UniversalOnlineFallbackService(FakeSearch([row])).online(category="services", subject=subject)
        assert len(rows) == 1 and rows[0]["page_type"] in {PAGE_APPLY, PAGE_OFFICIAL}, subject
