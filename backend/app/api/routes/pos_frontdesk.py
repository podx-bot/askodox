"""Front Desk APIs: the customer's order QR / menu / receptionist / tracking and the shop's order desk + spoken menu.

Customer routes (any signed-in person): ``/api/pos/order-desk/*``.
Shop routes (floor staff, role-checked in the service): ``/api/pos/businesses/{id}/desk/*``.
"""
from __future__ import annotations

from datetime import datetime, timedelta
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
        def notify(user_id: str, title: str, body: str, route: str, event_key: str, speak=None) -> None:
            if speak:
                # the phone shows ONE notification and SAYS it (type=say), even with ASKODOX closed
                push_service(container).send_data_async(user_id, data={**speak, "route": route}, event_key=event_key,
                                                        ttl_seconds=300)
                return
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
    text: str = Field(min_length=1, max_length=20000)


class MenuPhotoIn(BaseModel):
    """Up to 4 photos of the menu, each base64 (JPEG / PNG), about 4 MB at most."""
    images: List[Dict[str, str]] = Field(min_length=1, max_length=4)


class MenuItemIn(BaseModel):
    name: str = Field(max_length=80)
    price_paise: int = Field(ge=1, le=10_00_00_000_00)
    unit: str = Field(default="plate", max_length=10)
    today_only: bool = False
    menu_group: str = Field(default="", max_length=40)
    food_type: str = Field(default="", pattern="^(|veg|nonveg|egg)$")


class MenuImportIn(BaseModel):
    items: List[MenuItemIn] = Field(min_length=1, max_length=200)
    rate_bp: int = Field(default=0, ge=0, le=4000)


class AvailabilityIn(BaseModel):
    available: bool


class TodayOnlyIn(BaseModel):
    today_only: bool


class QuickLineIn(BaseModel):
    name: str = Field(default="", max_length=80)
    amount_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    # Billed by the menu NUMBER ("3 two"): item_no + count; the amount then comes from the menu price.
    item_no: int = Field(default=0, ge=0, le=100000)
    count: int = Field(default=0, ge=0, le=1000)
    qty_milli: int = Field(default=0, ge=0, le=10_000_000)
    rate_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)


class QuickBillIn(BaseModel):
    lines: List[QuickLineIn] = Field(min_length=1, max_length=100)
    advance_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    method: str = Field(default="cash", pattern="^(cash|upi|online|card|bank_transfer|phonepe|gpay|paytm|bhim|other_upi)$")
    cash_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    online_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    revise_of: str = Field(default="", max_length=60)
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


class AskIn(BaseModel):
    kinds: List[str] = Field(default_factory=list, max_length=8)
    text: str = Field(default="", max_length=160)
    qty: int = Field(default=1, ge=1, le=9)


class CustomRequestIn(BaseModel):
    key: str = Field(default="", max_length=40)
    en: str = Field(default="", max_length=40)
    te: str = Field(default="", max_length=40)


class RequestSettingsIn(BaseModel):
    off: Optional[List[str]] = Field(default=None, max_length=12)
    custom: Optional[List[CustomRequestIn]] = Field(default=None, max_length=8)


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


class PayChoiceIn(BaseModel):
    choice: str = Field(pattern="^(cash|online)$")


@router.post("/order-desk/mine/{order_id}/pay-choice")
def mine_pay_choice(order_id: str, body: PayChoiceIn, request: Request) -> dict:
    """The customer says how they will pay: cash (at the counter / table) or online (the shop's own UPI)."""
    return _call(_desk(request).set_pay_choice, _user(request, "desk-paychoice", 30), order_id, body.choice)


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


@router.get("/order-desk/shops")
def desk_shop_search(request: Request, q: str = "") -> dict:
    """Find a shop by its name (the box beside the QR scanner): shops with a menu, open ones first."""
    _user(request, "desk-search", 120)
    return {"shops": _desk(request).search_shops(q[:60])}


@router.get("/shopping")
def askodox_shopping(request: Request, q: str = "", lat: Optional[float] = None, lng: Optional[float] = None) -> dict:
    """ASKODOX Shopping (owner 2026-11-18): businesses on ASKODOX first (by name or by what their menu has), then the
    affiliate store items that match what was searched. No Google / web / videos here -- that stays in the main chat."""
    from app.api.routes.affiliate_catalog import catalog
    from app.services import affiliate_catalog as ac

    _user(request, "shopping", 120)
    q = q[:80]
    near = (lat, lng) if lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180 else None
    shops = _desk(request).shopping(q, near=near)  # owner 2026-11-19: nearest first when the place is known
    items: list = []
    if len(q.strip()) >= 2:
        try:
            items = [ac.result_row(i) for i in catalog(request.app.state.container).search(q, limit=8)]
        except Exception:  # a catalog problem never hides our shops
            items = []
    return {"query": q, "shops": shops, "items": items}


@router.get("/businesses/{business_id}/desk/qr")
def desk_qr(business_id: str, request: Request) -> dict:
    return _call(_desk(request).qr_codes, business_id, _user(request, "desk", 120))


