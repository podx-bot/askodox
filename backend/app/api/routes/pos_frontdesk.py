"""Front Desk APIs: the customer's order QR / menu / receptionist / tracking and the shop's order desk + spoken menu.

Customer routes (any signed-in person): ``/api/pos/order-desk/*``.
Shop routes (floor staff, role-checked in the service): ``/api/pos/businesses/{id}/desk/*``.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.routes.pos import _call, _restaurant, _store, _user
from app.services.pos_frontdesk import PosFrontDesk

router = APIRouter(prefix="/api/pos", tags=["POS front desk"])


def _desk(request: Request) -> PosFrontDesk:
    from app.api.routes.payment_methods import payment_methods
    from app.services.push_service import push_service

    container: Any = request.app.state.container
    store = _store(request)
    existing = getattr(container, "pos_frontdesk", None)
    if existing is None or existing.store is not store:
        def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)

        methods = payment_methods(container)

        def pay_to(owner: str, amount_paise: int, note: str, ref: str) -> List[Dict[str, Any]]:
            return methods.pay_to(owner, amount=amount_paise / 100.0, note=note, reference=ref)

        existing = PosFrontDesk(store, _restaurant(request), notify=notify, pay_to=pay_to)
        try:
            container.pos_frontdesk = existing
        except Exception:
            pass
    return existing


class LineIn(BaseModel):
    product_id: str = Field(max_length=60)
    qty: float = Field(default=1, gt=0, le=50)
    note: str = Field(default="", max_length=120)


class OrderIn(BaseModel):
    code: Optional[str] = Field(default=None, max_length=120)
    items: List[LineIn] = Field(min_length=1, max_length=60)
    kind: Optional[str] = Field(default=None, pattern="^(dine_in|takeaway|delivery)$")
    name: str = Field(default="", max_length=40)
    phone: str = Field(default="", max_length=20)
    address: str = Field(default="", max_length=240)
    landmark: str = Field(default="", max_length=80)
    lat: Optional[float] = None
    lng: Optional[float] = None
    notes: str = Field(default="", max_length=160)
    client_txn_id: str = Field(min_length=8, max_length=64)


class StaffOrderIn(OrderIn):
    source: str = Field(default="counter", pattern="^(counter|reception)$")
    table_id: Optional[str] = Field(default=None, max_length=60)


class AssistIn(BaseModel):
    code: Optional[str] = Field(default=None, max_length=120)
    text: str = Field(max_length=300)
    cart: List[Dict[str, Any]] = Field(default_factory=list, max_length=60)
    te: bool = True


class ConfirmIn(BaseModel):
    decisions: Dict[str, bool] = Field(default_factory=dict)
    note: str = Field(default="", max_length=160)


class ReasonIn(BaseModel):
    reason: str = Field(default="", max_length=160)


class AdvanceIn(BaseModel):
    stage: str = Field(max_length=20)
    assignee: str = Field(default="", max_length=40)
    assignee_user: str = Field(default="", max_length=60)


class BillIn(BaseModel):
    payments: List[Dict[str, Any]] = Field(default_factory=list, max_length=6)
    client_txn_id: str = Field(default="", max_length=64)
    customer_id: Optional[str] = Field(default=None, max_length=60)


class MenuTextIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


class MenuPhotoIn(BaseModel):
    """Up to 4 photos of the menu, each base64 (JPEG / PNG), about 4 MB at most."""
    images: List[Dict[str, str]] = Field(min_length=1, max_length=4)


class MenuItemIn(BaseModel):
    name: str = Field(max_length=80)
    price_paise: int = Field(ge=1, le=10_00_00_000_00)
    unit: str = Field(default="plate", max_length=10)
    today_only: bool = False


class MenuImportIn(BaseModel):
    items: List[MenuItemIn] = Field(min_length=1, max_length=200)
    rate_bp: int = Field(default=0, ge=0, le=4000)


class AvailabilityIn(BaseModel):
    available: bool


class TodayOnlyIn(BaseModel):
    today_only: bool


class QuickLineIn(BaseModel):
    name: str = Field(default="", max_length=80)
    amount_paise: int = Field(ge=1, le=10_00_00_000_00)


class QuickBillIn(BaseModel):
    lines: List[QuickLineIn] = Field(min_length=1, max_length=100)
    advance_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    method: str = Field(default="cash", pattern="^(cash|upi|card|bank_transfer)$")
    name: str = Field(default="", max_length=80)
    phone: str = Field(default="", max_length=20)
    customer_id: Optional[str] = Field(default=None, max_length=60)
    rate_bp: int = Field(default=0, ge=0, le=4000)
    notes: str = Field(default="", max_length=200)
    client_txn_id: str = Field(min_length=8, max_length=64)


class AssigneeIn(BaseModel):
    assignee: str = Field(default="", max_length=40)
    assignee_user: str = Field(default="", max_length=60)


class DeskSettingsIn(BaseModel):
    """routing: {new | kitchen | ready | delivery: [staff user ids]} (empty list = the role defaults)."""
    routing: Optional[Dict[str, List[str]]] = None
    auto_confirm: Optional[bool] = None


# ------------------------------------------------------------------------------------------- customer
@router.get("/order-desk/resolve")
def resolve(code: str, request: Request) -> dict:
    return _call(_desk(request).resolve, code, _user(request, "desk-resolve", 60))


@router.post("/order-desk/assist")
def assist(body: AssistIn, request: Request) -> dict:
    user = _user(request, "desk-assist", 90)
    return _call(_desk(request).assist, body.code or "", user, body.text, body.cart, body.te)


@router.post("/order-desk/orders")
def place(body: OrderIn, request: Request) -> dict:
    user = _user(request, "desk-place", 20)
    payload = body.model_dump()
    return _call(_desk(request).place, user, body.code, {**payload, "items": [i for i in payload["items"]]})


@router.get("/order-desk/mine")
def mine(request: Request) -> dict:
    return {"orders": _call(_desk(request).mine, _user(request, "desk-mine", 120))}


@router.get("/order-desk/mine/{order_id}")
def mine_one(order_id: str, request: Request) -> dict:
    return _call(_desk(request).view_mine, _user(request, "desk-track", 240), order_id)


@router.post("/order-desk/mine/{order_id}/cancel")
def mine_cancel(order_id: str, request: Request) -> dict:
    return _call(_desk(request).cancel_mine, _user(request, "desk-cancel", 30), order_id)


# ------------------------------------------------------------------------------------------- shop
@router.get("/businesses/{business_id}/desk/orders")
def desk_orders(business_id: str, request: Request, lane: str = "active") -> dict:
    return _call(_desk(request).orders, business_id, _user(request, "desk", 300), lane)


@router.get("/businesses/{business_id}/desk/orders/{order_id}")
def desk_order(business_id: str, order_id: str, request: Request) -> dict:
    return _call(_desk(request).order, business_id, _user(request, "desk", 300), order_id)


@router.post("/businesses/{business_id}/desk/orders")
def desk_place(business_id: str, body: StaffOrderIn, request: Request) -> dict:
    user = _user(request, "desk-staff-place", 120)
    payload = body.model_dump()
    return _call(_desk(request).place, user, None, payload, business_id=business_id, source=body.source)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/confirm")
def desk_confirm(business_id: str, order_id: str, body: ConfirmIn, request: Request) -> dict:
    return _call(_desk(request).confirm, business_id, _user(request, "desk", 300), order_id, body.decisions, body.note)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/reject")
def desk_reject(business_id: str, order_id: str, body: ReasonIn, request: Request) -> dict:
    return _call(_desk(request).reject, business_id, _user(request, "desk", 300), order_id, body.reason)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/advance")
def desk_advance(business_id: str, order_id: str, body: AdvanceIn, request: Request) -> dict:
    return _call(_desk(request).advance, business_id, _user(request, "desk", 300), order_id, body.stage, body.assignee, body.assignee_user)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/bill")
def desk_bill(business_id: str, order_id: str, body: BillIn, request: Request) -> dict:
    return _call(_desk(request).bill, business_id, _user(request, "desk", 300), order_id, body.payments, body.client_txn_id, body.customer_id)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/assign")
def desk_assign(business_id: str, order_id: str, body: AssigneeIn, request: Request) -> dict:
    return _call(_desk(request).assign, business_id, _user(request, "desk", 300), order_id, body.assignee, body.assignee_user)


@router.post("/businesses/{business_id}/desk/assist")
def desk_assist(business_id: str, body: AssistIn, request: Request) -> dict:
    return _call(_desk(request).assist_counter, business_id, _user(request, "desk-assist", 120), body.text, body.cart, body.te)


@router.get("/businesses/{business_id}/desk/people")
def desk_people(business_id: str, request: Request) -> dict:
    return _call(_desk(request).people, business_id, _user(request, "desk", 300))


@router.get("/businesses/{business_id}/desk/settings")
def desk_settings(business_id: str, request: Request) -> dict:
    """Who is told about each step (new order / kitchen / ready / delivery) + auto-confirm. Owner only."""
    return _call(_desk(request).desk_settings, business_id, _user(request, "desk", 120))


@router.put("/businesses/{business_id}/desk/settings")
def desk_settings_save(business_id: str, body: DeskSettingsIn, request: Request) -> dict:
    return _call(_desk(request).set_desk_settings, business_id, _user(request, "desk", 120), body.routing, body.auto_confirm)


@router.get("/businesses/{business_id}/sales")
def sales(business_id: str, request: Request, period: str = "day", date: str = "") -> dict:
    """Today / week / month sales from the shop's own bills (owner, manager, accountant)."""
    from app.services.pos_sales import PosSales

    return _call(PosSales(_store(request)).summary, business_id, _user(request, "sales", 120), period, date)


