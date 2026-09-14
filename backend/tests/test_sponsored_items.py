from app.core.sponsored_items import sponsored_items_for


def test_sponsored_items_are_empty_by_default():
    assert sponsored_items_for("explore_top") == []


def test_filters_active_items_by_placement(monkeypatch):
    monkeypatch.setattr(
        "app.core.sponsored_items.SPONSORED_ITEMS",
        [
            {"id": "one", "title": "One", "placement": "explore_top", "active": True},
            {"id": "two", "title": "Two", "placement": "home", "active": True},
            {"id": "three", "title": "Three", "placement": "explore_top", "active": False},
        ],
    )
    assert [item["id"] for item in sponsored_items_for(" EXPLORE_TOP ")] == ["one"]