@router.post("/businesses/{business_id}/quick-bill")
def quick_bill(business_id: str, body: QuickBillIn, request: Request) -> dict:
    """The calculator bill as a REAL bill: items, rate, GST only for a registered shop, advance and pending."""
    from app.services.pos_quick_bill import PosQuickBill

    return _call(PosQuickBill(_store(request)).make, business_id, _user(request, "pos-quick", 120), body.model_dump())


# ---------------------------------------------------------------- bills: send, pay later, history, customer inbox
def _bills(request: Request):
    from app.api.routes.payment_methods import payment_methods
    from app.services.pos_bills import PosBills
    from app.services.push_service import push_service

    container: Any = request.app.state.container
    store = _store(request)
    existing = getattr(container, "pos_bills", None)
    if existing is None or existing.store is not store:
        def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)

        methods = payment_methods(container)

        def pay_to(owner: str, amount_paise: int, note: str, ref: str) -> List[Dict[str, Any]]:
            return methods.pay_to(owner, amount=amount_paise / 100.0, note=note, reference=ref)

        existing = PosBills(store, notify=notify, pay_to=pay_to)
        try:
            container.pos_bills = existing
        except Exception:
            pass
    return existing


class BillSendIn(BaseModel):
    phone: str = Field(min_length=10, max_length=20)


class BillSettleIn(BaseModel):
    pay: str = Field(default="cash", max_length=20)
    amount_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    client_txn_id: str = Field(min_length=8, max_length=64)


class SaysPaidIn(BaseModel):
    app: str = Field(default="", max_length=20)


@router.post("/businesses/{business_id}/bills/{invoice_id}/send")
def bill_send(business_id: str, invoice_id: str, body: BillSendIn, request: Request) -> dict:
    """The bill to the customer's number: their ASKODOX inbox when they use the app, else a WhatsApp text + link."""
    from app.api.routes.partners import _public_base

    return _call(_bills(request).send, business_id, _user(request, "bill-send", 120), invoice_id, body.phone,
                 base_url=_public_base(request))


@router.post("/businesses/{business_id}/bills/{invoice_id}/settle")
def bill_settle(business_id: str, invoice_id: str, body: BillSettleIn, request: Request) -> dict:
    return _call(_bills(request).settle, business_id, _user(request, "bill-settle", 120), invoice_id, body.pay,
                 body.amount_paise, body.client_txn_id)


class ChatBillIn(BaseModel):
    text: str = Field(min_length=1, max_length=400)
    te: bool = True


@router.post("/chat-bill")
def chat_bill(body: ChatBillIn, request: Request) -> dict:
    """Main chat, owner 2026-11-19: item NUMBERS said by a shop's own staff -> the bill preview from the shop's own
    numbered items (no AI call, no guessed items). ``card`` is null when the words are not a number bill or the caller
    sells in no shop -- the chat then answers normally. The real bill = ``/businesses/{id}/quick-bill``."""
    from app.services.pos_chat_bill import PosChatBill, parse, reply_text

    if not parse(body.text):
        return {"card": None}
    card = _call(PosChatBill(_store(request)).card, _user(request, "chat-bill", 120), body.text)
    if card is None:
        return {"card": None}
    return {"card": card, "reply": reply_text(card, body.te)}


@router.post("/businesses/{business_id}/bills/{invoice_id}/printed")
def bill_printed(business_id: str, invoice_id: str, request: Request) -> dict:
    """The phone printed this bill; history stops flagging it as "print pending"."""
    return _call(_bills(request).mark_printed, business_id, _user(request, "bill-printed", 300), invoice_id)


@router.get("/businesses/{business_id}/bills")
def bill_history(business_id: str, request: Request, date_from: str = "", date_to: str = "", due: bool = False,
                 q: str = "") -> dict:
    return _call(_bills(request).history, business_id, _user(request, "bills", 300), date_from=date_from[:10],
                 date_to=date_to[:10], only_due=due, query=q[:40])


@router.get("/me/bills")
def my_bills(request: Request) -> dict:
    """Bills shops sent to the signed-in person's number, with the shop's own UPI pay link for any balance."""
    bills = _call(_bills(request).my_bills, _user(request, "my-bills", 300))
    try:  # the date the person gave for a pending bill ("I will pay on ...")
        given = dues_followup(request.app.state.container, _store(request), _bills(request)).promises(
            [b["invoice_id"] for b in bills if int(b.get("due_paise") or 0) > 0])
        for b in bills:
            b["promised_date"] = given.get(b["invoice_id"], "")
    except Exception:
        pass
    return {"bills": bills}


@router.post("/me/bills/{token}/paid")
def my_bill_paid(token: str, body: SaysPaidIn, request: Request) -> dict:
    _user(request, "my-bills", 60)
    return _call(_bills(request).customer_says_paid, token, body.app)


class PromiseIn(BaseModel):
    date: str


