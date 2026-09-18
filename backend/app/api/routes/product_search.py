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
    match_score: float = 0
    match_reasons: list[str] = []


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
    elif str(row.get("precise_location") or "").strip():
        # Fall back to the precise GPS/landmark note only when no simple
        # area/city label was given at all.
        parts.append(str(row["precise_location"]).strip())
    # 2026-09-15 (round 2): a plain "ID Verified" trust badge -- never the
    # underlying ID number itself (see product_catalog_repository.py).
    if str(row.get("id_verification_status") or "").strip().upper() == "VERIFIED":
        parts.append("✓ ID Verified")
    category_tag = str(row.get("category_tag") or "").strip()
    if category_tag:
        parts.append(category_tag)
    service_area = str(row.get("service_area") or "").strip()
    if service_area:
        parts.append(f"Serves: {service_area}")
    working_hours = str(row.get("working_hours") or "").strip()
    if working_hours:
        parts.append(working_hours)
    seller_name = str(row.get("seller_name") or "").strip()
    if seller_name:
        parts.append(seller_name)
    return " • ".join(parts)


def _title(row: dict[str, Any]) -> str:
    subject = str(row.get("subject") or "").strip()
    variant = str(row.get("variant") or "").strip()
    return f"{subject} — {variant}" if variant else subject


@router.get("/search", response_model=ProductSearchResponse)
def search_products(request: Request, q: str = "", limit: int = 10, location: str = "", budget: float | None = None) -> ProductSearchResponse:
    container: Any = request.app.state.container
    repository = container.product_catalog_repository
    rows = repository.search_active(q, limit=max(limit * 3, limit))
    rows = container.product_match_ranking_service.rank(q, rows, location=location, budget=budget)[:max(1, min(limit, 50))]
    return ProductSearchResponse(
        items=[
            ProductMatch(
                id=str(row["id"]),
                title=_title(row),
                subtitle=_subtitle(row),
                price=(float(row["price"]) if row.get("price") is not None else None),
                provider_id=str(row.get("seller_user_id") or ""),
                match_score=float(row.get("match_score") or 0),
                match_reasons=list(row.get("match_reasons") or []),
            )
            for row in rows
        ]
    )