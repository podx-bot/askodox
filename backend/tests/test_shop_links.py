"""Shop link (owner 2026-11-22): one free public page per shop, askodox.com/s/<slug> -- menu, WhatsApp order, call,
map, the shop's own UPI, counts only. Made-up numbers only (public repo)."""
from datetime import datetime, timezone
from urllib.parse import unquote

import pytest

from app.services.pos_store import PosError, PosStore
from app.services.shop_links import ShopLinks, clean_slug, slug_problem, ten_digits

OWNER = "app-phone-9400000301"
MANAGER_PHONE = "9400000302"
MANAGER = "app-phone-9400000302"


@pytest.fixture()
def env(tmp_path):
    now = [datetime(2026, 11, 23, 6, 0, tzinfo=timezone.utc)]
    store = PosStore(str(tmp_path / "pos.db"), clock=lambda: now[0])
    biz = store.create_business(OWNER, {"name": "Sai Tiffins", "template": "restaurant", "invoice_prefix": "ST",
                                        "state_code": "37", "registration_type": "unregistered",
                                        "phone": "9400000301", "address": "Main Road, Vuyyuru"})["id"]
    store.set_member(biz, OWNER, MANAGER_PHONE, "manager")
    menu = [{"id": "p1", "name": "Idli", "price_paise": 4000, "unit": "plate", "available": True},
            {"id": "p2", "name": "Chicken", "price_paise": 24000, "unit": "kg", "available": True},
            {"id": "p3", "name": "Vada", "price_paise": 3000, "unit": "plate", "available": False}]
    links = ShopLinks(store, menu=lambda conn, b: menu,
                      upi=lambda owner: {"upi_id": "saitiffins@okbank", "upi_link": "upi://pay?pa=saitiffins@okbank"},
                      clock=lambda: now[0])
    return store, links, biz, now


def test_slug_rules():
    assert clean_slug(" Sai Tiffins & Meals ") == "sai-tiffins-meals"
    assert clean_slug("--a__b..c--") == "a-b-c"
    assert slug_problem("ab") == "too_short"
    assert slug_problem("admin") == "reserved" and slug_problem("askodox-shop") == "reserved"
    assert slug_problem("sai-tiffins") == ""
    assert ten_digits("+91 94000 00301") == "9400000301" and ten_digits("12345") == ""


def test_owner_makes_the_link_manager_reads_it(env):
    store, links, biz, _ = env
    first = links.get(biz, OWNER)
    assert first["link"] is None and first["suggested_slug"] == "sai-tiffins" and first["has_upi"]
    assert links.get(biz, MANAGER)["can_change"] is False
    with pytest.raises(PosError) as refused:
        links.save(biz, MANAGER, {"slug": "sai-tiffins"})
    assert refused.value.status == 403
    saved = links.save(biz, OWNER, {"slug": "Sai Tiffins", "offer": "Sunday 10% off", "color": "maroon"})["link"]
    assert saved["slug"] == "sai-tiffins" and saved["url"].endswith("/s/sai-tiffins")
    assert saved["whatsapp"] == "9400000301"  # the shop phone by default
    with pytest.raises(PosError):
        links.save(biz, OWNER, {"offer": "visit bit.ly/abc for gifts"})
    with pytest.raises(PosError):
        links.save(biz, OWNER, {"color": "neon"})
    with pytest.raises(PosError) as outsider:
        links.get(biz, "app-phone-9999999990")
    assert outsider.value.status == 404


def test_slug_taken_and_old_name_keeps_working(env):
    store, links, biz, _ = env
    other = store.create_business("app-phone-9400000303", {"name": "Other", "template": "kirana", "invoice_prefix": "OT",
                                                            "state_code": "37", "registration_type": "unregistered"})["id"]
    links.save(biz, OWNER, {"slug": "sai-tiffins"})
    with pytest.raises(PosError) as taken:
        links.save(other, "app-phone-9400000303", {"slug": "sai-tiffins"})
    assert taken.value.status == 409
    assert links.get(other, "app-phone-9400000303")["suggested_slug"] == "other"
    links.save(biz, OWNER, {"slug": "sai-tiffins-vuyyuru"})
    assert links.resolve("sai-tiffins") == {"moved": "sai-tiffins-vuyyuru"}
    with pytest.raises(PosError):  # an old name stays this shop's (printed posters)
        links.save(other, "app-phone-9400000303", {"slug": "sai-tiffins"})


def test_public_page_order_and_counts(env):
    store, links, biz, _ = env
    links.save(biz, OWNER, {"slug": "sai-tiffins"})
    page = links.public("sai-tiffins")
    assert page["name"] == "Sai Tiffins" and page["can_order"] and page["upi_id"] == "saitiffins@okbank"
    order = links.order(page, {"p1": "2", "p2": "1.3", "p3": "4", "zz": "9"}, name="Ravi", note="parcel")
    assert [(l["id"], l["qty"]) for l in order["lines"]] == [("p1", 2.0), ("p2", 1.25)]  # sold out / unknown dropped
    assert order["total_paise"] == 8000 + 30000
    text = unquote(order["whatsapp_url"].split("text=", 1)[1])
    assert order["whatsapp_url"].startswith("https://wa.me/919400000301?") and "Ravi" in text and "₹380" in text
    links.count(biz, "view")
    links.count(biz, "view")
    links.count(biz, "nonsense")
    assert links.stats(biz, OWNER)["today"] == {"view": 2}
    links.save(biz, OWNER, {"enabled": False})
    assert links.public("sai-tiffins") is None and links.resolve("sai-tiffins") == {"off": True}