def dues_followup(container: Any, store: Any, bills: Any):
    from app.services.pos_dues_followup import PosDuesFollowup
    from app.services.push_service import push_service

    existing = getattr(container, "pos_dues_followup", None)
    if existing is None or existing.store is not store:
        def notify(user_id: str, title: str, body: str, route: str, event_key: str) -> None:
            push_service(container).notify_async(user_id, title=title, body=body, route=route, event_key=event_key)

        existing = PosDuesFollowup(store, bills, notify=notify)
        try:
            container.pos_dues_followup = existing
        except Exception:
            pass
    return existing


@router.post("/me/bills/{token}/promise")
def my_bill_promise(token: str, body: PromiseIn, request: Request) -> dict:
    """The customer's own answer to a baaki reminder: the date they will pay (the shop is told; reminders wait)."""
    user = _user(request, "my-bills", 60)
    return _call(dues_followup(request.app.state.container, _store(request), _bills(request)).promise, user, token,
                 body.date[:10])


bill_page_router = APIRouter(tags=["POS"])


def _rupees(paise: int) -> str:
    return f"₹{paise // 100:,}" if paise % 100 == 0 else f"₹{paise / 100:,.2f}"


@bill_page_router.get("/b/{token}")
def bill_page(token: str, request: Request):
    """Public page of ONE bill (the unguessable link the shop sent on WhatsApp): items, total, and a button that
    opens the customer's own UPI app for the balance. Read-only; money goes straight to the shop."""
    import html as _html

    from fastapi.responses import HTMLResponse

    bill = _bills(request).public(token)
    if bill is None:
        return HTMLResponse("<h3>This bill link is not valid · ఈ బిల్లు లింక్ సరైనది కాదు.</h3>", status_code=404)
    esc = _html.escape
    M = "#9d1d5a"

    def qty(l: Dict[str, Any]) -> str:
        q = l["qty_milli"] / 1000
        return f"{q:g} {esc(str(l.get('unit') or ''))}".strip() if l.get("unit") not in (None, "", "pcs", "plate") else f"{q:g}"

    lines = bill.get("paper_lines") or bill["lines"]
    rows = "".join(
        f'<tr><td>{esc(str(l["name"]))}</td><td class="c">{qty(l)}</td>'
        f'<td class="r">{_rupees(int(l.get("rate_paise") or 0)) if l.get("rate_paise") else ""}</td>'
        f'<td class="r">{_rupees(int(l["amount_paise"] or 0))}</td></tr>' for l in lines)
    kind = bill.get("bill_kind") or ("credit" if bill["due_paise"] > 0 else "cash")
    title = {"cash": "క్యాష్ బిల్లు", "online": "ఆన్‌లైన్ బిల్లు", "mixed": "క్యాష్ + ఆన్‌లైన్ బిల్లు",
             "credit": "క్రెడిట్ బిల్లు", "part": "బిల్లు (కొంత బాకీ)"}.get(kind, "బిల్లు")
    tax = (f'<div class="k"><span>GST</span><span>{_rupees(int(bill.get("tax_paise") or 0))}</span></div>'
           if bill.get("gst") else '<div class="k"><span>GST</span><span>లేదు</span></div>')
    disc = (f'<div class="k"><span>తగ్గింపు</span><span>−{_rupees(int(bill["discount_paise"]))}</span></div>'
            if bill.get("discount_paise") else "")
    apps = ", ".join(bill.get("online_apps") or [])
    paid = ""
    if bill.get("cash_paise"):
        paid += f'<div class="k"><span>క్యాష్</span><b>{_rupees(int(bill["cash_paise"]))}</b></div>'
    if bill.get("online_paise"):
        paid += f'<div class="k"><span>ఆన్‌లైన్{(" (" + esc(apps) + ")") if apps else ""}</span><b>{_rupees(int(bill["online_paise"]))}</b></div>'
    if bill["due_paise"] > 0:
        paid += f'<div class="k due"><span>బాకీ (ఇంకా కట్టాలి)</span><b>{_rupees(bill["due_paise"])}</b></div>'
    upi = next((m.get("upi_link") for m in bill["pay"] if m.get("upi_link")), "")
    if bill["status"] == "cancelled":
        action = '<p class="m">ఈ బిల్లు రద్దు అయింది (సవరించిన బిల్ వేరే నంబర్‌తో వస్తుంది) · This bill was cancelled.</p>'
    elif bill["due_paise"] <= 0:
        action = '<p class="ok">కట్టారు ✓ Paid</p>'
    elif upi:
        action = (f'<a class="b" href="{esc(upi, quote=True)}">UPI లో {_rupees(bill["due_paise"])} కట్టండి · Pay</a>'
                  '<p class="m">PhonePe / Google Pay / Paytm / BHIM / మీ బ్యాంక్ యాప్ — మొత్తం ముందే నిండి ఉంటుంది. '
                  'డబ్బు నేరుగా షాప్‌కి వెళ్తుంది; ASKODOX పట్టుకోదు.</p>')
    else:
        action = f'<p class="m">కట్టాల్సింది {_rupees(bill["due_paise"])} — షాప్‌లో కట్టండి · Pay at the shop.</p>'
    shop_line = " · ".join(x for x in [esc(bill.get("shop_category") or ""), esc(bill.get("shop_address") or "")] if x)
    gst_line = (f'GSTIN: {esc(bill["shop_gstin"])}' if bill.get("shop_gstin") else "GST లేదు")
    phone = f'Cell: {esc(bill.get("shop_phone") or "")} · ' if bill.get("shop_phone") else ""
    who = esc(bill.get("customer_name") or "")
    page = ('<!doctype html><html lang="te"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,'
            'initial-scale=1"><title>' + esc(bill["shop"]) + ' · ' + esc(str(bill["number"])) + '</title><style>'
            'body{font-family:system-ui,sans-serif;background:#f3f4f6;margin:0;padding:12px;color:#1f1f1f}'
            f'.p{{background:#fff;border:2px solid {M};border-radius:6px;max-width:460px;margin:8px auto;padding-bottom:10px}}'
            f'.top{{display:flex;justify-content:space-between;padding:6px 10px;color:{M};font-weight:800;font-size:13px}}'
            f'.hd{{background:#fce9f1;text-align:center;padding:10px;border-top:1px solid {M};border-bottom:1px solid {M}}}'
            f'.hd h1{{margin:0;font-size:22px;color:{M}}}.hd div{{font-size:12.5px}}'
            f'.cu{{padding:8px 10px;border-bottom:1px dotted {M};font-size:14px}}'
            'table{width:100%;border-collapse:collapse;font-size:14px}td{padding:6px 8px}'
            f'th{{color:{M};text-align:left;padding:6px 8px;border-bottom:1px solid {M};font-size:13px}}'
            '.c{text-align:center}.r{text-align:right}'
            f'.tot{{margin:4px 10px 0;border-top:1px solid {M};padding-top:4px;font-size:14px}}'
            '.k{display:flex;justify-content:space-between;padding:2px 0}'
            f'.g{{font-weight:900;font-size:17px;color:{M}}}.pay{{margin:8px 10px 0;background:#faf5f8;border-radius:6px;padding:6px 8px}}'
            '.due{color:#b45309}.b{display:block;background:#2f5bd3;color:#fff;padding:14px;border-radius:12px;'
            'text-decoration:none;font-weight:700;margin:12px 10px 0;text-align:center}.m{color:#5b6475;font-size:13px;margin:8px 10px}'
            '.ok{color:#1f7a4a;font-weight:700;font-size:17px;margin:10px}'
            f'.f{{text-align:center;font-size:11.5px;color:{M};padding-top:8px}}@media print{{.b{{display:none}}}}</style></head><body>'
            '<div class="p"><div class="top"><span>నెం. ' + esc(str(bill["number"])) + '</span><span>' + title + '</span><span>'
            + esc(str(bill["issued_at"])[:10]) + '</span></div><div class="hd"><h1>' + esc(bill["shop"]) + '</h1>'
            + (f'<div>{shop_line}</div>' if shop_line else '') + f'<div><b>{phone}{gst_line}</b></div></div>'
            + (f'<div class="cu">శ్రీ <b>{who}</b></div>' if who else '')
            + '<table><tr><th>ఐటమ్</th><th class="c">పరిమాణం</th><th class="r">రేటు</th><th class="r">మొత్తం</th></tr>'
            + rows + '</table><div class="tot">' + disc + tax
            + (f'<div class="k"><span>రౌండ్ ఆఫ్</span><span>{_rupees(int(bill["round_off_paise"]))}</span></div>' if bill.get("round_off_paise") else "")
            + '<div class="k g"><span>మొత్తం · Total</span><span>' + _rupees(bill["total_paise"]) + '</span></div></div>'
            + (f'<div class="pay">{paid}</div>' if paid else '') + action
            + '<div class="f">ధన్యవాదాలు · ASKODOX ద్వారా పంపిన బిల్లు</div></div></body></html>')
    return HTMLResponse(page, headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
                                       "X-Robots-Tag": "noindex"})


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


