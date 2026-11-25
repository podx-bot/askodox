"""Finance items (insurance / loan / credit card): the company's own documents, answers from them only, and a call
back from an ASKODOX executive only when the customer says yes. Rules: ``app/services/finance_items.py``.

Staff (Staff Workspace sign-in; needs the grant to add ``financial_offer`` items):
  GET    /admin/cc/workspace/finance/{item_id}                    documents, AI points + answers, what customers ask
  PUT    /admin/cc/workspace/finance/{item_id}/kind               insurance | loan | credit_card | other
  POST   /admin/cc/workspace/finance/{item_id}/documents          one PDF or photo of the company's paper (8 MB)
  DELETE /admin/cc/workspace/finance/{item_id}/documents/{doc}    remove it (and the answers read from it)
  POST   /admin/cc/workspace/finance/{item_id}/study              AI reads the documents -> points + answers with pages
  POST   /admin/cc/workspace/finance/{item_id}/confirm            staff checked them: customers may now ask
  GET    /admin/cc/workspace/finance-callbacks                    who asked for a call (numbers masked)
  POST   /admin/cc/workspace/finance-callbacks/{id}/reveal        the number, for the person who calls now (audited)
  POST   /admin/cc/workspace/finance-callbacks/{id}/close         what happened (+ the answer given, kept for the item)

Customer:
  GET    /api/finance/items/{item_id}                             checked points + ready answers (public, LIVE items)
  POST   /api/finance/items/{item_id}/ask                         answer from the document with its page, or "not there"
  POST   /api/finance/items/{item_id}/callback                    signed in + consent true -> an executive calls
  DELETE /api/finance/callbacks/{id}                              changed my mind
"""
from __future__ import annotations

from typing import Any, List, Optional

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field

from app.api.routes.affiliate_catalog import _audit, catalog
from app.api.routes.staff_workspace import _types, _workspace
from app.services import finance_items as fi
from app.services import governance as gov
from app.services import rate_limit

router = APIRouter(tags=["finance-items"])


def _service(request: Request) -> fi.FinanceItems:
    container: Any = request.app.state.container
    existing = getattr(container, "finance_items", None)
    if existing is not None:
        return existing

    def item(item_id: str) -> Optional[dict]:
        try:
            return catalog(container).get(int(item_id))
        except (TypeError, ValueError):
            return None

    def read_image(data: bytes, mime: str) -> str:
        images = getattr(container, "universal_image_service", None)
        if images is None or not hasattr(images, "analyze_with_prompt"):
            raise RuntimeError("no image reader")
        payload, _calls = images.analyze_with_prompt([(data, mime)], fi.IMAGE_PROMPT, max_models=2,
                                                     allow_second_provider=True, fast=True)
        return str((payload or {}).get("text") or "")

    def write_text(prompt: str) -> str:
        ai = getattr(container, "universal_ai_assistant_service", None)
        if ai is None or not hasattr(ai, "write_text"):
            raise RuntimeError("no model")
        return ai.write_text(prompt, max_tokens=2400) or ""

    service = fi.FinanceItems(container.settings.database_path, item=item, read_image=read_image, write_text=write_text)
    try:
        container.finance_items = service
    except Exception:
        pass
    return service


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except fi.FinanceError as error:
        raise HTTPException(status_code=error.status, detail={"code": error.code, "message": error.message}) from None


def _staff(request: Request) -> dict:
    principal = _workspace(request)
    if "financial_offer" not in _types(principal):
        raise HTTPException(status_code=403, detail=f"{gov.FORBIDDEN} (cannot work on finance items)")
    return principal


def _app_user(request: Request) -> str:
    from app.api.routes.in_app_deal import _authenticated_app_user

    return _authenticated_app_user(request)


# --------------------------------------------------------------------- staff --

class KindBody(BaseModel):
    kind: str = Field(max_length=20)


class ConfirmBody(BaseModel):
    points: Optional[List[str]] = Field(default=None, max_length=6)
    remove_qa: List[str] = Field(default_factory=list, max_length=40)


class CloseBody(BaseModel):
    outcome: str = Field(max_length=20)
    answer: str = Field(default="", max_length=600)
    note: str = Field(default="", max_length=300)


@router.get("/admin/cc/workspace/finance/{item_id}")
def staff_view(item_id: str, request: Request) -> dict:
    _staff(request)
    return _call(_service(request).staff_view, item_id)


@router.put("/admin/cc/workspace/finance/{item_id}/kind")
def set_kind(item_id: str, body: KindBody, request: Request) -> dict:
    _staff(request)
    return _call(_service(request).set_kind, item_id, body.kind)


@router.post("/admin/cc/workspace/finance/{item_id}/documents")
async def add_document(item_id: str, request: Request, file: UploadFile = File(...)) -> dict:
    principal = _staff(request)
    rate_limit.check(request, "finance_documents", limit=60)
    data = await file.read(fi.MAX_DOC_BYTES + 1)
    out = _call(_service(request).add_document, item_id, file.filename or "document", file.content_type or "", data,
                principal["id"])
    print(f"ASKODOX FINANCE DOC item={item_id} bytes={len(data)} docs={len(out['documents'])}", flush=True)
    return out