def test_paused_shop_shows_but_takes_no_orders_and_hidden_parts(env):
    store, links, biz, _ = env
    links.save(biz, OWNER, {"slug": "sai-tiffins", "show_pay": False, "show_call": False, "show_prices": False})
    store.set_status(biz, OWNER, "paused")
    page = links.public("sai-tiffins")
    assert page["can_order"] is False and page["upi_link"] == "" and page["phone"] == ""
    text = links.order({**page, "can_order": True}, {"p1": "1"})["text"]
    assert "₹" not in text  # prices hidden on the page -> none in the message


def test_routes_and_public_html(monkeypatch):
    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    rate_limit.reset_for_tests()
    for name in ("pos_store", "pos_frontdesk", "pos_bills", "shop_links"):
        monkeypatch.setattr(container, name, None, raising=False)
    client = TestClient(app)
    h = {"Authorization": f"Bearer {issue_token('app-phone-9411100081', container.settings.session_token_secret)}"}
    bid = client.post("/api/pos/businesses", headers=h, json={
        "name": "Ravi Kirana", "template": "kirana", "invoice_prefix": "RK", "state_code": "37",
        "registration_type": "unregistered", "phone": "9411100081", "address": "Bus stand road"}).json()["id"]
    assert client.post(f"/api/pos/businesses/{bid}/products", headers=h,
                       json={"name": "Sugar", "unit": "kg", "price_paise": 4800}).status_code == 200
    assert client.get(f"/api/pos/businesses/{bid}/link").status_code == 401
    got = client.get(f"/api/pos/businesses/{bid}/link", headers=h).json()
    assert got["link"] is None and got["suggested_slug"] == "ravi-kirana"
    assert client.get(f"/api/pos/businesses/{bid}/link/check?slug=admin", headers=h).json()["problem"] == "reserved"
    saved = client.put(f"/api/pos/businesses/{bid}/link", headers=h, json={"slug": "ravi-kirana", "offer": "Free delivery"})
    assert saved.status_code == 200, saved.text
    page = client.get("/s/ravi-kirana")
    assert page.status_code == 200 and "Ravi Kirana" in page.text and "Sugar" in page.text and "Free delivery" in page.text
    assert "script-src 'none'" in page.headers["content-security-policy"]
    product_id = page.text.split('name="q_', 1)[1].split('"', 1)[0]
    after = client.get(f"/s/ravi-kirana/order?q_{product_id}=2&via=wa&name=Ravi")
    assert after.status_code == 200 and "https://wa.me/919411100081?text=" in after.text
    empty = client.get("/s/ravi-kirana/order?via=wa")
    assert empty.status_code == 200 and "ఏమీ ఎంచుకోలేదు" in empty.text
    app_page = client.get(f"/s/ravi-kirana/order?q_{product_id}=1&via=app")
    assert app_page.status_code == 200 and "Play Store" in app_page.text
    go = client.get("/s/ravi-kirana/go/app", follow_redirects=False)
    assert go.status_code == 302 and go.headers["location"].startswith("https://play.google.com/store/apps/details?id=com.askodox.askodox")
    assert client.post("/s/ravi-kirana/c/call").status_code == 204
    stats = client.get(f"/api/pos/businesses/{bid}/link/stats", headers=h).json()["today"]
    assert stats["view"] >= 1 and stats["order_wa"] == 1 and stats["order_app"] == 1 and stats["app"] == 1
    assert client.get("/s/nobody-here").status_code == 404


def test_whatsapp_box_starts_with_the_owner_number_when_the_shop_has_no_phone(env):
    """Owner 2026-11-23: a shop made from the short setup card has no phone -> the WhatsApp box was empty."""
    store, links, _, now = env
    owner = "app-phone-9400000311"
    biz = store.create_business(owner, {"name": "No Phone Shop", "template": "kirana", "invoice_prefix": "NP",
                                        "state_code": "37", "registration_type": "unregistered"})["id"]
    store.set_member(biz, owner, "9400000312", "manager")
    assert links.get(biz, owner)["whatsapp_default"] == "9400000311"
    assert links.get(biz, "app-phone-9400000312")["whatsapp_default"] == ""  # the owner's number only to the owner
    assert links.save(biz, owner, {"slug": "no-phone-shop"})["link"]["whatsapp"] == "9400000311"
    assert links.save(biz, owner, {"whatsapp": ""})["link"]["whatsapp"] == ""  # cleared on purpose stays cleared
