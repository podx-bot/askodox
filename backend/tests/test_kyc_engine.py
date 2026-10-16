"""AI-assisted KYC: consent first, extraction never equals verification,
masked storage only, Aadhaar never stored, inconsistencies routed to review,
staff may verify only business / professional documents, providers (when
configured) verify identity, expiry, withdrawal wipes data, demo account refused."""
import dataclasses
import json
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.repositories.command_center_repository import CommandCenterRepository
from app.services import kyc_engine
from app.services.session_tokens import issue_token

OWNER_KEY = "owner-kyc-" + uuid.uuid4().hex[:6]
OWNER = {"X-ASKODOX-Admin-Key": OWNER_KEY}
PAN = "ABCPK1234F"
GSTIN_OK = "27ABCPK1234F1Z"  # check digit appended below

PAN_TEXT = f"INCOME TAX DEPARTMENT  GOVT. OF INDIA\nName: Ravi Kumar\nPermanent Account Number\n{PAN}\n12/05/1990"


def _gstin(base: str) -> str:
    chars = kyc_engine._GST_CHARS
    total = 0
    for i, ch in enumerate(base):
        p = chars.index(ch) * (2 if i % 2 else 1)
        total += p // 36 + p % 36
    return base + chars[(36 - total % 36) % 36]


@pytest.fixture()
def env(monkeypatch, tmp_path):
    from server import app, container

    settings = dataclasses.replace(container.settings, admin_seed_key=OWNER_KEY,
                                   database_path=str(tmp_path / "kyc.db"))
    monkeypatch.setattr(container, "settings", settings)
    monkeypatch.setattr(container, "command_center_repository", CommandCenterRepository(str(tmp_path / "cc.db")),
                        raising=False)
    monkeypatch.setattr(container, "kyc_store", None, raising=False)
    monkeypatch.setattr(container, "kyc_providers", {}, raising=False)
    yield TestClient(app), container


def _user(container, uid=None):
    uid = uid or "app-phone-91" + str(uuid.uuid4().int)[:10]
    return uid, {"Authorization": f"Bearer {issue_token(uid, container.settings.session_token_secret)}"}


def _consent(client, me):
    assert client.post("/api/kyc/consent", headers=me, json={"accept": True}).status_code == 200


def test_extraction_rules():
    gstin = _gstin(GSTIN_OK)
    assert kyc_engine.gstin_valid(gstin) and not kyc_engine.gstin_valid(gstin[:-1] + ("A" if gstin[-1] != "A" else "B"))
    out = kyc_engine.extract(PAN_TEXT)
    assert out["kind"] == "pan" and out["values"]["pan"] == PAN and out["values"]["name"] == "Ravi Kumar"
    assert out["values"]["date"] == "1990-05-12" and not out["issues"]
    gst = kyc_engine.extract(f"Goods and Services Tax\nLegal Name: Ravi Traders\nGSTIN {gstin}\nPAN ZZZPK9999Z")
    assert gst["kind"] == "gst" and gst["values"]["gstin"] == gstin
    assert any("PAN inside the GSTIN differs" in i for i in gst["issues"])
    aadhaar = kyc_engine.extract("Unique Identification Authority of India  1234 5678 9012")
    assert aadhaar["kind"] == "aadhaar" and any("never stores" in i for i in aadhaar["issues"])
    assert "1234" not in json.dumps(aadhaar["values"])
    assert kyc_engine.masked_fields({"pan": PAN})["pan"].endswith("234F") and PAN not in json.dumps(
        kyc_engine.masked_fields({"pan": PAN}))
    mismatch = kyc_engine.extract(PAN_TEXT, profile_name="Sita Devi")
    assert any("does not match the profile" in i for i in mismatch["issues"])