@router.delete("/admin/cc/workspace/finance/{item_id}/documents/{doc_id}")
def remove_document(item_id: str, doc_id: str, request: Request) -> dict:
    _staff(request)
    return _call(_service(request).remove_document, item_id, doc_id)


@router.post("/admin/cc/workspace/finance/{item_id}/study")
def study(item_id: str, request: Request) -> dict:
    principal = _staff(request)
    rate_limit.check(request, "finance_study", limit=30)
    out = _call(_service(request).study, item_id, principal["id"])
    print(f"ASKODOX FINANCE STUDY item={item_id} points={len(out['points'])} qa={len(out['qa'])}", flush=True)
    return out


@router.post("/admin/cc/workspace/finance/{item_id}/confirm")
def confirm(item_id: str, body: ConfirmBody, request: Request) -> dict:
    principal = _staff(request)
    out = _call(_service(request).confirm, item_id, principal["id"], points=body.points, remove_qa=body.remove_qa)
    _audit(request, principal, "finance_checked", item_id, None, {"points": len(out["points"]), "qa": len(out["qa"])})
    return out


@router.get("/admin/cc/workspace/finance-callbacks")
def callbacks(request: Request, status: str = "new") -> dict:
    _staff(request)
    return {"callbacks": _service(request).callbacks(status=status)}


@router.post("/admin/cc/workspace/finance-callbacks/{callback_id}/reveal")
def reveal(callback_id: str, request: Request) -> dict:
    principal = _staff(request)
    rate_limit.check(request, "finance_reveal", limit=60)
    out = _call(_service(request).reveal, callback_id)
    # Who saw a customer's number, and for which request -- never the number itself.
    _audit(request, principal, "finance_callback_number_seen", out["item_id"], None, {"callback": callback_id})
    return {"id": out["id"], "phone": out["phone"]}


@router.post("/admin/cc/workspace/finance-callbacks/{callback_id}/close")
def close_callback(callback_id: str, body: CloseBody, request: Request) -> dict:
    principal = _staff(request)
    return _call(_service(request).close_callback, callback_id, principal["id"], outcome=body.outcome,
                 answer=body.answer, note=body.note)


# ------------------------------------------------------------------ customer --

class AskBody(BaseModel):
    question: str = Field(min_length=1, max_length=300)
    language: str = Field(default="te", max_length=5)


class CallbackBody(BaseModel):
    question: str = Field(default="", max_length=300)
    when: str = Field(default="now", max_length=12)
    consent: bool = False


@router.get("/api/finance/items/{item_id}")
def public_view(item_id: str, request: Request) -> dict:
    rate_limit.check(request, "finance_view", limit=120)
    return _call(_service(request).public_view, item_id)


@router.post("/api/finance/items/{item_id}/ask")
def ask(item_id: str, body: AskBody, request: Request) -> dict:
    rate_limit.check(request, "finance_ask", limit=30)
    out = _call(_service(request).ask, item_id, body.question, body.language)
    print(f"ASKODOX FINANCE ASK item={item_id} found={out['found']} source={out['source'] or '-'} page={out['page']}",
          flush=True)
    return out


@router.post("/api/finance/items/{item_id}/callback")
def request_callback(item_id: str, body: CallbackBody, request: Request) -> dict:
    user = _app_user(request)
    rate_limit.check(request, f"finance_callback:{user}", limit=10)
    out = _call(_service(request).request_callback, item_id, user, question=body.question, when=body.when,
                consent=body.consent)
    if not out["again"]:
        _tell_staff(request, item_id)
    return out


@router.delete("/api/finance/callbacks/{callback_id}")
def cancel_callback(callback_id: str, request: Request) -> dict:
    return _service(request).cancel_callback(_app_user(request), callback_id)


def _tell_staff(request: Request, item_id: str) -> None:
    """One staff task per item while call backs wait (best effort; the list itself is the record)."""
    try:
        from app.api.routes.platform import platform
        from app.api.routes.staff_workspace import alert_new_task, create_task_once

        container = request.app.state.container
        data = {"title": "Finance call back waiting", "kind": "review_items", "priority": "high",
                "why": "A customer asked for a call about a finance item (they said yes to the call).",
                "expected_action": "Open Staff Workspace -> Finance -> Call backs, call, and note what happened.",
                "dedupe_key": f"finance_callback:{item_id}", "assignee_role": "any", "evidence": {"item_id": item_id}}
        record, new = create_task_once(platform(container), data, actor="system:finance_callback")
        if new:
            alert_new_task(container, record)
    except Exception:
        pass
    print(f"ASKODOX FINANCE CALLBACK item={item_id}", flush=True)
