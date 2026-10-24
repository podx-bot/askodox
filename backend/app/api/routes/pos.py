"""ASKODOX Universal POS APIs (``/api/pos/...``).

Every route is token-proven (``_authenticated_app_user``) and the store checks
the caller's membership + role in that business on every call (owner /
manager / cashier / accountant). A business the caller does not belong to
answers 404, exactly like a missing one.

Public: GET /api/pos/meta  -- templates, units, GST rates, State codes, rule sources.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import pos_tax, rate_limit
from app.services.pos_store import PAY_METHODS, PERMISSIONS, ROLES, TEMPLATES, UNITS, PosError, PosStore

router = APIRouter(prefix="/api/pos", tags=["POS"])


def _store(request: Request) -> PosStore:
    container: Any = request.app.state.container
    existing = getattr(container, "pos_store", None)
    if existing is None:
        existing = PosStore(container.settings.database_path)
        try:
            container.pos_store = existing
        except Exception:
            pass
    return existing


def _user(request: Request, bucket: str = "pos", limit: int = 240) -> str:
    user = _authenticated_app_user(request)
    rate_limit.check(request, f"{bucket}:{user}", limit=limit)
    return user


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except PosError as error:
        raise HTTPException(status_code=error.status,
                            detail={"code": error.code, "message": error.message, **error.extra})


class BusinessIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    address: str = Field(default="", max_length=240)
    phone: str = Field(default="", max_length=20)
    registration_type: str = Field(default="unregistered", pattern="^(regular|composition|unregistered)$")
    gstin: Optional[str] = Field(default=None, max_length=15)
    state_code: Optional[str] = Field(default=None, max_length=2)
    template: str = Field(default="general", max_length=20)
    invoice_prefix: str = Field(default="INV", max_length=3)
    turnover_above_5cr: bool = False
    round_off: bool = False


class SettingsIn(BaseModel):
    name: Optional[str] = Field(default=None, max_length=80)
    address: Optional[str] = Field(default=None, max_length=240)
    phone: Optional[str] = Field(default=None, max_length=20)
    round_off: Optional[bool] = None
    turnover_above_5cr: Optional[bool] = None


class MemberIn(BaseModel):
    phone: str = Field(min_length=10, max_length=16)
    role: str = Field(pattern="^(manager|cashier|accountant|waiter|kitchen|removed)$")


class ProductIn(BaseModel):
    name: Optional[str] = Field(default=None, max_length=80)
    name_te: Optional[str] = Field(default=None, max_length=80)
    sku: Optional[str] = Field(default=None, max_length=40)
    barcode: Optional[str] = Field(default=None, max_length=64)
    hsn_sac: Optional[str] = Field(default=None, max_length=10)
    is_service: Optional[bool] = None
    unit: Optional[str] = Field(default=None, max_length=10)
    price_paise: Optional[int] = Field(default=None, ge=0)
    price_includes_tax: Optional[bool] = None
    rate_bp: Optional[int] = Field(default=None, ge=0)
    cess_bp: Optional[int] = Field(default=None, ge=0, le=30000)
    category: Optional[str] = Field(default=None, max_length=20)
    track_stock: Optional[bool] = None
    track_batches: Optional[bool] = None
    low_stock_milli: Optional[int] = Field(default=None, ge=0)
    opening_stock_milli: Optional[int] = None
    active: Optional[bool] = None


class StockIn(BaseModel):
    product_id: str = Field(max_length=40)
    kind: str = Field(pattern="^(purchase|adjustment|count|wastage)$")
    qty_milli: int
    reason: str = Field(default="", max_length=160)
    client_txn_id: Optional[str] = Field(default=None, max_length=64)
    batch_no: Optional[str] = Field(default=None, max_length=40)
    expiry_date: Optional[str] = Field(default=None, max_length=10)


class CustomerIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    phone: str = Field(default="", max_length=20)
    gstin: Optional[str] = Field(default=None, max_length=15)
    address: str = Field(default="", max_length=240)
    state_code: Optional[str] = Field(default=None, max_length=2)
    credit_limit_paise: int = Field(default=0, ge=0)


class PriceIn(BaseModel):
    price_paise: Optional[int] = Field(default=None, ge=0)


class WeightIn(BaseModel):
    gross_milli: int = Field(gt=0)
    tare_milli: int = Field(default=0, ge=0)
    live_weight_milli: Optional[int] = Field(default=None, ge=0)
    source: str = Field(default="typed", pattern="^(typed|scale)$")


class LineIn(BaseModel):
    product_id: str = Field(max_length=40)
    qty_milli: int = Field(default=0, ge=0, le=10_000_000_000)
    unit_price_paise: Optional[int] = Field(default=None, ge=0)
    discount_paise: int = Field(default=0, ge=0)
    weight: Optional[WeightIn] = None


class PaymentIn(BaseModel):
    method: str = Field(max_length=20)
    amount_paise: int = Field(gt=0)
    reference: str = Field(default="", max_length=60)


class InvoiceIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    lines: List[LineIn] = Field(min_length=1, max_length=300)
    customer_id: Optional[str] = Field(default=None, max_length=40)
    place_of_supply: Optional[str] = Field(default=None, max_length=2)
    payments: List[PaymentIn] = Field(default_factory=list, max_length=6)
    notes: str = Field(default="", max_length=240)
    offline: bool = False
    issued_at: Optional[str] = Field(default=None, max_length=40)
    device_id: Optional[str] = Field(default=None, max_length=64)
    invoice_number: Optional[str] = Field(default=None, max_length=16)


class CreditLineIn(BaseModel):
    line_no: int = Field(ge=1)
    qty_milli: int = Field(gt=0)
    restock: bool = True


class CreditIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    lines: List[CreditLineIn] = Field(min_length=1, max_length=300)
    reason: str = Field(min_length=1, max_length=160)
    refund: Optional[PaymentIn] = None


class CancelIn(BaseModel):
    reason: str = Field(min_length=1, max_length=160)


class CollectIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    method: str = Field(max_length=20)
    amount_paise: int = Field(gt=0)
    reference: str = Field(default="", max_length=60)


class DayCloseIn(BaseModel):
    local_date: str = Field(max_length=10)
    opening_float_paise: int = Field(default=0, ge=0)
    counted_cash_paise: int = Field(ge=0)
    note: str = Field(default="", max_length=240)


class DraftIn(BaseModel):
    id: Optional[str] = Field(default=None, max_length=40)
    kind: str = Field(pattern="^(hold|quotation)$")
    title: str = Field(default="", max_length=80)
    payload: Dict[str, Any] = Field(default_factory=dict)


class DeviceSeriesIn(BaseModel):
    device_id: str = Field(min_length=6, max_length=64)


def _dump(model: BaseModel) -> Dict[str, Any]:
    return model.model_dump(exclude_none=True)


@router.get("/meta")
def meta() -> dict:
    return {"templates": list(TEMPLATES), "units": list(UNITS), "payment_methods": list(PAY_METHODS),
            "roles": {r: sorted(PERMISSIONS[r]) for r in ROLES}, "gst_rates_bp": sorted(pos_tax.ALLOWED_RATES_BP),
            "tax_categories": list(pos_tax.TAX_CATEGORIES), "states": pos_tax.STATE_CODES,
            "utgst_codes": sorted(pos_tax.UTGST_CODES), "rules": pos_tax.RULES,
            "payment_note": "UPI / card entered at the counter is cashier-confirmed, not bank-verified."}


@router.get("/gstin/{gstin}")
def check_gstin(gstin: str, request: Request) -> dict:
    _user(request)
    return pos_tax.validate_gstin(gstin)


@router.get("/businesses")
def my_businesses(request: Request) -> dict:
    user = _user(request)
    return {"businesses": _store(request).my_businesses(user)}


@router.post("/businesses")
def create_business(body: BusinessIn, request: Request) -> dict:
    user = _user(request, "pos-create", 20)
    return _call(_store(request).create_business, user, _dump(body))


@router.get("/businesses/{business_id}")
def business(business_id: str, request: Request) -> dict:
    return _call(_store(request).business, business_id, _user(request))


@router.patch("/businesses/{business_id}")
def update_business(business_id: str, body: SettingsIn, request: Request) -> dict:
    return _call(_store(request).update_settings, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/members")
def members(business_id: str, request: Request) -> dict:
    return {"members": _call(_store(request).members, business_id, _user(request))}


@router.post("/businesses/{business_id}/members")
def set_member(business_id: str, body: MemberIn, request: Request) -> dict:
    return _call(_store(request).set_member, business_id, _user(request), body.phone, body.role)


@router.post("/businesses/{business_id}/device-series")
def device_series(business_id: str, body: DeviceSeriesIn, request: Request) -> dict:
    return _call(_store(request).register_device_series, business_id, _user(request), body.device_id)


@router.get("/businesses/{business_id}/products")
def products(business_id: str, request: Request, q: str = "", include_inactive: bool = False) -> dict:
    return {"products": _call(_store(request).products, business_id, _user(request), q, include_inactive)}


@router.post("/businesses/{business_id}/products")
def add_product(business_id: str, body: ProductIn, request: Request) -> dict:
    return _call(_store(request).add_product, business_id, _user(request), _dump(body))


@router.patch("/businesses/{business_id}/products/{product_id}")
def update_product(business_id: str, product_id: str, body: ProductIn, request: Request) -> dict:
    return _call(_store(request).update_product, business_id, _user(request), product_id, _dump(body))


@router.get("/businesses/{business_id}/products/{product_id}/history")
def product_history(business_id: str, product_id: str, request: Request) -> dict:
    return {"history": _call(_store(request).product_history, business_id, _user(request), product_id)}


@router.post("/businesses/{business_id}/stock")
def stock(business_id: str, body: StockIn, request: Request) -> dict:
    return _call(_store(request).stock_move, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/stock/{product_id}")
def stock_moves(business_id: str, product_id: str, request: Request) -> dict:
    return {"moves": _call(_store(request).stock_moves, business_id, _user(request), product_id)}


@router.get("/businesses/{business_id}/customers")
def customers(business_id: str, request: Request, q: str = "") -> dict:
    return {"customers": _call(_store(request).customers, business_id, _user(request), q)}


@router.post("/businesses/{business_id}/customers")
def add_customer(business_id: str, body: CustomerIn, request: Request) -> dict:
    return _call(_store(request).add_customer, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/customers/{customer_id}")
def customer(business_id: str, customer_id: str, request: Request) -> dict:
    store, user = _store(request), _user(request)
    out = _call(store.customer, business_id, user, customer_id)
    out["prices"] = _call(store.customer_prices, business_id, user, customer_id)
    return out


@router.put("/businesses/{business_id}/customers/{customer_id}/prices/{product_id}")
def customer_price(business_id: str, customer_id: str, product_id: str, body: PriceIn, request: Request) -> dict:
    return _call(_store(request).set_customer_price, business_id, _user(request), customer_id, product_id,
                 body.price_paise)


@router.post("/businesses/{business_id}/customers/{customer_id}/payments")
def collect(business_id: str, customer_id: str, body: CollectIn, request: Request) -> dict:
    return _call(_store(request).collect, business_id, _user(request), customer_id, _dump(body))


@router.get("/businesses/{business_id}/customers/{customer_id}/statement")
def statement(business_id: str, customer_id: str, month: str, request: Request) -> dict:
    return _call(_store(request).statement, business_id, _user(request), customer_id, month)


@router.post("/businesses/{business_id}/invoices")
def create_invoice(business_id: str, body: InvoiceIn, request: Request) -> dict:
    data = body.model_dump()
    data["lines"] = [{k: v for k, v in line.items() if v is not None} for line in data["lines"]]
    return _call(_store(request).create_invoice, business_id, _user(request), data)


@router.get("/businesses/{business_id}/invoices")
def invoices(business_id: str, request: Request, date_from: str = "", date_to: str = "", customer_id: str = "",
             limit: int = 200) -> dict:
    return {"invoices": _call(_store(request).invoices, business_id, _user(request), date_from=date_from,
                              date_to=date_to, customer_id=customer_id, limit=limit)}


@router.get("/businesses/{business_id}/invoices/{invoice_id}")
def invoice(business_id: str, invoice_id: str, request: Request) -> dict:
    return _call(_store(request).invoice, business_id, _user(request), invoice_id)


@router.post("/businesses/{business_id}/invoices/{invoice_id}/credit-notes")
def credit_note(business_id: str, invoice_id: str, body: CreditIn, request: Request) -> dict:
    return _call(_store(request).create_credit_note, business_id, _user(request), invoice_id, body.model_dump())


@router.post("/businesses/{business_id}/invoices/{invoice_id}/cancel")
def cancel(business_id: str, invoice_id: str, body: CancelIn, request: Request) -> dict:
    return _call(_store(request).cancel_invoice, business_id, _user(request), invoice_id, body.reason)


@router.get("/businesses/{business_id}/day/{local_date}")
def day(business_id: str, local_date: str, request: Request) -> dict:
    return _call(_store(request).day_summary, business_id, _user(request), local_date)


@router.post("/businesses/{business_id}/day-close")
def day_close(business_id: str, body: DayCloseIn, request: Request) -> dict:
    return _call(_store(request).close_day, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/reports/gst")
def gst_report(business_id: str, date_from: str, date_to: str, request: Request) -> dict:
    return _call(_store(request).gst_summary, business_id, _user(request), date_from, date_to)


@router.get("/businesses/{business_id}/reports/register.csv")
def register_csv(business_id: str, date_from: str, date_to: str, request: Request) -> Response:
    text = _call(_store(request).register_csv, business_id, _user(request), date_from, date_to)
    return Response(content=text, media_type="text/csv",
                    headers={"Content-Disposition": f'attachment; filename="register-{date_from}-{date_to}.csv"'})


@router.get("/businesses/{business_id}/drafts")
def drafts(business_id: str, request: Request, kind: str = "") -> dict:
    return {"drafts": _call(_store(request).drafts, business_id, _user(request), kind)}


@router.post("/businesses/{business_id}/drafts")
def save_draft(business_id: str, body: DraftIn, request: Request) -> dict:
    return _call(_store(request).save_draft, business_id, _user(request), _dump(body))


@router.delete("/businesses/{business_id}/drafts/{draft_id}")
def delete_draft(business_id: str, draft_id: str, request: Request) -> dict:
    _call(_store(request).delete_draft, business_id, _user(request), draft_id)
    return {"deleted": True}


@router.get("/businesses/{business_id}/audit")
def audit(business_id: str, request: Request, limit: int = 200) -> dict:
    return {"audit": _call(_store(request).audit, business_id, _user(request), limit)}


# ------------------------------------------------------------------ restaurant
def _restaurant(request: Request):
    from app.services.pos_restaurant import PosRestaurant

    container: Any = request.app.state.container
    store = _store(request)
    existing = getattr(container, "pos_restaurant", None)
    if existing is None or existing.store is not store:
        existing = PosRestaurant(store)
        try:
            container.pos_restaurant = existing
        except Exception:
            pass
    return existing


class TableIn(BaseModel):
    name: str = Field(min_length=1, max_length=30)
    area: str = Field(default="", max_length=30)
    seats: int = Field(default=4, ge=1, le=50)


class OrderIn(BaseModel):
    kind: str = Field(default="dine_in", pattern="^(dine_in|takeaway|delivery)$")
    table_id: Optional[str] = Field(default=None, max_length=40)
    guests: int = Field(default=0, ge=0, le=200)
    notes: str = Field(default="", max_length=160)


class OrderItemIn(BaseModel):
    product_id: str = Field(max_length=40)
    qty_milli: int = Field(default=1000, gt=0, le=1_000_000_000)
    note: str = Field(default="", max_length=120)
    client_txn_id: Optional[str] = Field(default=None, max_length=64)


class OrderItemsIn(BaseModel):
    items: List[OrderItemIn] = Field(min_length=1, max_length=100)


class ReasonIn(BaseModel):
    reason: str = Field(default="", max_length=160)


class MoveIn(BaseModel):
    table_id: str = Field(max_length=40)


class KotStatusIn(BaseModel):
    status: str = Field(pattern="^(preparing|ready|served)$")


class OrderBillIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    item_ids: List[str] = Field(default_factory=list, max_length=300)
    customer_id: Optional[str] = Field(default=None, max_length=40)
    payments: List[PaymentIn] = Field(default_factory=list, max_length=6)
    include_unsent: bool = False


@router.get("/businesses/{business_id}/tables")
def tables(business_id: str, request: Request) -> dict:
    return {"tables": _call(_restaurant(request).tables, business_id, _user(request))}


@router.post("/businesses/{business_id}/tables")
def add_table(business_id: str, body: TableIn, request: Request) -> dict:
    return _call(_restaurant(request).add_table, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/orders")
def open_orders(business_id: str, request: Request) -> dict:
    return {"orders": _call(_restaurant(request).open_orders, business_id, _user(request))}


@router.post("/businesses/{business_id}/orders")
def open_order(business_id: str, body: OrderIn, request: Request) -> dict:
    return _call(_restaurant(request).open_order, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/orders/{order_id}")
def order(business_id: str, order_id: str, request: Request) -> dict:
    return _call(_restaurant(request).order, business_id, _user(request), order_id)


@router.post("/businesses/{business_id}/orders/{order_id}/items")
def add_order_items(business_id: str, order_id: str, body: OrderItemsIn, request: Request) -> dict:
    return _call(_restaurant(request).add_items, business_id, _user(request), order_id,
                 [_dump(i) for i in body.items])


@router.post("/businesses/{business_id}/orders/{order_id}/items/{item_id}/remove")
def remove_order_item(business_id: str, order_id: str, item_id: str, body: ReasonIn, request: Request) -> dict:
    return _call(_restaurant(request).remove_item, business_id, _user(request), order_id, item_id, body.reason)


@router.post("/businesses/{business_id}/orders/{order_id}/kot")
def send_kot(business_id: str, order_id: str, request: Request) -> dict:
    return _call(_restaurant(request).send_kot, business_id, _user(request), order_id)


@router.post("/businesses/{business_id}/orders/{order_id}/move")
def move_order(business_id: str, order_id: str, body: MoveIn, request: Request) -> dict:
    return _call(_restaurant(request).move, business_id, _user(request), order_id, body.table_id)


@router.post("/businesses/{business_id}/orders/{order_id}/bill")
def bill_order(business_id: str, order_id: str, body: OrderBillIn, request: Request) -> dict:
    return _call(_restaurant(request).bill, business_id, _user(request), order_id, body.model_dump())


@router.post("/businesses/{business_id}/orders/{order_id}/void")
def void_order(business_id: str, order_id: str, body: ReasonIn, request: Request) -> dict:
    return _call(_restaurant(request).void_order, business_id, _user(request), order_id, body.reason)


@router.get("/businesses/{business_id}/kitchen")
def kitchen(business_id: str, request: Request) -> dict:
    return {"kots": _call(_restaurant(request).kitchen, business_id, _user(request))}


@router.post("/businesses/{business_id}/kitchen/{kot_id}")
def kot_status(business_id: str, kot_id: str, body: KotStatusIn, request: Request) -> dict:
    return _call(_restaurant(request).set_kot_status, business_id, _user(request), kot_id, body.status)


# ------------------------------------------------------------ stock batches / expiry
@router.get("/businesses/{business_id}/stock/{product_id}/batches")
def batches(business_id: str, product_id: str, request: Request) -> dict:
    return {"batches": _call(_store(request).batches, business_id, _user(request), product_id)}


@router.get("/businesses/{business_id}/reports/expiry")
def expiry_report(business_id: str, request: Request, days: int = 30) -> dict:
    return _call(_store(request).expiry_report, business_id, _user(request), days)


# ------------------------------------------------------------ suppliers / purchases
def _purchases(request: Request):
    from app.services.pos_purchases import PosPurchases

    container: Any = request.app.state.container
    store = _store(request)
    existing = getattr(container, "pos_purchases", None)
    if existing is None or existing.store is not store:
        existing = PosPurchases(store)
        try:
            container.pos_purchases = existing
        except Exception:
            pass
    return existing


class SupplierIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    phone: str = Field(default="", max_length=20)
    gstin: Optional[str] = Field(default=None, max_length=15)
    address: str = Field(default="", max_length=240)
    state_code: Optional[str] = Field(default=None, max_length=2)


class PurchaseLineIn(BaseModel):
    product_id: str = Field(max_length=40)
    qty_milli: int = Field(gt=0, le=10_000_000_000)
    cost_paise: int = Field(ge=0)
    rate_bp: Optional[int] = Field(default=None, ge=0)
    cess_bp: int = Field(default=0, ge=0, le=30000)
    discount_paise: int = Field(default=0, ge=0)
    batch_no: Optional[str] = Field(default=None, max_length=40)
    expiry_date: Optional[str] = Field(default=None, max_length=10)


class PurchaseIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    supplier_id: str = Field(max_length=40)
    supplier_bill_no: str = Field(min_length=1, max_length=40)
    bill_date: Optional[str] = Field(default=None, max_length=10)
    lines: List[PurchaseLineIn] = Field(min_length=1, max_length=300)
    supplier_total_paise: Optional[int] = Field(default=None, ge=0)
    notes: str = Field(default="", max_length=240)


class SupplierPayIn(BaseModel):
    client_txn_id: str = Field(min_length=8, max_length=64)
    method: str = Field(max_length=20)
    amount_paise: int = Field(gt=0)
    reference: str = Field(default="", max_length=60)


@router.get("/businesses/{business_id}/suppliers")
def suppliers(business_id: str, request: Request) -> dict:
    return {"suppliers": _call(_purchases(request).suppliers, business_id, _user(request))}


@router.post("/businesses/{business_id}/suppliers")
def add_supplier(business_id: str, body: SupplierIn, request: Request) -> dict:
    return _call(_purchases(request).add_supplier, business_id, _user(request), _dump(body))


@router.get("/businesses/{business_id}/suppliers/{supplier_id}")
def supplier(business_id: str, supplier_id: str, request: Request) -> dict:
    return _call(_purchases(request).supplier, business_id, _user(request), supplier_id)


@router.post("/businesses/{business_id}/suppliers/{supplier_id}/payments")
def pay_supplier(business_id: str, supplier_id: str, body: SupplierPayIn, request: Request) -> dict:
    return _call(_purchases(request).pay_supplier, business_id, _user(request), supplier_id, _dump(body))


@router.get("/businesses/{business_id}/suppliers/{supplier_id}/statement")
def supplier_statement(business_id: str, supplier_id: str, month: str, request: Request) -> dict:
    return _call(_purchases(request).supplier_statement, business_id, _user(request), supplier_id, month)


@router.get("/businesses/{business_id}/purchases")
def purchases(business_id: str, request: Request, supplier_id: str = "") -> dict:
    return {"purchases": _call(_purchases(request).purchases, business_id, _user(request), supplier_id)}


@router.post("/businesses/{business_id}/purchases")
def record_purchase(business_id: str, body: PurchaseIn, request: Request) -> dict:
    data = body.model_dump()
    data["lines"] = [{k: v for k, v in line.items() if v is not None} for line in data["lines"]]
    return _call(_purchases(request).record_purchase, business_id, _user(request), data)


@router.get("/businesses/{business_id}/purchases/{purchase_id}")
def purchase(business_id: str, purchase_id: str, request: Request) -> dict:
    return _call(_purchases(request).purchase, business_id, _user(request), purchase_id)


@router.post("/businesses/{business_id}/purchases/{purchase_id}/cancel")
def cancel_purchase(business_id: str, purchase_id: str, body: CancelIn, request: Request) -> dict:
    return _call(_purchases(request).cancel_purchase, business_id, _user(request), purchase_id, body.reason)


@router.get("/businesses/{business_id}/reports/valuation")
def valuation(business_id: str, request: Request) -> dict:
    return _call(_purchases(request).valuation, business_id, _user(request))


@router.get("/businesses/{business_id}/reports/input-tax")
def input_tax(business_id: str, date_from: str, date_to: str, request: Request) -> dict:
    return _call(_purchases(request).input_tax, business_id, _user(request), date_from, date_to)
