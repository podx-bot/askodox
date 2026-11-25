"""Finance items: answers only from the company's document (page + a quote that really stands on it), customers see
only what staff checked, and a call back needs the customer's yes. Every name, figure and number is made up."""
import dataclasses
import json
import uuid

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import affiliate_catalog as ac
from app.services import finance_items as fi
from app.services import rate_limit
from app.services.session_tokens import issue_token

PAGES = ["Suraksha Health Plan. Entry age is 18 to 65 years. Sum insured options are 3 lakh, 5 lakh and 10 lakh rupees.",
         "Waiting period. Pre-existing diseases are covered after a waiting period of 36 months from the policy start date.",
         "Exclusions. Cosmetic surgery and dental treatment are not covered under this plan unless caused by an accident."]
PDF = b"%PDF-1.4 made up"
STUDY = {"points": ["Entry age 18 to 65 years", "Sum insured 3 / 5 / 10 lakh"], "qa": [
    {"q": "When are old diseases covered?", "a": "After 36 months.", "doc": 1, "page": 2,
     "quote": "covered after a waiting period of 36 months from the policy start date"},
    {"q": "Is maternity covered?", "a": "Yes, fully.", "doc": 1, "page": 3, "quote": "maternity is fully covered from day one"},
    {"q": "Wrong page", "a": "x", "doc": 1, "page": 9, "quote": "Entry age is 18 to 65 years"}]}


class Model:
    def __init__(self):
        self.answer, self.prompts = STUDY, []

    def __call__(self, prompt):
        self.prompts.append(prompt)
        return "Here you go: " + json.dumps(self.answer)


def _service(tmp_path, items=None):
    items = items if items is not None else {"7": {"id": 7, "item_type": "financial_offer", "review_status": "LIVE",
                                                   "title": "Suraksha Health Plan", "affiliate_url": "https://x.example/a"},
                                             "8": {"id": 8, "item_type": "product", "review_status": "LIVE", "title": "Shoe"},
                                             "9": {"id": 9, "item_type": "financial_offer", "review_status": "DRAFT", "title": "Loan"}}
    model = Model()
    svc = fi.FinanceItems(str(tmp_path / "f.db"), item=items.get, read_pdf=lambda data: list(PAGES),
                          read_image=lambda data, mime: "Premium chart. Age 30 years premium is 6,400 rupees per year for 5 lakh.",
                          write_text=model)
    return svc, model


def _ready(svc):
    svc.add_document("7", "brochure.pdf", "application/pdf", PDF, "staff-1")
    svc.study("7", "staff-1")
    return svc.confirm("7", "staff-1")


def test_study_keeps_only_answers_whose_quote_stands_on_the_named_page(tmp_path):
    svc, _ = _service(tmp_path)
    svc.add_document("7", "brochure.pdf", "application/pdf", PDF, "staff-1")
    view = svc.study("7", "staff-1")
    assert [q["question"] for q in view["qa"]] == ["When are old diseases covered?"]
    assert view["qa"][0]["page"] == 2 and view["qa"][0]["document"] == "brochure.pdf"
    assert view["points"] == STUDY["points"] and view["checked"] is False


def test_customers_see_nothing_until_staff_checked_and_a_new_document_needs_a_new_check(tmp_path):
    svc, _ = _service(tmp_path)
    svc.add_document("7", "brochure.pdf", "application/pdf", PDF, "staff-1")
    svc.study("7", "staff-1")
    before = svc.public_view("7")
    assert before["points"] == [] and before["questions"] == [] and before["can_ask"] is False
    assert svc.ask("7", "When are old diseases covered?")["found"] is False
    svc.confirm("7", "staff-1")
    after = svc.public_view("7")
    assert after["can_ask"] is True and len(after["questions"]) == 1 and after["has_link"] is True
    jpg = b"\xff\xd8\xff" + b"0" * 50
    assert svc.add_document("7", "chart.jpg", "image/jpeg", jpg, "staff-1")["checked"] is False
    assert svc.public_view("7")["can_ask"] is False


def test_ask_answers_with_the_page_or_says_it_is_not_in_the_document(tmp_path):
    svc, model = _service(tmp_path)
    _ready(svc)
    model.answer = {"found": True, "answer": "36 నెలల తర్వాత cover అవుతాయి.", "doc": 1, "page": 2, "executive": 0,
                    "quote": "Pre-existing diseases are covered after a waiting period of 36 months"}
    good = svc.ask("7", "పాత జబ్బులు ఎప్పుడు cover అవుతాయి?", "te")
    assert good["found"] is True and good["page"] == 2 and good["document"] == "brochure.pdf"
    assert good["source"] == "document" and good["offer_callback"] is False and "సలహా కాదు" in good["not_advice"]
    assert "NEVER advise" in model.prompts[-1] and "[D1 p2]" in model.prompts[-1]
    # A confident answer whose quote is not on that page is a guess: refused.
    model.answer = {"found": True, "answer": "Maternity is covered.", "doc": 1, "page": 3, "executive": 0,
                    "quote": "maternity is fully covered from day one"}
    bad = svc.ask("7", "Is maternity covered?", "en")
    assert bad["found"] is False and bad["offer_callback"] is True and bad["answer"] == fi.NOT_IN_DOCUMENT["en"]
    model.answer = {"found": False}
    assert svc.ask("7", "Is maternity covered?", "en")["found"] is False
    assert svc.staff_view("7")["not_answered"] == [{"question": "is maternity covered?", "times": 2}]


