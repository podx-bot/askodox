"""Customer web chat is served by the backend and uses the same APIs as the app."""
from fastapi.testclient import TestClient


def test_web_chat_page_uses_the_shared_backend():
    from server import app

    r = TestClient(app).get("/chat")
    assert r.status_code == 200 and "text/html" in r.headers["content-type"]
    html = r.text
    for api in ("/api/in-app/assistant", "/deals/discover"):
        assert api in html
    assert "advisor_asked" in html and "no_preference" in html  # same advisor memory as the app
    assert "Sponsored" in html and "affiliate" in html.lower()  # one global disclosure
    assert "innerHTML=esc" not in html and "esc(x.title)" in html  # result text is escaped


def test_web_chat_asks_the_home_page_question_and_has_a_strict_csp():
    from server import app

    r = TestClient(app).get("/chat?q=car")
    csp = r.headers["content-security-policy"]
    assert "connect-src 'self'" in csp and "frame-ancestors 'none'" in csp
    assert "URLSearchParams(location.search).get(\"q\")" in r.text
