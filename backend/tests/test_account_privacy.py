"""Privacy actions are real: data export and confirmed account deletion."""
import uuid

from fastapi.testclient import TestClient

from app.services.session_tokens import issue_token


def _auth(container, user):
    return {"Authorization": f"Bearer {issue_token(user, container.settings.session_token_secret)}"}


def test_export_and_delete_my_account():
    from server import app, container

    client = TestClient(app)
    user = "app-phone-91" + str(uuid.uuid4().int)[:10]
    headers = _auth(container, user)
    listed = client.post("/api/products/mine", headers=headers,
                         json={"seller_user_id": user, "subject": "privacy test mixer grinder", "price": 3000})
    assert listed.status_code == 200, listed.text

    assert client.get("/api/me/export").status_code == 401
    export = client.get("/api/me/export", headers=headers).json()
    assert export["user_id"] == user
    assert any(row.get("subject") == "privacy test mixer grinder" for row in export["data"].get("seller_products", []))
    assert "token" not in str(export).lower().split("seller_products")[0]

    # Deletion needs an explicit confirmation.
    assert client.delete("/api/me?confirm=yes", headers=headers).status_code == 422
    done = client.delete("/api/me?confirm=DELETE", headers=headers).json()
    assert done["deleted"] is True and done["listings_removed"] == 1

    # The old session no longer works; the listing is no longer searchable.
    assert client.get("/api/me/export", headers=headers).status_code == 401
    assert not container.product_catalog_repository.search_active("privacy test mixer grinder")


def test_seller_removes_only_their_own_listing():
    from server import app, container

    client = TestClient(app)
    seller, other = ("app-phone-91" + str(uuid.uuid4().int)[:10] for _ in range(2))
    listing = client.post("/api/products/mine", headers=_auth(container, seller),
                          json={"seller_user_id": seller, "subject": "remove test pressure cooker"}).json()["id"]
    assert client.delete(f"/api/products/mine/{listing}", headers=_auth(container, other)).status_code == 404
    assert client.delete(f"/api/products/mine/{listing}").status_code == 401
    assert client.delete(f"/api/products/mine/{listing}", headers=_auth(container, seller)).json()["removed"] is True
    assert client.get("/api/products/mine", headers=_auth(container, seller)).json()["items"] == []