# ------------------------------------------------------------------------------------------- table service requests
@router.get("/order-desk/mine/{order_id}/requests")
def my_requests(order_id: str, request: Request) -> dict:
    return _call(_desk(request).requests.for_order, _user(request, "desk", 300), order_id)


@router.post("/order-desk/mine/{order_id}/requests")
def ask_service(order_id: str, body: AskIn, request: Request) -> dict:
    """Water / extra gravy / onions / bring the bill / call the waiter -- tapped from the shop's list or said in words."""
    return _call(_desk(request).requests.ask, _user(request, "desk", 120), order_id, body.kinds, body.text, body.qty)


@router.post("/order-desk/requests/{request_id}/cancel")
def cancel_service(request_id: str, request: Request) -> dict:
    return _call(_desk(request).requests.cancel_mine, _user(request, "desk", 120), request_id)


@router.get("/businesses/{business_id}/desk/requests")
def desk_requests(business_id: str, request: Request) -> dict:
    return _call(_desk(request).requests.open_list, business_id, _user(request, "desk", 600))


@router.post("/businesses/{business_id}/desk/requests/{request_id}/done")
def desk_request_done(business_id: str, request_id: str, request: Request) -> dict:
    return _call(_desk(request).requests.done, business_id, _user(request, "desk", 300), request_id)


