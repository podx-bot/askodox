"""Staff tools (owner request 2026-10-29): AI-written descriptions from page
facts + photos only (no invented price / warranty / stock), and many product
links (+ commission links) split into tasks for chosen staff with progress."""
from types import SimpleNamespace

from app.services import product_description as pd

from test_sources_workspace_early_access import OWNER, _app_bearer, _staff, api  # noqa: F401  (fixture)


def test_description_uses_facts_only_and_flags_unbacked_claims():
    seen = []

    def write(prompt):
        seen.append(prompt)
        return '{"en": "Cotton kurti in blue. Comes with 1 year warranty.", "te": "Blue cotton kurti."}'

    out = pd.describe({"title": "Women Cotton Kurti", "colour": "Blue", "price": "499", "junk": "x"}, write=write,
                      photo_facts=["a blue kurti with white print"])
    assert out["ok"] and out["needs_review"] is True
    assert out["description_te"] == "Blue cotton kurti."
    assert out["unsupported_claims"] == ["warranty"], "warranty is not in the facts"
    assert '"price": "499"' in seen[0] and "junk" not in seen[0] and "a blue kurti" in seen[0]
    assert "Do NOT add or guess a price" in seen[0]
    assert pd.describe({}, write=write)["ok"] is False
    assert pd.describe({"title": "x"}, write=lambda p: "")["ok"] is False


def test_describe_route_and_link_batches_split_between_staff(api):  # noqa: F811
    client, container, _ = api
    container.universal_ai_assistant_service = SimpleNamespace(
        write_text=lambda prompt, max_tokens=900: '{"en": "Steel bottle, 1 litre.", "te": "Steel bottle, 1 litre."}')
    worker = _staff(client, "affiliate_product_staff", phone="919811111111")
    other = _staff(client, "affiliate_product_staff", phone="919822222222")
    junior = {"X-ASKODOX-Staff-Session": client.post("/api/staff/session",
                                                     headers=_app_bearer(container, "919811111111")).json()["session"]}
    got = client.post("/admin/cc/workspace/describe", headers=junior,
                      json={"fields": {"title": "Steel bottle 1 litre"}, "photos": ["https://evil.example/x.jpg"]})
    assert got.status_code == 200 and got.json()["description_en"] == "Steel bottle, 1 litre."
    assert got.json()["photo_facts"] == [], "only photos uploaded to ASKODOX are read"
    links = [f"https://www.meesho.com/item-{i}/p/{1000 + i}" for i in range(7)]
    body = {"links": links + [links[0], "not a link"], "affiliate_links": ["https://aff.example/a"],
            "assignees": [str(worker["id"]), f"staff-{other['id']}"], "per_task": 3}
    assert client.post("/admin/cc/workspace/tasks/batch-links", headers=junior, json=body).status_code == 403
    made = client.post("/admin/cc/workspace/tasks/batch-links", headers=OWNER, json=body).json()
    assert made["links"] == 7 and [t["links"] for t in made["tasks"]] == [3, 3, 1] and made["created"] == 3
    assert [t["assignee"] for t in made["tasks"]] == [worker["name"], other["name"], worker["name"]]
    again = client.post("/admin/cc/workspace/tasks/batch-links", headers=OWNER, json=body).json()
    assert again["created"] == 0, "the same batch never duplicates tasks"
    mine = client.get("/admin/cc/workspace/tasks", headers=junior).json()["items"]
    evidence = [t["data"]["evidence"] for t in mine if t["data"].get("kind") == "add_products"]
    assert len(evidence) == 2, "worker got tasks 1 and 3"
    firsts = [e["links"][0] for e in evidence]
    assert {"url": links[0], "affiliate_url": "https://aff.example/a"} in firsts
    progress = client.get(f"/admin/cc/workspace/tasks/batch-links/{made['batch']}", headers=OWNER).json()
    assert progress["links"] == 7 and progress["added"] == 0
    me = client.get("/admin/cc/workspace/me", headers=OWNER).json()
    assert me["can_assign"] is True and {m["name"] for m in me["team"]} >= {worker["name"], other["name"]}