@router.get("/businesses/{business_id}/desk/menu")
def desk_menu(business_id: str, request: Request) -> dict:
    return _call(_desk(request).menu_admin, business_id, _user(request, "desk", 300))


@router.post("/businesses/{business_id}/desk/menu/parse")
def desk_menu_parse(business_id: str, body: MenuTextIn, request: Request) -> dict:
    return _call(_desk(request).parse_menu, business_id, _user(request, "desk", 300), body.text)


@router.post("/businesses/{business_id}/desk/menu/photo")
def desk_menu_photo(business_id: str, body: MenuPhotoIn, request: Request) -> dict:
    """A photo of the menu -> items + prices as a preview (nothing is saved until /menu/import)."""
    import base64

    photos = []
    for entry in body.images:
        raw = str(entry.get("data") or "")
        if len(raw) > 6_000_000:
            raise HTTPException(status_code=413, detail="Photo too large. Use a smaller picture.")
        try:
            data = base64.b64decode(raw, validate=False)
        except Exception:
            raise HTTPException(status_code=400, detail="Photo could not be read.")
        mime = str(entry.get("mime") or "image/jpeg").lower()
        if mime not in ("image/jpeg", "image/png", "image/webp"):
            raise HTTPException(status_code=400, detail="Send a JPEG or PNG photo.")
        photos.append((data, mime))
    container = getattr(request.app.state, "container", None)
    service = getattr(container, "universal_image_service", None)
    return _call(_desk(request).parse_menu_photo, business_id, _user(request, "desk-photo", 20), photos, service)


