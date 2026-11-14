"""The shop name can be corrected after creation (owner 2026-11-14); an empty name is refused."""

import pytest

from app.services.pos_store import PosError, PosStore

OWNER = "app-phone-9400000401"


@pytest.fixture()
def store(tmp_path):
    return PosStore(str(tmp_path / "pos.db"))


def test_owner_renames_the_shop_and_the_new_name_is_kept(store):
    shop = store.create_business(OWNER, {"name": "Murali Manohar Muttom N Chicken Shop", "state_code": "37"})["id"]
    renamed = store.update_settings(shop, OWNER, {"name": "Sri Lakshmi Mutton Centre"})
    assert renamed["name"] == "Sri Lakshmi Mutton Centre"
    assert store.business(shop, OWNER)["name"] == "Sri Lakshmi Mutton Centre"


def test_an_empty_name_is_refused_and_the_old_name_stays(store):
    shop = store.create_business(OWNER, {"name": "Kirana Corner", "state_code": "37"})["id"]
    with pytest.raises(PosError) as empty:
        store.update_settings(shop, OWNER, {"name": "   "})
    assert empty.value.status == 400 and empty.value.code == "name"
    assert store.business(shop, OWNER)["name"] == "Kirana Corner"
