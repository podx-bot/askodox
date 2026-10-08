"""Online / local channel (APK 1312): an explicit online ask never shows
nearby shop cards and always runs the online search; a local ask never waits
for web shops; both / neither keeps every source. Any category, en/te/hi."""
import pytest

from app.services.channel_preference import detect
from tests.test_result_contract_combinations import (SHOES_ONLINE, SHOES_PLACES, _Brave, _Maps, _assert_contract,
                                                     _discover, _kinds, app_env)  # noqa: F401


@pytest.mark.parametrize("text,channel", [
    ("show me online shops for paint", "online"),                 # home improvement
    ("buy a laptop online", "online"),                            # electronics
    ("ఆన్‌లైన్ లో టైల్స్ చూపించు", "online"),                       # Telugu
    ("ऑनलाइन दवा", "online"),                                      # Hindi, pharmacy
    ("plumber near me", "local"),                                  # service
    ("దగ్గర్లో పెయింట్ షాప్", "local"),                              # Telugu local
    ("fertiliser dealers in Guntur", "local"),                     # agriculture
    ("walking shoes shops and online links", None),                # both named
    ("online store or nearby shop", None),
    ("how do I learn Python", None),                               # non-commerce
    ("vitrified tiles 100 sq ft", None),                           # nothing said
])
def test_channel_from_the_users_own_words(text, channel):
    assert detect(text) == channel


class _CountingMaps(_Maps):
    def __init__(self, places):
        super().__init__(places)
        self.calls = 0

    def search_places(self, query, **kwargs):
        self.calls += 1
        return self.places


class _CountingBrave(_Brave):
    def __init__(self, rows):
        super().__init__(rows)
        self.calls = 0

    def __call__(self, query, limit):
        self.calls += 1
        return super().__call__(query, limit)


def test_online_ask_shows_online_rows_and_no_nearby_shop_cards(app_env):
    _, container, client = app_env
    maps, brave = _CountingMaps(SHOES_PLACES), _CountingBrave(SHOES_ONLINE)
    container.google_maps_service, container.brave_web_search_provider = maps, brave
    body = _discover(client, text="walking shoes", groups_text="show me walking shoes online shops")
    _assert_contract(body)
    assert "online" in _kinds(body) and "local" not in _kinds(body)
    assert maps.calls == 0, "no Places call for an online-only ask (cost + relevance)"
    assert not [m for m in body["matches"] if "maps.google" in str(m.get("destination_url") or "")]


def test_local_ask_skips_the_web_search(app_env):
    _, container, client = app_env
    maps, brave = _CountingMaps(SHOES_PLACES), _CountingBrave(SHOES_ONLINE)
    container.google_maps_service, container.brave_web_search_provider = maps, brave
    body = _discover(client, text="walking shoes", groups_text="walking shoes near me")
    assert "local" in _kinds(body) and "online" not in _kinds(body)


def test_no_channel_keeps_every_source(app_env):
    _, container, client = app_env
    container.google_maps_service = _Maps(SHOES_PLACES)
    container.brave_web_search_provider = _Brave(SHOES_ONLINE)
    body = _discover(client, text="walking shoes", groups_text="walking shoes")
    assert {"local", "online"} <= set(_kinds(body))


def test_remembered_channel_survives_a_short_follow_up(app_env):
    _, container, client = app_env
    maps = _CountingMaps(SHOES_PLACES)
    container.google_maps_service, container.brave_web_search_provider = maps, _Brave(SHOES_ONLINE)
    # "size 9" names no channel: the app sends the remembered one back.
    body = _discover(client, text="walking shoes", groups_text="size 9", dynamic={"channel": "online"})
    assert "local" not in _kinds(body) and maps.calls == 0