@router.get("/businesses/{business_id}/desk/request-settings")
def desk_request_settings(business_id: str, request: Request) -> dict:
    return _call(_desk(request).requests.settings, business_id, _user(request, "desk", 120))


@router.put("/businesses/{business_id}/desk/request-settings")
def desk_request_settings_save(business_id: str, body: RequestSettingsIn, request: Request) -> dict:
    custom = None if body.custom is None else [c.model_dump() for c in body.custom]
    return _call(_desk(request).requests.set_settings, business_id, _user(request, "desk", 120), body.off, custom)


# ------------------------------------------------------------------------------------------- menu sort (owner 2026-11-17)
class MenuSortRowIn(BaseModel):
    id: str = Field(max_length=60)
    menu_group: str = Field(default="", max_length=40)
    food_type: str = Field(default="", pattern="^(|veg|nonveg|egg)$")
    name: Optional[str] = Field(default=None, max_length=120)
    item_no: Optional[int] = Field(default=None, ge=1, le=99999)


class MenuSortApplyIn(BaseModel):
    items: List[MenuSortRowIn] = Field(min_length=1, max_length=300)


@router.post("/businesses/{business_id}/desk/menu/sort")
def menu_sort(business_id: str, request: Request) -> dict:
    """Preview only: the model reads the item NAMES and proposes sections + veg / non-veg. Nothing is saved."""
    from app.services.pos_menu_sort import sort_menu

    user = _user(request, "menu-sort", 10)
    store = _store(request)
    with store._connect() as conn:
        _call(store._require, conn, business_id, user, "products")
    items = _call(_desk(request).menu_admin, business_id, user)["items"]
    service = getattr(request.app.state.container, "universal_ai_assistant_service", None)
    if service is None or not hasattr(service, "write_text"):
        raise HTTPException(503, "The AI helper is not available right now. Set sections by hand with ✏.")
    out = sort_menu([{"id": i["id"], "name": i["name"], "menu_group": i.get("menu_group", ""),
                      "food_type": i.get("food_type", "")} for i in items][:300], service.write_text)
    if not out["read"]:
        raise HTTPException(503, "Could not read the menu just now. Try again in a minute.")
    return out


@router.post("/businesses/{business_id}/desk/menu/sort/apply")
def menu_sort_apply(business_id: str, body: MenuSortApplyIn, request: Request) -> dict:
    user = _user(request, "menu-sort", 20)
    store = _store(request)
    saved = 0
    for row in body.items:
        change = {"menu_group": row.menu_group, "food_type": row.food_type}
        if row.name and row.name.strip():
            change["name"] = row.name.strip()
        _call(store.update_product, business_id, user, row.id, change)
        if row.item_no:
            # The printed menu number becomes the item number, unless another item of this shop already has it.
            with store._connect() as conn:
                taken = conn.execute("SELECT 1 FROM pos_products WHERE business_id = ? AND item_no = ? AND id != ?",
                                     (business_id, row.item_no, row.id)).fetchone()
                if not taken:
                    conn.execute("UPDATE pos_products SET item_no = ? WHERE id = ? AND business_id = ?",
                                 (row.item_no, row.id, business_id))
        saved += 1
    return {"saved": saved}


# ------------------------------------------------------------------------------------------- ratings, reviews, shop page
class RateIn(BaseModel):
    shop: Optional[int] = Field(default=None, ge=1, le=5)
    items: Dict[str, int] = Field(default_factory=dict)
    later: bool = False


class ReviewPhotoIn(BaseModel):
    data: str = Field(max_length=600_000)
    mime: str = Field(default="image/jpeg", max_length=20)


class ReviewIn(BaseModel):
    stars: int = Field(ge=1, le=5)
    text: str = Field(default="", max_length=800)
    photos: List[ReviewPhotoIn] = Field(default_factory=list, max_length=3)


class ReplyIn(BaseModel):
    text: str = Field(max_length=400)


class WelcomeIn(BaseModel):
    enabled: Optional[bool] = None
    hello: Optional[str] = Field(default=None, max_length=160)
    again: Optional[str] = Field(default=None, max_length=160)
    thanks: Optional[str] = Field(default=None, max_length=160)


@router.get("/order-desk/mine/{order_id}/rate")
def rate_ask(order_id: str, request: Request) -> dict:
    return {"ask": _call(_desk(request).ratings.ask, _user(request, "rate", 120), order_id)}


@router.post("/order-desk/mine/{order_id}/rate")
def rate(order_id: str, body: RateIn, request: Request) -> dict:
    return _call(_desk(request).ratings.rate, _user(request, "rate", 30), order_id, body.shop, body.items, body.later)


