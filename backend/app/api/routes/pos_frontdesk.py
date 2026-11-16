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
    amount_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    # Billed by the menu NUMBER ("3 two"): item_no + count; the amount then comes from the menu price.
    item_no: int = Field(default=0, ge=0, le=100000)
    count: int = Field(default=0, ge=0, le=1000)
    qty_milli: int = Field(default=0, ge=0, le=10_000_000)
    rate_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)


class QuickBillIn(BaseModel):
    lines: List[QuickLineIn] = Field(min_length=1, max_length=100)
    advance_paise: int = Field(default=0, ge=0, le=10_00_00_000_00)
    method: str = Field(default="cash", pattern="^(cash|upi|card|bank_transfer|phonepe|gpay|paytm|bhim|other_upi)$")
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


@router.get("/businesses/{business_id}/bills")
def bill_history(business_id: str, request: Request, date_from: str = "", date_to: str = "", due: bool = False,
                 q: str = "") -> dict:
    return _call(_bills(request).history, business_id, _user(request, "bills", 300), date_from=date_from[:10],
                 date_to=date_to[:10], only_due=due, query=q[:40])


@router.get("/me/bills")
def my_bills(request: Request) -> dict:
    """Bills shops sent to the signed-in person's number, with the shop's own UPI pay link for any balance."""
    return {"bills": _call(_bills(request).my_bills, _user(request, "my-bills", 300))}


@router.post("/me/bills/{token}/paid")
def my_bill_paid(token: str, body: SaysPaidIn, request: Request) -> dict:
    _user(request, "my-bills", 60)
    return _call(_bills(request).customer_says_paid, token, body.app)


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
    rows = "".join(
        f'<tr><td>{esc(str(l["name"]))} × {l["qty_milli"] / 1000:g}</td><td class="r">{_rupees(int(l["amount_paise"] or 0))}</td></tr>'
        for l in bill["lines"])
    upi = next((m.get("upi_link") for m in bill["pay"] if m.get("upi_link")), "")
    if bill["status"] == "cancelled":
        action = '<p class="m">This bill was cancelled · ఈ బిల్లు రద్దు అయింది.</p>'
    elif bill["due_paise"] <= 0:
        paid = (" · " + esc(", ".join(bill["paid_with"]))) if bill["paid_with"] else ""
        action = f'<p class="ok">కట్టారు ✓ Paid{paid}</p>'
    elif upi:
        action = (f'<a class="b" href="{esc(upi, quote=True)}">UPI లో {_rupees(bill["due_paise"])} కట్టండి · Pay</a>'
                  '<p class="m">PhonePe / Google Pay / Paytm / BHIM / మీ బ్యాంక్ యాప్ — మొత్తం ముందే నిండి ఉంటుంది. '
                  'డబ్బు నేరుగా షాప్‌కి వెళ్తుంది; ASKODOX పట్టుకోదు.</p>')
    else:
        action = f'<p class="m">కట్టాల్సింది {_rupees(bill["due_paise"])} — షాప్‌లో కట్టండి · Pay at the shop.</p>'
    page = ('<!doctype html><html lang="te"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,'
            'initial-scale=1"><title>' + esc(bill["shop"]) + ' · ' + esc(str(bill["number"])) + '</title><style>'
            'body{font-family:system-ui,sans-serif;background:#f3f4f6;margin:0;padding:16px;color:#1b2333}'
            '.c{background:#fff;border-radius:16px;padding:18px;max-width:440px;margin:12px auto;border:1px solid #e2e5ea}'
            'h1{font-size:22px;margin:0 0 2px;color:#16203f}table{width:100%;border-collapse:collapse;margin-top:12px}'
            'td{padding:6px 0;border-bottom:1px solid #eef0f3;font-size:15px}.r{text-align:right}.t td{font-weight:700;'
            'font-size:18px;border:0}.b{display:block;background:#2f5bd3;color:#fff;padding:16px;border-radius:14px;'
            'text-decoration:none;font-weight:700;margin-top:16px;text-align:center}.m{color:#5b6475;font-size:13px}'
            '.ok{color:#1f7a4a;font-weight:700;font-size:17px}.d{background:#16203f;color:#fff}.d .m{color:#d5daea}'
            '.d a{display:block;background:#fff;color:#16203f;padding:12px;border-radius:12px;text-align:center;'
            'text-decoration:none;font-weight:700;margin-top:10px}@media print{.d,.b{display:none}}</style></head><body>'
            '<div class="c"><h1>' + esc(bill["shop"]) + '</h1><div class="m">బిల్లు ' + esc(str(bill["number"])) + ' · '
            + esc(str(bill["issued_at"])[:10]) + '</div><table>' + rows + '<tr class="t"><td>మొత్తం · Total</td>'
            '<td class="r">' + _rupees(bill["total_paise"]) + '</td></tr></table>' + action + '</div>'
            '<div class="c d"><b>తర్వాతి సారి బిల్లులు నేరుగా యాప్‌లోనే</b><div class="m">ASKODOX లో మీ బిల్లులు, ఆర్డర్లు ఒకే '
            'చోట.</div><a href="https://askodox.com">ASKODOX</a></div></body></html>')
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