def test_consent_first_masked_only_and_extraction_is_not_verification(env):
    client, container = env
    uid, me = _user(container)
    assert client.post("/api/kyc/documents", json={"text": PAN_TEXT}).status_code == 401
    assert client.post("/api/kyc/documents", headers=me, json={"text": PAN_TEXT}).status_code == 428
    me_before = client.get("/api/kyc/me", headers=me).json()
    assert me_before["level"] == 1 and me_before["consent"] is False and me_before["checks"] == []
    _consent(client, me)
    out = client.post("/api/kyc/documents", headers=me, json={"text": PAN_TEXT}).json()
    assert out["kind"] == "pan" and out["check"]["status"] == "AWAITING_PROVIDER", "no provider -> never verified"
    assert out["check"]["method"] == "ai_extraction"
    assert PAN not in json.dumps(out) and out["prefill"]["pan"].endswith("234F")
    with container.kyc_store._connect() as conn:  # noqa: SLF001 -- storage audit
        dump = json.dumps([dict(r) for r in conn.execute("SELECT * FROM kyc_checks")])
    assert PAN not in dump, "the full PAN is never stored"
    summary = client.get("/api/kyc/me", headers=me).json()
    assert summary["level"] == 1, "AI extraction never raises the level"
    assert summary["providers"]["pan"] == "CONFIGURATION REQUIRED"
    assert summary["requirements"]["buy"]["met"] is True and summary["requirements"]["receive_payouts"]["met"] is False
    # Staff can NOT verify identity -- only an authoritative provider can.
    cid = out["check"]["id"]
    r = client.post(f"/admin/cc/kyc/checks/{cid}/review", headers=OWNER, json={"decision": "approve", "confirm": True})
    assert r.status_code == 409 and r.json()["detail"] == "PROVIDER_VERIFICATION_REQUIRED"


def test_provider_verifies_identity_and_it_expires(env):
    client, container = env

    class FakePanProvider:  # stands in for a real adapter; never reported as a real provider test
        name = "test-provider"

        def __init__(self):
            self.seen = []

        def verify(self, kind, value, name):
            self.seen.append((kind, value))
            return {"verified": True, "reference": "ref-1"}

    provider = FakePanProvider()
    container.kyc_providers = {"pan": provider}
    uid, me = _user(container)
    _consent(client, me)
    out = client.post("/api/kyc/documents", headers=me, json={"text": PAN_TEXT}).json()
    assert out["check"]["status"] == "VERIFIED" and out["check"]["method"] == "provider"
    assert provider.seen == [("pan", PAN)], "the full value goes to the provider in memory only"
    summary = client.get("/api/kyc/me", headers=me).json()
    assert summary["level"] == 2 and summary["requirements"]["receive_payouts"]["met"] is True
    # The same PAN on a second account is flagged for review.
    other, them = _user(container)
    _consent(client, them)
    dup = client.post("/api/kyc/documents", headers=them, json={"text": PAN_TEXT}).json()
    assert dup["check"]["status"] == "NEEDS_REVIEW" and any("another ASKODOX account" in i for i in dup["issues"])
    # Expiry.
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    container.kyc_store.update(out["check"]["id"], expires_at=past)
    assert client.get("/api/kyc/me", headers=me).json()["level"] == 1


def test_staff_review_business_document_withdrawal_and_demo(env):
    client, container = env
    uid, me = _user(container)
    _consent(client, me)
    doc = client.post("/api/kyc/documents", headers=me, json={
        "text": "Udyam Registration Certificate\nName of Enterprise: Ravi Kumar\nMSME", "kind_hint": ""}).json()
    assert doc["kind"] == "business_document" and doc["check"]["status"] == "NEEDS_REVIEW"
    queue = client.get("/admin/cc/kyc/queue", headers=OWNER).json()["items"]
    assert any(i["id"] == doc["check"]["id"] and i["staff_reviewable"] for i in queue)
    assert client.get("/admin/cc/kyc/queue").status_code in (401, 403)
    cid = doc["check"]["id"]
    assert client.post(f"/admin/cc/kyc/checks/{cid}/review", headers=OWNER,
                       json={"decision": "approve"}).status_code == 409, "confirmation required"
    ok = client.post(f"/admin/cc/kyc/checks/{cid}/review", headers=OWNER,
                     json={"decision": "approve", "confirm": True, "note": "Udyam checked"}).json()
    assert ok["check"]["status"] == "VERIFIED" and ok["check"]["method"] == "staff_review"
    assert client.get("/api/kyc/me", headers=me).json()["level"] == 3
    # Aadhaar is never stored.
    a = client.post("/api/kyc/documents", headers=me, json={"text": "UIDAI Aadhaar 2345 6789 0123"}).json()
    assert a["check"] is None and a["kind"] == "aadhaar"
    # Withdrawing consent deletes the stored details.
    w = client.delete("/api/kyc/consent", headers=me).json()
    assert w["checks_deleted"] >= 1
    after = client.get("/api/kyc/me", headers=me).json()
    assert after["checks"] == [] and after["level"] == 1 and after["consent"] is False
    # The shared demo login can never be verified.
    _, demo = _user(container, "app-phone-919999999999")
    assert client.post("/api/kyc/consent", headers=demo, json={"accept": True}).status_code == 403
    assert client.get("/api/kyc/me", headers=demo).json()["level"] == 0