@router.get("/shops/{business_id}/page")
def shop_page(business_id: str, request: Request) -> dict:
    return _call(_desk(request).ratings.shop_page, business_id, _user(request, "shop-page", 120))


@router.post("/shops/{business_id}/review")
def write_review(business_id: str, body: ReviewIn, request: Request) -> dict:
    return _call(_desk(request).ratings.write_review, _user(request, "review", 10), business_id, body.stars, body.text,
                 [p.model_dump() for p in body.photos])


@router.delete("/shops/{business_id}/review")
def delete_review(business_id: str, request: Request) -> dict:
    return _call(_desk(request).ratings.delete_review, _user(request, "review", 20), business_id)


@router.post("/shops/{business_id}/reviews/{review_id}/reply")
def reply_review(business_id: str, review_id: str, body: ReplyIn, request: Request) -> dict:
    return _call(_desk(request).ratings.reply, business_id, _user(request, "review", 30), review_id, body.text)


@router.post("/shops/reviews/{review_id}/report")
def report_review(review_id: str, request: Request) -> dict:
    return _call(_desk(request).ratings.report, _user(request, "review", 20), review_id)


@router.get("/shops/{business_id}/photo/{kind}/{photo_id}")
def shop_photo(business_id: str, kind: str, photo_id: str, request: Request):
    from fastapi.responses import Response

    from app.services import rate_limit

    # Public like the shop page photos on a map (an <img> carries no sign-in); limited per client.
    rate_limit.check(request, "shop-photo", limit=300)
    if kind == "review":
        out = _call(_desk(request).ratings.photo, photo_id)
        return Response(out["image"], media_type=out["mime"], headers={"Cache-Control": "public, max-age=3600"})
    store = _store(request)
    with store._connect() as conn:
        row = conn.execute("SELECT image, mime FROM pos_product_photos WHERE business_id = ? AND product_id = ?",
                           (business_id, photo_id)).fetchone()
    if row is None:
        raise HTTPException(404, "Photo not found.")
    return Response(bytes(row["image"]), media_type=row["mime"], headers={"Cache-Control": "public, max-age=3600"})


@router.get("/businesses/{business_id}/welcome")
def welcome_settings(business_id: str, request: Request) -> dict:
    user = _user(request)
    store = _store(request)
    with store._connect() as conn:
        _call(store._require, conn, business_id, user, "settings")
        return _desk(request).ratings.welcome_settings(conn, business_id)


@router.put("/businesses/{business_id}/welcome")
def set_welcome(business_id: str, body: WelcomeIn, request: Request) -> dict:
    return _call(_desk(request).ratings.set_welcome, business_id, _user(request), body.model_dump())


@router.get("/businesses/{business_id}/bills/{invoice_id}/paper")
def bill_paper(business_id: str, invoice_id: str, request: Request) -> dict:
    """The bill as the customer sees it (shop details, lines, GST or none, cash / online / due)."""
    return _call(_bills(request).paper_for, business_id, _user(request), invoice_id)


# ------------------------------------------------------------------------------------------ the business hub + ASK bar
class BizAskIn(BaseModel):
    text: str = Field(min_length=1, max_length=400)
    page: str = Field(default="hub", max_length=40)
    lang: str = Field(default="te", pattern="^(te|en)$")


class AskConfirmIn(BaseModel):
    action: str = Field(max_length=30)
    product_id: str = Field(default="", max_length=60)
    price_paise: Optional[int] = Field(default=None, ge=1, le=100_000_000)
    amount_paise: Optional[int] = Field(default=None, ge=1, le=1_000_000_000)
    category: str = Field(default="", max_length=30)
    note: str = Field(default="", max_length=120)
    ref: str = Field(default="", max_length=20)


@router.get("/businesses/{business_id}/hub")
def business_hub(business_id: str, request: Request) -> dict:
    """Today's numbers for the hub and the 6 group pages (owner 2026-11-18). Members of the shop only."""
    from app.services import pos_hub

    user = _user(request, "hub", 240)
    store = _store(request)
    with store._connect() as conn:
        role = _call(store._require, conn, business_id, user, "view")
        out = pos_hub.summary(conn, business_id)
    out["role"] = role
    return out


