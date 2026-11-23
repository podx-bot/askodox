"""Customer list grows by itself (owner 2026-11-24): orders / sent bills suggest people, a tap saves, ✕ hides."""
import sqlite3

import pytest

from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000401"
STRANGER = "app-phone-9400000402"


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    shop = store.create_business(OWNER, {"name": "Lakshmi Tiffins", "state_code": "37"})["id"]
    conn = sqlite3.connect(store.db_path)
    conn.executescript(
        "CREATE TABLE IF NOT EXISTS pos_desk_orders (id TEXT, business_id TEXT, source TEXT, customer_name TEXT,"
        " customer_phone TEXT, placed_at TEXT);"
        "CREATE TABLE IF NOT EXISTS pos_bill_shares (token TEXT, business_id TEXT, phone_key TEXT, created_at TEXT);")
    conn.executemany("INSERT INTO pos_desk_orders (id, business_id, source, customer_name, customer_phone, placed_at)"
                     " VALUES (?,?,?,?,?,?)",
                     [("o1", shop, "shop_link", "Ramu", "+91 98480 11111", "2026-11-20"),
                      ("o2", shop, "counter", "Ramu", "9848011111", "2026-11-22"),
                      ("o3", shop, "app", "Sita", "9848022222", "2026-11-21"),
                      ("o4", "other-shop", "app", "Other", "9848099999", "2026-11-21")])
    conn.execute("INSERT INTO pos_bill_shares VALUES ('t1', ?, '9848033333', '2026-11-23')", (shop,))
    conn.execute("INSERT INTO pos_bill_shares VALUES ('t2', ?, '9848011111', '2026-11-23')", (shop,))
    conn.commit()
    conn.close()
    return store, shop


def test_people_who_ordered_or_got_a_bill_are_suggested_most_seen_first(env):
    store, shop = env
    rows = store.customer_suggestions(shop, OWNER)
    assert [r["phone"] for r in rows] == ["9848011111", "9848033333", "9848022222"]
    assert rows[0]["name"] == "Ramu" and rows[0]["times"] == 3 and set(rows[0]["sources"]) == {"order", "bill"}
    assert "9848099999" not in [r["phone"] for r in rows], "another shop's customers never show"


def test_saved_and_skipped_numbers_stop_showing(env):
    store, shop = env
    store.add_customer(shop, OWNER, {"name": "Ramu", "phone": "9848011111"})
    store.skip_customer_suggestion(shop, OWNER, "98480 22222")
    assert [r["phone"] for r in store.customer_suggestions(shop, OWNER)] == ["9848033333"]


def test_only_the_shop_people_see_suggestions(env):
    store, shop = env
    with pytest.raises(PosError):
        store.customer_suggestions(shop, STRANGER)
    with pytest.raises(PosError):
        store.skip_customer_suggestion(shop, OWNER, "123")
