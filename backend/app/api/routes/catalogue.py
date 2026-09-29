"""Ready-made seller catalogues: pick items from a template, set YOUR price,
size, stock and (optionally) a photo, review, publish.

GET  /api/catalog/templates                 -> available templates
GET  /api/catalog/templates/{key}           -> categories + items (en/te/hi)
POST /api/catalog/templates/{key}/publish   -> the seller's reviewed items
GET  /api/catalog/photos/{product_id}       -> a published item's photo

Published items are ordinary listings (same table, same search, same order
flow as "list my product"); items without a price are kept as drafts so the
seller can finish them later -- nothing is published with an invented price.
"""
from __future__ import annotations

import base64
import binascii
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app.api.routes.in_app_deal import _authenticated_app_user
from app.services import catalogue_templates

router = APIRouter(prefix="/api/catalog", tags=["catalogue"])

PHOTO_LIMIT = 600 * 1024
STOCK = {"IN_STOCK", "LOW_STOCK", "OUT_OF_STOCK", "UNKNOWN"}


def _photos_db(container: Any) -> str:
    path = container.settings.database_path
    with closing(sqlite3.connect(path)) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS catalog_item_photos (product_id INTEGER PRIMARY KEY, "
                     "seller_user_id TEXT NOT NULL, jpeg BLOB NOT NULL, updated_at TEXT NOT NULL)")
        conn.commit()
    return path


@router.get("/templates")
def list_templates() -> dict:
    return {"items": catalogue_templates.summaries()}


@router.get("/templates/{key}")
def get_template(key: str) -> dict:
    found = catalogue_templates.template(key)
    if not found:
        raise HTTPException(status_code=404, detail="No ready-made catalogue for this category yet")
    return found


class CatalogueItem(BaseModel):
    item_key: str = Field(min_length=1, max_length=80)
    size: str | None = Field(default=None, max_length=40)
    price: float | None = Field(default=None, gt=0, le=10_000_000)
    stock_status: str = "IN_STOCK"
    description: str | None = Field(default=None, max_length=400)
    photo_base64: str | None = None


class PublishCatalogue(BaseModel):
    items: list[CatalogueItem] = Field(min_length=1, max_length=200)
    business_name: str | None = Field(default=None, max_length=120)
    business_address: str | None = Field(default=None, max_length=240)
    language: str = Field(default="en", max_length=8)


def _photo_bytes(value: str | None) -> bytes | None:
    if not value:
        return None
    try:
        data = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail="invalid photo data") from error
    if len(data) > PHOTO_LIMIT:
        raise HTTPException(status_code=413, detail="photo too large (max 600 KB)")
    if not (data[:3] == b"\xff\xd8\xff" or data[:8] == b"\x89PNG\r\n\x1a\n"):
        raise HTTPException(status_code=415, detail="photo must be JPEG or PNG")
    return data


@router.post("/templates/{key}/publish")
def publish_catalogue(key: str, payload: PublishCatalogue, request: Request) -> dict:
    from app.api.routes.growth import growth
    from app.api.routes.profile import profiles

    seller = _authenticated_app_user(request)
    template = catalogue_templates.template(key)
    if not template:
        raise HTTPException(status_code=404, detail="No ready-made catalogue for this category yet")
    container = request.app.state.container
    profile_repo = profiles(container)
    updates = {k: v.strip() for k, v in (("business_name", payload.business_name),
                                          ("business_address", payload.business_address)) if v and v.strip()}
    if updates:
        profile_repo.update(seller, {**updates, "business_category": template["key"]})
    profile = profile_repo.get(seller)
    shop = profile.get("business_name") or profile.get("name")
    place = profile.get("business_address") or profile.get("address")
    if not shop or not place:
        raise HTTPException(status_code=422, detail="Add your shop name and address before publishing")

    published, drafts, skipped = [], [], []
    catalog = container.product_catalog_repository
    for entry in payload.items:
        item = catalogue_templates.item(template["key"], entry.item_key)
        if not item:
            skipped.append({"item_key": entry.item_key, "reason": "not in this catalogue"})
            continue
        size = (entry.size or (item["sizes"][0] if item["sizes"] else "")).strip()
        subject = f"{item['name']['en']} {size}".strip()
        description = (entry.description or "").strip() or f"{item['name']['en']} ({size})"
        features = [description, item["name"]["te"], item["name"]["hi"], item["category_name"]["en"]]
        stock = entry.stock_status.upper() if entry.stock_status.upper() in STOCK else "UNKNOWN"
        photo = _photo_bytes(entry.photo_base64)
        if entry.price is None:
            draft = growth(container).save_draft(
                seller, {"subject": subject, "title": subject, "unit": item["unit"], "category_tag": template["category_tag"],
                         "attributes": {"size": size}, "description": description},
                ["price"], "catalogue_template")
            drafts.append({"item_key": entry.item_key, "draft_id": draft.get("id")})
            continue
        product_id = catalog.upsert_product(
            seller_user_id=seller, subject=subject, variant=size or None, price=entry.price, unit=item["unit"],
            stock_status=stock, seller_name=shop, location_label=place, category_tag=template["category_tag"],
            features=features,
        )
        if photo is not None:
            with closing(sqlite3.connect(_photos_db(container))) as conn:
                conn.execute("INSERT OR REPLACE INTO catalog_item_photos(product_id, seller_user_id, jpeg, updated_at) "
                             "VALUES(?,?,?,?)", (product_id, seller, photo, datetime.now(timezone.utc).isoformat()))
                conn.execute("UPDATE seller_products SET image_media_id=? WHERE id=?",
                             (f"catalog-photo:{product_id}", product_id))
                conn.commit()
        published.append({"item_key": entry.item_key, "product_id": product_id, "subject": subject})
    tier = None
    if published:
        container.seller_profile_repository.backfill_from_catalog()
        row = container.seller_profile_repository.get(seller)
        tier = row["tier"] if row else None
    return {"template": template["key"], "published": published, "drafts": drafts, "skipped": skipped,
            "seller_tier": tier}


@router.get("/photos/{product_id}")
def catalogue_photo(product_id: int, request: Request) -> Response:
    """A published item's photo (public, like the listing itself)."""
    with closing(sqlite3.connect(_photos_db(request.app.state.container))) as conn:
        row = conn.execute(
            "SELECT p.jpeg FROM catalog_item_photos p JOIN seller_products s ON s.id=p.product_id "
            "WHERE p.product_id=? AND s.active=1", (product_id,)).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="no photo")
    data = bytes(row[0])
    return Response(content=data, media_type="image/png" if data[:4] == b"\x89PNG" else "image/jpeg",
                    headers={"Cache-Control": "public, max-age=3600"})