@router.post("/businesses/{business_id}/ask")
def business_ask(business_id: str, body: BizAskIn, request: Request) -> dict:
    """The ASK bar: one sentence -> open a page, answer from the shop's own numbers, or ONE change waiting for ✓."""
    from app.services import pos_hub

    user = _user(request, "ask", 60)
    store = _store(request)
    with store._connect() as conn:
        _call(store._require, conn, business_id, user, "view")
        numbers = pos_hub.summary(conn, business_id)
    service = getattr(request.app.state.container, "universal_ai_assistant_service", None)
    if service is None or not hasattr(service, "write_text"):
        raise HTTPException(503, "The AI helper is not available right now.")
    intent = pos_hub.read(body.text, body.page, service.write_text)
    items: List[Dict[str, Any]] = []
    if intent["action"] in ("item_off", "item_on", "item_price"):
        items = _call(_desk(request).menu_admin, business_id, user)["items"]
    people: List[Dict[str, Any]] = []
    report = None
    if intent["action"] in ("staff_advance", "task_add", "att_mark"):
        people = [{"id": p["ref"], "name": p["name"]} for p in _call(_att(request).today, business_id, user)["people"]]
    if intent["action"] == "report":
        try:
            when = intent.get("when") or "today"
            if when in ("week", "month"):
                report = pos_hub.range_say(_reports(request).range(business_id, user, 7 if when == "week" else 30),
                                           body.lang == "te")
            else:
                from app.services.pos_store import IST

                day = (datetime.now(IST) - timedelta(days=1)).strftime("%Y-%m-%d") if when == "yesterday" else ""
                report = _reports(request).day(business_id, user, day)
        except Exception:
            report = None  # no reports permission: the page itself explains
    out = pos_hub.plan(intent, items, numbers, body.lang == "te", people=people, report=report)
    out["intent"] = intent["action"]
    return out


@router.post("/businesses/{business_id}/ask/confirm")
def business_ask_confirm(business_id: str, body: AskConfirmIn, request: Request) -> dict:
    from app.services import pos_hub

    user = _user(request, "ask-confirm", 60)
    return _call(pos_hub.run, body.model_dump(), store=_store(request), desk=_desk(request),
                 business_id=business_id, user=user)


# ------------------------------------------------------------------------------------------ cashbook + dues
class CashbookIn(BaseModel):
    kind: str = Field(pattern="^(income|expense)$")
    amount_paise: int = Field(ge=1, le=1_000_000_000)
    category: str = Field(default="other", max_length=30)
    note: str = Field(default="", max_length=120)
    local_date: str = Field(default="", max_length=10)
    client_txn_id: str = Field(default="", max_length=60)


def _cashbook(request: Request):
    from app.services.pos_cashbook import PosCashbook

    return PosCashbook(_store(request))


@router.get("/businesses/{business_id}/cashbook")
def cashbook_month(business_id: str, request: Request, month: str = "") -> dict:
    return _call(_cashbook(request).month, business_id, _user(request, "cashbook", 240), month[:7])


@router.post("/businesses/{business_id}/cashbook")
def cashbook_add(business_id: str, body: CashbookIn, request: Request) -> dict:
    return _call(_cashbook(request).add, business_id, _user(request, "cashbook-add", 120), body.model_dump())


@router.delete("/businesses/{business_id}/cashbook/{entry_id}")
def cashbook_remove(business_id: str, entry_id: str, request: Request, undo: bool = False) -> dict:
    return _call(_cashbook(request).remove, business_id, _user(request, "cashbook-add", 120), entry_id, undo)


@router.get("/businesses/{business_id}/dues")
def dues(business_id: str, request: Request) -> dict:
    """Everyone who still owes money, biggest first, with their bills (read from the bill history)."""
    user = _user(request, "dues", 240)
    bills = _call(_bills(request).history, business_id, user, only_due=True, limit=1000)["bills"]
    return _cashbook(request).dues(business_id, user, bills)


# ------------------------------------------------------------------------------------------ attendance, salary, tasks
class CheckIn(BaseModel):
    action: str = Field(pattern="^(in|out|leave)$")
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lng: Optional[float] = Field(default=None, ge=-180, le=180)
    method: str = Field(default="device_lock", pattern="^(device_lock|photo)$")
    photo: str = Field(default="", max_length=600_000)
    for_ref: str = Field(default="", max_length=20)


class MarkIn(BaseModel):
    ref: str = Field(max_length=20)
    date: str = Field(max_length=10)
    status: str = Field(pattern="^(P|A|OT|leave|half)$")
    ot_min: int = Field(default=0, ge=0, le=1440)
    note: str = Field(default="", max_length=120)


class AttSettingsIn(BaseModel):
    start_time: Optional[str] = Field(default=None, max_length=5)
    end_time: Optional[str] = Field(default=None, max_length=5)
    grace_min: Optional[int] = Field(default=None, ge=0, le=180)
    radius_m: Optional[int] = Field(default=None, ge=30, le=5000)
    own_phone: Optional[bool] = None
    kiosk: Optional[bool] = None


class PayIn(BaseModel):
    salary_kind: str = Field(default="month", pattern="^(month|day)$")
    salary_paise: int = Field(default=0, ge=0, le=100_000_000)
    ot_rate_paise: int = Field(default=0, ge=0, le=10_000_000)


class StaffAdvanceIn(BaseModel):
    amount_paise: int = Field(ge=1, le=100_000_000)
    note: str = Field(default="", max_length=120)


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    ref: str = Field(max_length=20)
    due_at: str = Field(default="", max_length=25)


def _att(request: Request):
    from app.services.pos_attendance import PosAttendance

    desk = _desk(request)
    return PosAttendance(_store(request), notify=getattr(desk, "notify", None))