def test_only_live_finance_items_are_served(tmp_path):
    svc, _ = _service(tmp_path)
    for item_id in ("8", "9", "404"):
        with pytest.raises(fi.FinanceError) as error:
            svc.public_view(item_id)
        assert error.value.status == 404
    assert svc.staff_view("9")["title"] == "Loan"  # staff prepare a draft before it goes live


def test_documents_bad_files_limits_and_removal(tmp_path):
    svc, _ = _service(tmp_path)
    for data, code in ((b"", "size"), (b"hello world", "type"), (b"x" * (fi.MAX_DOC_BYTES + 1), "size")):
        with pytest.raises(fi.FinanceError) as error:
            svc.add_document("7", "a", "", data, "s")
        assert error.value.code == code
    svc.read_pdf = lambda data: ["", "  "]
    with pytest.raises(fi.FinanceError) as error:
        svc.add_document("7", "scan.pdf", "", PDF, "s")
    assert error.value.code == "no_text"
    svc.read_pdf = lambda data: list(PAGES)
    view = _ready(svc)
    doc = view["documents"][0]
    assert doc["pages"] == 3
    gone = svc.remove_document("7", doc["id"])
    assert gone["documents"] == [] and gone["qa"] == [] and gone["checked"] is False


def test_callback_needs_consent_and_the_own_number_and_staff_see_it_masked(tmp_path):
    svc, _ = _service(tmp_path)
    _ready(svc)
    user = "app-phone-9000000123"
    with pytest.raises(fi.FinanceError) as error:
        svc.request_callback("7", user, question="Is maternity covered?", when="evening", consent=False)
    assert error.value.code == "consent"
    with pytest.raises(fi.FinanceError) as error:
        svc.request_callback("7", "app-guest-1", question="q", when="now", consent=True)
    assert error.value.code == "no_phone"
    made = svc.request_callback("7", user, question="Is maternity covered?", when="evening", consent=True)
    again = svc.request_callback("7", user, question="Is maternity covered?", when="tomorrow", consent=True)
    assert again == {"id": made["id"], "status": "new", "again": True}
    rows = svc.callbacks()
    assert len(rows) == 1 and rows[0]["customer"] == "••123" and rows[0]["when"] == "tomorrow"
    assert "9000000123" not in json.dumps(rows)
    assert svc.reveal(made["id"])["phone"] == "9000000123"
    closed = svc.close_callback(made["id"], "staff-2", outcome="answered", answer="Maternity is covered after 2 years.")
    assert closed == {"ok": True, "answer_saved": True}
    with pytest.raises(fi.FinanceError):
        svc.reveal(made["id"])  # the number is wiped with the request closed
    done = svc.callbacks(status="done")
    assert done[0]["outcome"] == "answered" and svc.callbacks() == []
    saved = [q for q in svc.staff_view("7")["qa"] if q["source"] == "executive"]
    assert saved[0]["answer"] == "Maternity is covered after 2 years." and saved[0]["page"] == 0


def test_an_executives_saved_answer_reaches_the_next_customer_labelled(tmp_path):
    svc, model = _service(tmp_path)
    _ready(svc)
    made = svc.request_callback("7", "app-phone-9000000123", question="Is maternity covered?", when="now", consent=True)
    svc.close_callback(made["id"], "staff-2", outcome="answered", answer="Maternity is covered after 2 years.")
    model.answer = {"found": True, "answer": "2 years tarvata cover avutundi.", "doc": 0, "page": 0, "quote": "", "executive": 1}
    out = svc.ask("7", "maternity cover unda?", "te")
    assert out["found"] is True and out["source"] == "executive" and out["page"] == 0
    assert "[E1] Q: Is maternity covered?" in model.prompts[-1]


