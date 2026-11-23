"""Task chips learned from the owner's own commands (owner 2026-11-24)."""
from datetime import datetime, timedelta, timezone

from app.services.pos_attendance import rank_task_chips, task_chip_key

NOW = datetime(2026, 11, 24, 9, 0, tzinfo=timezone.utc)  # 14:30 IST


def _row(title, who, days_ago, hour_utc=9):
    at = (NOW - timedelta(days=days_ago)).replace(hour=hour_utc)
    return {"title": title, "assignee": who, "created_at": at.isoformat()}


def test_phrasing_variants_join_one_chip():
    assert task_chip_key("Clean the tables at 3 pm!") == task_chip_key("clean the tables") == "clean the tables"


def test_most_given_recent_and_this_hour_first_with_the_usual_person():
    rows = [_row("Clean the tables", "9848011111", d) for d in (1, 2, 3)]
    rows += [_row("Bring vegetables", "9848022222", d, hour_utc=1) for d in (1, 2, 3)]  # usually morning
    rows += [_row("Old job", "9848033333", d) for d in (80, 81, 82, 83)]
    chips = rank_task_chips(rows, NOW, {})
    assert [c["title"] for c in chips][:2] == ["Clean the tables", "Bring vegetables"]
    assert chips[0]["ref"] == "1111" and chips[0]["times"] == 3
    assert chips[-1]["title"] == "Old job", "old ones fade"


def test_pinned_first_removed_never_and_starters_on_day_one():
    rows = [_row("Clean the tables", "9848011111", 1), _row("Count stock", "9848011111", 5)]
    prefs = {"count stock": {"state": "pin", "title": "Count stock"}, "clean the tables": {"state": "hide"}}
    assert [c["title"] for c in rank_task_chips(rows, NOW, prefs)] == ["Count stock"]
    starters = rank_task_chips([], NOW, {}, "restaurant")
    assert starters and all(c.get("starter") for c in starters)
