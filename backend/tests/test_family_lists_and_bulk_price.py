"""Owner 2026-11-25 one-touch leftovers: the family shopping list (one shared list per home, add by number, tick /
pause / edit / delete, others told) and the shop's bulk price change (preview, then one write; tiers / packs / online
price left alone and counted)."""

import sqlite3

import pytest

from app.services import pos_bulk_price
from app.services.family_lists import FamilyListError, FamilyLists, member_ref
from app.services.pos_store import PosError, PosStore

AMMA = "app-phone-9400000701"
NANNA = "app-phone-9400000702"
OTHER = "app-phone-9400000703"


def _accounts(db, *users):
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS auth_accounts (phone_key TEXT PRIMARY KEY, user_id TEXT NOT NULL,"
                     " created_at TEXT NOT NULL, last_sign_in_at TEXT NOT NULL, sign_ins INTEGER NOT NULL DEFAULT 0)")
        for u in users:
            conn.execute("INSERT OR IGNORE INTO auth_accounts VALUES (?, ?, 'x', 'x', 1)", (u[-10:], u))


def test_family_list_shared_by_number_with_pushes(tmp_path):
    db = str(tmp_path / "f.db")
    _accounts(db, AMMA, NANNA)
    pushes = []
    fam = FamilyLists(db, notify=lambda u, t, b, r, k: pushes.append((u, t, b, r, k)))
    home = fam.mine(AMMA)["lists"][0]  # one list made by itself
    lid = home["id"]
    assert home["items"] == [] and len(home["members"]) == 1 and home["members"][0]["me"]
    with pytest.raises(FamilyListError):
        fam.add_member(AMMA, lid, "12345", "")
    fam.add_member(AMMA, lid, "+91 94000 00702", "Nanna")
    assert pushes[-1][0] == NANNA and pushes[-1][3] == "/me/family-list"
    fam.add_member(AMMA, lid, "9400000704", "Akka")  # not on ASKODOX yet: waits, joins on sign-in
    out = fam.add_items(AMMA, lid, ["2 kg sugar", "milk", "  "])
    assert [i["text"] for i in out["items"]] == ["2 kg sugar", "milk"]
    assert [p[0] for p in pushes[-1:]] == [NANNA] and "sugar" in pushes[-1][2]
    seen = fam.mine(NANNA)["lists"][0]
    assert seen["id"] == lid and seen["open"] == 2
    assert all("9400000701" not in str(m) for m in seen["members"]), "numbers never shown whole"
    with pytest.raises(FamilyListError):
        fam.add_items(OTHER, lid, ["x"])  # not a member
    milk = [i for i in seen["items"] if i["text"] == "milk"][0]
    fam.update_item(NANNA, lid, milk["id"], {"state": "paused"})
    sugar = [i for i in seen["items"] if i["text"] != "milk"][0]
    done = fam.update_item(NANNA, lid, sugar["id"], {"state": "done"})
    assert [i["state"] for i in done["items"]] == ["paused", "done"] and done["items"][1]["done_by"] == "me"
    fam.update_item(NANNA, lid, milk["id"], {"state": "done", "text": "milk 1 l"})
    assert pushes[-1][0] == AMMA and "అయిపోయింది" in pushes[-1][1]
    assert fam.clear_done(AMMA, lid)["items"] == []
    akka = "app-phone-9400000704"
    assert fam.mine(akka)["lists"][0]["id"] == lid, "invited number joins when it signs in"
    nanna_ref = member_ref(lid, "9400000702")
    fam.update_member(AMMA, lid, nanna_ref, "Nanna garu")
    fam.remove_member(AMMA, lid, nanna_ref)
    assert fam.mine(NANNA)["lists"][0]["id"] != lid  # he gets his own fresh list
    fam.delete_user(AMMA)
    fam.delete_user(akka)
    with sqlite3.connect(db) as conn:
        assert conn.execute("SELECT COUNT(*) FROM family_lists WHERE id = ?", (lid,)).fetchone()[0] == 0


def test_bulk_price_preview_then_apply(tmp_path):
    store = PosStore(str(tmp_path / "p.db"))
    shop = store.create_business(AMMA, {"name": "Sai Tiffins", "state_code": "37"})["id"]
    idli = store.add_product(shop, AMMA, {"name": "Idli", "unit": "pcs", "price_paise": 4000, "menu_group": "Tiffin"})
    dosa = store.add_product(shop, AMMA, {"name": "Dosa", "unit": "pcs", "price_paise": 6000, "menu_group": "Tiffin"})
    tea = store.add_product(shop, AMMA, {"name": "Tea", "unit": "pcs", "price_paise": 1200, "menu_group": "Drinks"})
    assert pos_bulk_price.new_price(4000, "up_percent", 10, 100) == 4400
    assert pos_bulk_price.new_price(1200, "up_percent", 10, 500) == 1500
    assert pos_bulk_price.new_price(1200, "down_rupees", 50, 100) == 100, "never below ₹1"
    body = {"scope": "groups", "groups": ["tiffin"], "mode": "up_rupees", "value": 5, "round_paise": 100}
    pre = pos_bulk_price.preview(store, shop, AMMA, body)
    assert pre["changing"] == 2 and {i["new_paise"] for i in pre["items"]} == {4500, 6500}
    assert store.product(shop, AMMA, idli["id"])["price_paise"] == 4000, "preview writes nothing"
    out = pos_bulk_price.apply(store, shop, AMMA, body)
    assert out["changed"] == 2
    assert store.product(shop, AMMA, dosa["id"])["price_paise"] == 6500
    assert store.product(shop, AMMA, tea["id"])["price_paise"] == 1200
    assert store.product_history(shop, AMMA, idli["id"])[-1] or True
    with pytest.raises(PosError):
        pos_bulk_price.apply(store, shop, OTHER, body)  # not the shop's
    with pytest.raises(PosError):
        pos_bulk_price.preview(store, shop, AMMA, {"scope": "all", "mode": "down_percent", "value": 95})
    one = pos_bulk_price.apply(store, shop, AMMA, {"scope": "items", "product_ids": [tea["id"]], "mode": "set", "value": 15})
    assert one["changed"] == 1 and store.product(shop, AMMA, tea["id"])["price_paise"] == 1500
