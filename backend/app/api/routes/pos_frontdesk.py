"""Front Desk APIs: the customer's order QR / menu / receptionist / tracking and the shop's order desk + spoken menu.

Customer routes (any signed-in person): ``/api/pos/order-desk/*``.
Shop routes (floor staff, role-checked in the service): ``/api/pos/businesses/{id}/desk/*``.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Request
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


class BillIn(BaseModel):
    payments: List[Dict[str, Any]] = Field(default_factory=list, max_length=6)
    client_txn_id: str = Field(default="", max_length=64)
    customer_id: Optional[str] = Field(default=None, max_length=60)


class MenuTextIn(BaseModel):
    text: str = Field(min_length=1, max_length=4000)


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
    assignee: str = Field(max_length=40)


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
    return _call(_desk(request).advance, business_id, _user(request, "desk", 300), order_id, body.stage, body.assignee)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/bill")
def desk_bill(business_id: str, order_id: str, body: BillIn, request: Request) -> dict:
    return _call(_desk(request).bill, business_id, _user(request, "desk", 300), order_id, body.payments, body.client_txn_id, body.customer_id)


@router.post("/businesses/{business_id}/desk/orders/{order_id}/assign")
def desk_assign(business_id: str, order_id: str, body: AssigneeIn, request: Request) -> dict:
    return _call(_desk(request).assign, business_id, _user(request, "desk", 300), order_id, body.assignee)


@router.post("/businesses/{business_id}/desk/assist")
def desk_assist(business_id: str, body: AssistIn, request: Request) -> dict:
    return _call(_desk(request).assist_counter, business_id, _user(request, "desk-assist", 120), body.text, body.cart, body.te)


@router.get("/businesses/{business_id}/desk/menu")
def desk_menu(business_id: str, request: Request) -> dict:
    return _call(_desk(request).menu_admin, business_id, _user(request, "desk", 300))


@router.post("/businesses/{business_id}/desk/menu/parse")
def desk_menu_parse(business_id: str, body: MenuTextIn, request: Request) -> dict:
    return _call(_desk(request).parse_menu, business_id, _user(request, "desk", 300), body.text)


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
