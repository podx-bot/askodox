"""Real seller-catalog search for buyer-facing AI matching.

This is a deliberately simple bootstrap: it searches the same
`seller_products` table that WhatsApp price-list confirmation already
writes to, plus rows added through the manual `/admin/products/new` form.
It exists so the in-app AI chat can show real, seller-supplied listings
instead of the hardcoded `DemoNaturalMatchCatalog` sandbox data. Real
ranking/location/availability logic (Master Architecture Point 7) is a
separate, larger follow-up once there is meaningful real-data volume.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel

router = APIRouter(prefix="/api/products", tags=["product-search"])


class ProductMatch(BaseModel):
    id: str
    title: str
    subtitle: str = ""
    price: float | None = None
    provider_id: str = ""


class ProductSearchResponse(BaseModel):
    items: list[ProductMatch]


def _subtitle(row: dict[str, Any]) -> str:
    parts: list[str] = []
    price = row.get("price")
    unit = str(row.get("unit") or "").strip()
    if price is not None:
        price_text = f"₹{price:g}"
        parts.append(f"{price_text}/{unit}" if unit else price_text)
    stock = str(row.get("stock_status") or "").strip().upper()
    if stock and stock != "UNKNOWN":
        parts.append(stock.replace("_", " ").title())
    location = str(row.get("location_label") or "").strip()
    if location:
        parts.append(location)
    seller_name = str(row.get("seller_name") or "").strip()
    if seller_name:
        parts.append(seller_name)
    return " • ".join(parts)


def _title(row: dict[str, Any]) -> str:
    subject = str(row.get("subject") or "").strip()
    variant = str(row.get("variant") or "").strip()
    return f"{subject} — {variant}" if variant else subject


@router.get("/search", response_model=ProductSearchResponse)
def search_products(request: Request, q: str = "", limit: int = 10) -> ProductSearchResponse:
    container: Any = request.app.state.container
    repository = container.product_catalog_repository
    rows = repository.search_active(q, limit=limit)
    return ProductSearchResponse(
        items=[
            ProductMatch(
                id=str(row["id"]),
                title=_title(row),
                subtitle=_subtitle(row),
                price=(float(row["price"]) if row.get("price") is not None else None),
                provider_id=str(row.get("seller_user_id") or ""),
            )
            for row in rows
        ]
    )