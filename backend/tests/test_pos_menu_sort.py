"""Sort with AI (owner 2026-11-22/23): three 503s in the deploy log -- every part of a 150+ item menu came back
"claude answer cut at max_tokens" and the whole menu was called unreadable. These cases keep that from coming back."""

import re
import threading

from app.services.pos_menu_sort import MenuSortJobs, _parse, sort_menu

SECTIONS = ["Chicken", "Mutton", "Fish", "Eggs", "Drinks"]


def _menu(n):
    return [{"id": f"p{i}", "name": f"Item {i}", "menu_group": "", "food_type": ""} for i in range(1, n + 1)]


def _numbers(prompt):
    return [int(m) for m in re.findall(r"^(\d+)\. ", prompt.split("Items:\n", 1)[1], re.M)]


def _lines(nums):
    return "".join(f"{n}|{SECTIONS[n % len(SECTIONS)]}|nonveg\n" for n in nums)


def test_a_cut_answer_keeps_every_finished_line_and_the_rest_is_asked_again():
    calls = []
    lock = threading.Lock()

    def model(prompt, max_tokens=0):
        nums = _numbers(prompt)
        with lock:
            calls.append(len(nums))
            first = len(calls) <= 7  # 160 items = 7 parts on the first reading
        if first:
            # the model stopped in the middle of the 19th line ("cut at max_tokens")
            return _lines(nums[:18]) + f"{nums[18]}|Chi"
        return _lines(nums)

    out = sort_menu(_menu(160), model)
    assert out["read"] is True
    assert all(r["menu_group"] for r in out["items"]), "every item got a section after the second reading"
    assert max(calls) <= 25, "parts are small enough that the answer fits"
    assert "Chi" not in out["groups"], "a half-written last line is never a section"


def test_all_parts_failing_once_still_reads_the_menu_on_the_second_try():
    seen = {"n": 0}
    lock = threading.Lock()

    def model(prompt, max_tokens=0):
        with lock:
            seen["n"] += 1
            first = seen["n"] <= 8
        if first:
            return ""
        return _lines(_numbers(prompt))

    out = sort_menu(_menu(193), model)
    assert out["read"] is True and len(out["items"]) == 193
    assert set(out["groups"]) <= set(SECTIONS)


def test_nothing_read_at_all_says_so():
    out = sort_menu(_menu(40), lambda p, max_tokens=0: "sorry, no")
    assert out["read"] is False
    assert all(r["menu_group"] == "" for r in out["items"])


def test_parser_reads_lines_tables_and_cut_json():
    assert _parse("3|Biryani|nonveg\n7|Drinks|\n")[7] == {"group": "Drinks", "food": ""}
    assert _parse("| 4 | Starters | veg |\n")[4]["group"] == "Starters"
    cut = '{"items": [{"i": 1, "group": "Biryani", "food": "nonveg"}, {"i": 2, "group": "Cur'
    rows = _parse(cut)
    assert rows == {1: {"group": "Biryani", "food": "nonveg"}}
    # a two-cell last line may be cut; the same line earlier in the answer is complete
    assert 5 not in _parse("4|Rice|veg\n5|Ri")
    assert _parse("5|Rice\n6|Drinks|\n")[5]["group"] == "Rice"


def test_menu_sort_job_runs_once_per_shop_and_tells_when_ready():
    clock = {"t": 1000.0}
    jobs = MenuSortJobs(keep_s=60, clock=lambda: clock["t"])
    told = []
    assert jobs.get("biz1") == {"status": "none"}
    view = jobs.start("biz1", lambda: {"items": [{"id": "a"}], "groups": ["X"], "read": True}, told.append, wait=True)
    assert view["status"] == "done" and view["items"] == [{"id": "a"}]
    assert told and told[0]["status"] == "done"
    assert jobs.get("biz1")["status"] == "done"
    failed = jobs.start("biz2", lambda: {"items": [], "read": False}, told.append, wait=True)
    assert failed["status"] == "failed"
    clock["t"] += 61
    assert jobs.get("biz1") == {"status": "none"}, "a finished preview is kept for a while, then dropped"


def test_a_running_job_is_not_started_twice():
    gate = threading.Event()
    jobs = MenuSortJobs()
    runs = []

    def slow():
        runs.append(1)
        gate.wait(5)
        return {"items": [], "read": True}

    assert jobs.start("biz", slow)["status"] == "running"
    assert jobs.start("biz", slow)["status"] == "running"
    gate.set()
    for _ in range(100):
        if jobs.get("biz")["status"] != "running":
            break
        threading.Event().wait(0.02)
    assert runs == [1]
    jobs.clear("biz")
    assert jobs.get("biz") == {"status": "none"}


def test_routes_start_in_background_report_state_and_clear_after_save(monkeypatch):
    import time

    from fastapi.testclient import TestClient

    from app.services import rate_limit
    from app.services.session_tokens import issue_token
    from server import app, container

    class Model:
        def write_text(self, prompt, max_tokens=0):
            return _lines(_numbers(prompt))

    rate_limit.reset_for_tests()
    monkeypatch.setattr(container, "pos_store", None, raising=False)
    monkeypatch.setattr(container, "pos_frontdesk", None, raising=False)
    monkeypatch.setattr(container, "pos_menu_sort_jobs", None, raising=False)
    monkeypatch.setattr(container, "universal_ai_assistant_service", Model(), raising=False)
    secret = container.settings.session_token_secret

    def auth(user):
        return {"Authorization": f"Bearer {issue_token(user, secret)}"}

    client = TestClient(app)
    owner, stranger = "app-phone-9411100071", "app-phone-9811100072"
    biz = client.post("/api/pos/businesses", headers=auth(owner),
                      json={"name": "Meat Shop", "state_code": "37", "template": "restaurant"}).json()["id"]
    for name in ("Chicken Curry Cut", "Mutton Fry", "Fish"):
        client.post(f"/api/pos/businesses/{biz}/products", headers=auth(owner),
                    json={"name": name, "unit": "kg", "price_paise": 25000})
    assert client.get(f"/api/pos/businesses/{biz}/desk/menu/sort", headers=auth(owner)).json() == {"status": "none"}
    started = client.post(f"/api/pos/businesses/{biz}/desk/menu/sort", params={"background": 1, "lang": "te"},
                          headers=auth(owner))
    assert started.status_code == 200, started.text
    state = {}
    for _ in range(100):
        state = client.get(f"/api/pos/businesses/{biz}/desk/menu/sort", headers=auth(owner)).json()
        if state["status"] != "running":
            break
        time.sleep(0.03)
    assert state["status"] == "done" and len(state["items"]) == 3 and state["read"] is True
    assert client.get(f"/api/pos/businesses/{biz}/desk/menu/sort", headers=auth(stranger)).status_code in (403, 404)
    saved = client.post(f"/api/pos/businesses/{biz}/desk/menu/sort/apply", headers=auth(owner),
                        json={"items": [{"id": r["id"], "menu_group": r["menu_group"], "food_type": r["food_type"]}
                                        for r in state["items"]]})
    assert saved.status_code == 200 and saved.json()["saved"] == 3
    assert client.get(f"/api/pos/businesses/{biz}/desk/menu/sort", headers=auth(owner)).json() == {"status": "none"}
    # older apps still get the answer in the same call
    direct = client.post(f"/api/pos/businesses/{biz}/desk/menu/sort", headers=auth(owner)).json()
    assert direct["read"] is True and len(direct["items"]) == 3
