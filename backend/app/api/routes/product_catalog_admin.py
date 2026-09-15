"""Manual bootstrap tool for adding real seller_products rows.

Temporary, low-tech way to seed real listings while proper seller
onboarding (Master Architecture Point 15/16) and BFSI-specific schemas
(Point 11) are not yet built, so the AI chat has something real to show
instead of the DemoNaturalMatchCatalog sandbox data. Protected only by a
shared-secret query-param key (the ADMIN_SEED_KEY env var) rather than
real authentication -- this is a short-lived helper, not a permanent
admin surface. Deliberately uses a GET-based form (not POST + Form(...))
so it needs no python-multipart dependency.
"""
from __future__ import annotations

import html
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse

router = APIRouter(prefix="/admin/products", tags=["admin-products"])


def _check_key(container: Any, key: str) -> None:
    expected = str(getattr(container.settings, "admin_seed_key", "") or "").strip()
    if not expected or key != expected:
        # 404 rather than 403 so this path doesn't advertise its own existence.
        raise HTTPException(status_code=404)


_FORM_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Add a real product/service</title>
<style>
body{{font-family:sans-serif;max-width:480px;margin:24px auto;padding:0 16px;color:#111}}
label{{display:block;margin-top:12px;font-weight:600}}
input,select{{width:100%;padding:8px;margin-top:4px;box-sizing:border-box;font-size:16px}}
button{{margin-top:20px;padding:12px;width:100%;font-size:16px;background:#5B4BFF;color:#fff;border:none;border-radius:8px}}
.note{{color:#555;font-size:13px;margin-top:24px}}
.success{{background:#e8f9ee;border:1px solid #34a853;padding:12px;border-radius:8px;margin-bottom:16px}}
</style></head>
<body>
<h2>Add a real product / service</h2>
{success_banner}
<form method="get" action="/admin/products/new">
<input type="hidden" name="key" value="{key}">
<label>Seller / business name<input name="seller_name" value="{seller_name}"></label>
<label>Seller ID (phone or any short code -- groups this seller's items)<input name="seller_user_id" value="{seller_user_id}" required></label>
<label>What are they selling? (subject)<input name="subject" required></label>
<label>Variant / detail (optional)<input name="variant"></label>
<label>Price (INR)<input name="price" type="number" step="0.01"></label>
<label>Unit (kg, piece, plan, etc.)<input name="unit"></label>
<label>Stock / availability
<select name="stock_status">
<option value="IN_STOCK">In stock / available</option>
<option value="OUT_OF_STOCK">Out of stock</option>
<option value="UNKNOWN" selected>Unknown</option>
</select></label>
<label>Location (area/city)<input name="location_label"></label>
<label>Contact phone (not shown to buyers yet)<input name="contact_phone"></label>
<button type="submit">Save</button>
</form>
<p class="note">This saves directly into the real seller_products table used by ASKODOX's AI search. Bookmark this exact link (with your key) to add more items any time.</p>
</body></html>"""


@router.get("/new", response_class=HTMLResponse)
def add_product_form(
    request: Request,
    key: str = "",
    subject: str = "",
    seller_user_id: str = "",
    seller_name: str = "",
    variant: str = "",
    price: str = "",
    unit: str = "",
    stock_status: str = "UNKNOWN",
    location_label: str = "",
    contact_phone: str = "",
) -> HTMLResponse:
    container: Any = request.app.state.container
    _check_key(container, key)

    success_banner = ""
    if subject.strip() and seller_user_id.strip():
        clean_price: float | None
        try:
            clean_price = float(price) if price.strip() else None
        except ValueError:
            clean_price = None
        product_id = container.product_catalog_repository.upsert_product(
            seller_user_id=seller_user_id.strip(),
            subject=subject.strip(),
            variant=variant.strip() or None,
            price=clean_price,
            unit=unit.strip() or None,
            stock_status=stock_status,
            seller_name=seller_name.strip() or None,
            location_label=location_label.strip() or None,
            contact_phone=contact_phone.strip() or None,
        )
        success_banner = (
            f'<div class="success">Saved &quot;{html.escape(subject.strip())}&quot; '
            f"(id {product_id}). Add another below.</div>"
        )

    page = _FORM_PAGE.format(
        success_banner=success_banner,
        key=html.escape(key),
        seller_name=html.escape(seller_name),
        seller_user_id=html.escape(seller_user_id),
    )
    return HTMLResponse(page)