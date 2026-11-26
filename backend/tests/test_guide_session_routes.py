"""Routes need a sign-in; the console inbox needs staff."""
from fastapi.testclient import TestClient


def test_routes_refuse_without_sign_in():
    from server import app

    client = TestClient(app)
    for method, path in (("get", "/api/me/guide-session"), ("post", "/api/me/guide-session/start"),
                         ("get", "/api/me/guide-reminders"), ("post", "/api/me/feature-requests"),
                         ("get", "/admin/cc/feature-requests")):
        resp = getattr(client, method)(path)
        assert resp.status_code in (401, 403, 422), (path, resp.status_code)
