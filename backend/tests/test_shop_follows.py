"""Shop follows: any signed-in person, shop owners included; the owner cannot follow their own shop;
follower identities are never returned; a shop without followers and a person without a shop work the same."""

import pytest

from app.services.pos_store import PosError, PosStore
from app.services.shop_follows import ShopFollows

OWNER = "app-phone-9400000301"
FOLLOWER = "app-phone-9400000302"
PERSON_WITHOUT_SHOP = "app-phone-9400000303"


@pytest.fixture()
def env(tmp_path):
    store = PosStore(str(tmp_path / "pos.db"))
    shop = store.create_business(OWNER, {"name": "Sri Lakshmi Chicken Centre", "state_code": "37",
                                         "address": "Vuyyuru"})["id"]
    other_shop = store.create_business(FOLLOWER, {"name": "Kirana Corner", "state_code": "37"})["id"]
    return ShopFollows(store.db_path), shop, other_shop


def test_any_signed_in_person_follows_a_shop_and_the_count_is_public(env):
    follows, shop, _ = env
    assert follows.get(shop, PERSON_WITHOUT_SHOP) == {
        "business_id": shop, "name": "Sri Lakshmi Chicken Centre", "address": "Vuyyuru", "category": "general",
        "followers": 0, "following": False, "is_owner": False}
    out = follows.follow(shop, PERSON_WITHOUT_SHOP)
    assert out["following"] is True and out["followers"] == 1 and out["is_owner"] is False


def test_following_twice_counts_once_and_unfollow_removes(env):
    follows, shop, _ = env
    follows.follow(shop, FOLLOWER)
    again = follows.follow(shop, FOLLOWER)
    assert again["followers"] == 1
    gone = follows.unfollow(shop, FOLLOWER)
    assert gone["following"] is False and gone["followers"] == 0


def test_a_shop_owner_can_follow_other_shops_but_not_their_own(env):
    follows, shop, other_shop = env
    assert follows.follow(other_shop, OWNER)["following"] is True
    with pytest.raises(PosError) as own:
        follows.follow(shop, OWNER)
    assert own.value.status == 409 and own.value.code == "own_shop"
    assert follows.get(shop, OWNER)["is_owner"] is True


def test_my_follows_lists_shops_and_never_leaks_follower_ids(env):
    follows, shop, other_shop = env
    follows.follow(shop, PERSON_WITHOUT_SHOP)
    follows.follow(other_shop, PERSON_WITHOUT_SHOP)
    rows = follows.my_follows(PERSON_WITHOUT_SHOP)
    assert {r["business_id"] for r in rows} == {shop, other_shop}
    assert all(FOLLOWER not in str(r) and OWNER not in str(r) for r in rows)
    shop_view = follows.get(shop, FOLLOWER)
    assert PERSON_WITHOUT_SHOP not in str(shop_view), "a shop sees a count, never who follows it"


def test_unknown_shop_is_404(env):
    follows, _, _ = env
    with pytest.raises(PosError) as missing:
        follows.follow("no-such-shop", FOLLOWER)
    assert missing.value.status == 404


PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 64


def test_owner_posts_one_picture_a_day_and_followers_see_it_with_the_credit(env):
    follows, shop, _ = env
    post = follows.post(shop, OWNER, "సంక్రాంతి చికెన్ ఆఫర్", PNG)
    assert post["business_id"] == shop and post["caption"]
    with pytest.raises(PosError) as twice:
        follows.post(shop, OWNER, "again", PNG)
    assert twice.value.status == 409 and twice.value.code == "already_posted_today"
    assert follows.feed(FOLLOWER) == [], "a person who does not follow the shop sees nothing"
    follows.follow(shop, FOLLOWER)
    rows = follows.feed(FOLLOWER)
    assert len(rows) == 1 and rows[0]["credit"] == "Created by Sri Lakshmi Chicken Centre · ASKODOX"
    assert follows.image(post["id"], FOLLOWER) == PNG


def test_only_the_owner_posts_and_only_followers_or_owner_open_the_picture(env):
    follows, shop, _ = env
    with pytest.raises(PosError) as other:
        follows.post(shop, FOLLOWER, "not mine", PNG)
    assert other.value.status == 403 and other.value.code == "not_owner"
    post = follows.post(shop, OWNER, "ఆఫర్", PNG)
    with pytest.raises(PosError) as stranger:
        follows.image(post["id"], PERSON_WITHOUT_SHOP)
    assert stranger.value.status == 403
    assert follows.image(post["id"], OWNER) == PNG


def test_picture_must_be_png_and_small(env):
    follows, shop, _ = env
    with pytest.raises(PosError) as not_png:
        follows.post(shop, OWNER, "x", b"JPEG-ish")
    assert not_png.value.code == "image"
    with pytest.raises(PosError) as big:
        follows.post(shop, OWNER, "x", PNG + b"0" * 900_000)
    assert big.value.code == "image"
