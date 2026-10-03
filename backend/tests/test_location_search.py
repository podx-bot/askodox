"""Location picker search: a town typed by name is geocoded first (not
biased to the old pin), then nearby places follow without duplicates."""
from fastapi.testclient import TestClient

from app.services import rate_limit


class _Maps:
    enabled = True
    last_error = False

    def __init__(self):
        self.calls = []

    def geocode(self, place, region="in"):
        self.calls.append(("geocode", place))
        return {"name": "Vijayawada, Andhra Pradesh, India", "latitude": 16.5062, "longitude": 80.648,
                "place_id": "city"}

    def search_places(self, query, **kw):
        self.calls.append(("places", query, kw.get("latitude")))
        return [{"name": "Vijayawada Junction", "address": "Vijayawada", "latitude": 16.5176, "longitude": 80.6197},
                {"name": "Same point", "address": "x", "latitude": 16.5063, "longitude": 80.6481}]


def test_vijayawada_is_geocoded_first_even_when_the_pin_is_in_vuyyuru(monkeypatch):
    from server import app, container

    rate_limit.reset_for_tests()
    maps = _Maps()
    monkeypatch.setattr(container, "google_maps_service", maps)
    client = TestClient(app)
    data = client.get("/api/discover/places", params={"q": "vijayawada", "latitude": 16.36, "longitude": 80.84}).json()
    assert data["status"] == "ok"
    first = data["items"][0]
    assert first["kind"] == "area" and first["name"] == "Vijayawada" and abs(first["latitude"] - 16.5062) < 1e-6
    assert [i["name"] for i in data["items"]] == ["Vijayawada", "Vijayawada Junction"], "duplicate point dropped"
    assert maps.calls[0] == ("geocode", "vijayawada")