@router.get("/businesses/{business_id}/attendance/today")
def attendance_today(business_id: str, request: Request) -> dict:
    return _call(_att(request).today, business_id, _user(request, "att", 300))


@router.post("/businesses/{business_id}/attendance/check")
def attendance_check(business_id: str, body: CheckIn, request: Request) -> dict:
    return _call(_att(request).check, business_id, _user(request, "att-check", 60), body.action, lat=body.lat,
                 lng=body.lng, method=body.method, photo_b64=body.photo, for_ref=body.for_ref)


@router.post("/businesses/{business_id}/attendance/mark")
def attendance_mark(business_id: str, body: MarkIn, request: Request) -> dict:
    return _call(_att(request).mark, business_id, _user(request, "att-mark", 120), body.ref, body.date, body.status,
                 body.ot_min, body.note)


@router.get("/businesses/{business_id}/attendance/settings")
def attendance_settings(business_id: str, request: Request) -> dict:
    return _call(_att(request).get_settings, business_id, _user(request, "att", 120))


@router.put("/businesses/{business_id}/attendance/settings")
def attendance_settings_set(business_id: str, body: AttSettingsIn, request: Request) -> dict:
    return _call(_att(request).set_settings, business_id, _user(request, "att-mark", 60), body.model_dump())


@router.get("/businesses/{business_id}/attendance/month")
def attendance_month(business_id: str, request: Request, ref: str = "", month: str = "") -> dict:
    return _call(_att(request).month, business_id, _user(request, "att", 240), ref[:20], month[:7])


@router.get("/businesses/{business_id}/attendance/photo/{attendance_id}")
def attendance_photo(business_id: str, attendance_id: str, request: Request) -> dict:
    import base64

    image, mime = _call(_att(request).photo, business_id, _user(request, "att", 120), attendance_id)
    return {"image_base64": base64.b64encode(image).decode("ascii"), "mime": mime}


@router.put("/businesses/{business_id}/staff/{ref}/pay")
def staff_pay_set(business_id: str, ref: str, body: PayIn, request: Request) -> dict:
    return _call(_att(request).set_pay, business_id, _user(request, "att-mark", 60), ref[:20], body.model_dump())


@router.post("/businesses/{business_id}/staff/{ref}/advance")
def staff_advance(business_id: str, ref: str, body: StaffAdvanceIn, request: Request) -> dict:
    return _call(_att(request).advance, business_id, _user(request, "att-mark", 60), ref[:20], body.amount_paise, body.note)


@router.get("/businesses/{business_id}/salary")
def team_salary(business_id: str, request: Request, month: str = "") -> dict:
    return _call(_att(request).team_salary, business_id, _user(request, "att", 120), month[:7])


@router.post("/businesses/{business_id}/staff/{ref}/salary/{month}/paid")
def salary_paid(business_id: str, ref: str, month: str, request: Request) -> dict:
    return _call(_att(request).pay_salary, business_id, _user(request, "att-mark", 30), ref[:20], month[:7])


@router.get("/businesses/{business_id}/tasks")
def tasks(business_id: str, request: Request) -> dict:
    return _call(_att(request).tasks, business_id, _user(request, "tasks", 300))


@router.post("/businesses/{business_id}/tasks")
def task_add(business_id: str, body: TaskIn, request: Request) -> dict:
    return _call(_att(request).add_task, business_id, _user(request, "tasks", 120), body.title, body.ref, body.due_at)


@router.post("/businesses/{business_id}/tasks/{task_id}/done")
def task_done(business_id: str, task_id: str, request: Request, undo: bool = False) -> dict:
    return _call(_att(request).task_done, business_id, _user(request, "tasks", 120), task_id, not undo)


# ---------------------------------------------------------------- reports & analytics (owner 2026-11-18)
class ReportSettingsIn(BaseModel):
    night_push: Optional[bool] = None
    send_time: Optional[str] = Field(default=None, max_length=5)


def _reports(request: Request):
    from app.services.pos_reports import PosReports

    return PosReports(_store(request), notify=getattr(_desk(request), "notify", None))


@router.get("/businesses/{business_id}/reports/day")
def report_day(business_id: str, request: Request, date: str = "") -> dict:
    return _call(_reports(request).day, business_id, _user(request, "reports", 120), date[:10])


@router.get("/businesses/{business_id}/reports/range")
def report_range(business_id: str, request: Request, days: int = 7) -> dict:
    return _call(_reports(request).range, business_id, _user(request, "reports", 60), days)


@router.get("/businesses/{business_id}/reports/settings")
def report_settings(business_id: str, request: Request) -> dict:
    return _call(_reports(request).settings, business_id, _user(request, "reports", 120))


@router.put("/businesses/{business_id}/reports/settings")
def report_settings_save(business_id: str, body: ReportSettingsIn, request: Request) -> dict:
    return _call(_reports(request).save_settings, business_id, _user(request, "reports", 60), body.night_push, body.send_time)