@router.post("/businesses/{business_id}/desk/menu/import")
def desk_menu_import(business_id: str, body: MenuImportIn, request: Request) -> dict:
    out = _call(_desk(request).import_menu, business_id, _user(request, "desk", 120), [i.model_dump() for i in body.items], body.rate_bp)
    try:  # online listings follow the new prices
        from app.api.routes.pos import _online_sync

        _online_sync(request, business_id, None)
    except Exception:
        pass
    return out


@router.post("/businesses/{business_id}/desk/menu/{product_id}/availability")
def desk_availability(business_id: str, product_id: str, body: AvailabilityIn, request: Request) -> dict:
    return _call(_desk(request).set_availability, business_id, _user(request, "desk", 300), product_id, body.available)


@router.post("/businesses/{business_id}/desk/menu/{product_id}/today-only")
def desk_today_only(business_id: str, product_id: str, body: TodayOnlyIn, request: Request) -> dict:
    return _call(_desk(request).set_today_only, business_id, _user(request, "desk", 300), product_id, body.today_only)


@router.get("/businesses/{business_id}/desk/qr")
def desk_qr(business_id: str, request: Request) -> dict:
    return _call(_desk(request).qr_codes, business_id, _user(request, "desk", 120))


@router.post("/businesses/{business_id}/quick-bill")
def quick_bill(business_id: str, body: QuickBillIn, request: Request) -> dict:
    """The calculator bill as a REAL bill: items, rate, GST only for a registered shop, advance and pending."""
    from app.services.pos_quick_bill import PosQuickBill

    return _call(PosQuickBill(_store(request)).make, business_id, _user(request, "pos-quick", 120), body.model_dump())


class FillFieldIn(BaseModel):
    key: str = Field(max_length=60)
    label: str = Field(default="", max_length=80)
    kind: str = Field(default="text", pattern="^(text|number|phone|choice)$")
    options: List[str] = Field(default_factory=list, max_length=20)


class FormFillIn(BaseModel):
    fields: List[FillFieldIn] = Field(min_length=1, max_length=40)
    text: str = Field(min_length=1, max_length=600)
    locale: str = Field(default="te", max_length=8)


@router.post("/form-fill")
def form_fill(body: FormFillIn, request: Request) -> dict:
    """One mic at the bottom of a page: the words become the page's box values (model maps, rules check)."""
    from app.api.routes.pos import _phraser
    from app.services import form_fill as service

    _user(request, "form-fill", 60)
    phrase, metered = _phraser(request, body.locale)
    if metered and metered.get("blocked"):
        phrase = None
    out = service.fill([f.model_dump() for f in body.fields], body.text, locale=body.locale, phrase=phrase)
    return {"values": out["values"], "used_ai": out["used_ai"]}