def test_customer_can_cancel_and_open_requests_are_capped(tmp_path):
    items = {str(n): {"id": n, "item_type": "financial_offer", "review_status": "LIVE", "title": f"Plan {n}"} for n in range(1, 6)}
    svc, _ = _service(tmp_path, items)
    user = "app-phone-9000000456"
    ids = [svc.request_callback(str(n), user, question="q", when="now", consent=True)["id"] for n in (1, 2, 3)]
    with pytest.raises(fi.FinanceError) as error:
        svc.request_callback("4", user, question="q", when="now", consent=True)
    assert error.value.status == 429
    svc.cancel_callback("app-phone-9000000999", ids[0])  # someone else's token removes nothing
    assert len(svc.callbacks()) == 3
    svc.cancel_callback(user, ids[0])
    assert len(svc.callbacks()) == 2


# ------------------------------------------------------------------ routes --

OWNER_KEY = "owner-fin-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}


@pytest.fixture()
def api(monkeypatch, tmp_path):
    from server import app, container

    rate_limit.reset_for_tests()
    db = str(tmp_path / "fin.db")
    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY, database_path=db,
                                   secrets_key=Fernet.generate_key().decode())
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")), raising=False)
    monkeypatch.setattr(container, "platform", None, raising=False)
    catalog = ac.AffiliateCatalog(db)
    monkeypatch.setattr(container, "affiliate_catalog", catalog, raising=False)
    model = Model()
    service = fi.FinanceItems(db, item=lambda i: catalog.get(int(i)) if str(i).isdigit() else None,
                              read_pdf=lambda data: list(PAGES), write_text=model)
    monkeypatch.setattr(container, "finance_items", service, raising=False)
    yield TestClient(app), container, model
    container.platform = None


def _item(client):
    r = client.post("/admin/cc/workspace/items", headers=OWNER, json={
        "item_type": "financial_offer", "action": "submit",
        "fields": {"title": "Suraksha Health Plan", "platform": "other",
                   "original_product_url": "https://insurer.example/suraksha", "description": "Health cover"}})
    assert r.status_code == 200, r.text
    assert r.json()["review_status"] == "LIVE"
    return str(r.json()["item"]["id"])


def test_routes_staff_prepare_customer_asks_and_asks_for_a_call(api):
    client, container, model = api
    item = _item(client)
    base = f"/admin/cc/workspace/finance/{item}"
    assert client.get(base).status_code in (401, 403)
    assert client.post(f"{base}/documents", files={"file": ("b.pdf", PDF, "application/pdf")}).status_code in (401, 403)
    r = client.post(f"{base}/documents", headers=OWNER, files={"file": ("b.pdf", PDF, "application/pdf")})
    assert r.status_code == 200, r.text
    assert client.put(f"{base}/kind", headers=OWNER, json={"kind": "insurance"}).json()["kind"] == "insurance"
    assert client.put(f"{base}/kind", headers=OWNER, json={"kind": "gold"}).status_code == 400
    assert len(client.post(f"{base}/study", headers=OWNER).json()["qa"]) == 1
    assert client.get(f"/api/finance/items/{item}").json()["can_ask"] is False
    assert client.post(f"{base}/confirm", headers=OWNER, json={}).json()["checked"] is True
    public = client.get(f"/api/finance/items/{item}").json()
    assert public["can_ask"] is True and public["kind"] == "insurance" and public["points"]
    model.answer = {"found": False}
    miss = client.post(f"/api/finance/items/{item}/ask", json={"question": "Is maternity covered?", "language": "en"}).json()
    assert miss["found"] is False and miss["offer_callback"] is True
    body = {"question": "Is maternity covered?", "when": "evening", "consent": True}
    assert client.post(f"/api/finance/items/{item}/callback", json=body).status_code == 401
    token = issue_token("app-phone-9000000321", container.settings.session_token_secret)
    me = {"Authorization": f"Bearer {token}"}
    assert client.post(f"/api/finance/items/{item}/callback", headers=me, json={**body, "consent": False}).status_code == 400
    made = client.post(f"/api/finance/items/{item}/callback", headers=me, json=body)
    assert made.status_code == 200, made.text
    assert client.get("/admin/cc/workspace/finance-callbacks").status_code in (401, 403)
    rows = client.get("/admin/cc/workspace/finance-callbacks", headers=OWNER).json()["callbacks"]
    assert rows[0]["customer"] == "••321" and "9000000321" not in json.dumps(rows)
    cid = rows[0]["id"]
    assert client.post(f"/admin/cc/workspace/finance-callbacks/{cid}/reveal").status_code in (401, 403)
    assert client.post(f"/admin/cc/workspace/finance-callbacks/{cid}/reveal", headers=OWNER).json()["phone"] == "9000000321"
    r = client.post(f"/admin/cc/workspace/finance-callbacks/{cid}/close", headers=OWNER,
                    json={"outcome": "answered", "answer": "Maternity is covered after 2 years."})
    assert r.json()["answer_saved"] is True
    assert client.get(f"/api/finance/items/{item}").json()["questions"][0]["source"] == "executive"
    assert client.get("/api/finance/items/999999").status_code == 404
