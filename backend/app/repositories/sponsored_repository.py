"""Sponsored listings / advertisers / campaigns (Command Center).

Paid placements are kept strictly apart from organic results:

- sponsored_advertisers   who pays (brand, seller, provider, influencer,
                          affiliate, agency) -- admin-entered, never invented
- sponsored_campaigns     what is shown: a listing, deal, seller / provider
                          promotion, influencer video or affiliate link, with
                          budget, dates, target categories / keywords /
                          locations and a disclosure label (Sponsored /
                          Promoted). Only APPROVED campaigns inside their
                          window and under budget are ever served, and only
                          when their targeting matches the request (a
                          campaign with no category and no keyword is never
                          served -- no random ads).
- sponsored_events        impression / click / conversion (conversions are
                          recorded by an admin from a real report)
- sponsored_search_daily  per-day organic vs sponsored tallies from the
                          discovery pipeline (analytics only)

Editing what a live campaign shows sends it back to DRAFT (re-approval).
"""
from __future__ import annotations

import json
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

ADVERTISER_KINDS = ("brand", "seller", "provider", "influencer", "affiliate", "agency", "other")
CAMPAIGN_KINDS = (
    "sponsored_listing", "deal", "seller_promotion", "provider_promotion", "influencer_video", "affiliate_link",
)
STATUSES = ("DRAFT", "APPROVED", "PAUSED", "DISABLED")
LABELS = ("Sponsored", "Promoted")
PLACEMENTS = ("chat_results", "explore_top")
EVENTS = ("impression", "click", "conversion", "lead", "order")
OBJECTIVES = ("awareness", "traffic", "leads", "orders", "app_installs", "store_visits")
FORMATS = ("result_card", "video", "banner", "deal_card")
AUDIENCES = ("all", "new_users", "returning_users", "buyers", "sellers")

# Changing any of these on an APPROVED campaign needs a new approval.
_CONTENT_FIELDS = {
    "title", "subtitle", "image_url", "destination_url", "kind", "label", "categories", "keywords", "locations",
    "advertiser_id",
}
_LIST_FIELDS = ("categories", "keywords", "locations")
CAMPAIGN_FIELDS = (
    "advertiser_id", "name", "kind", "label", "placement", "title", "subtitle", "image_url", "destination_url",
    "categories", "keywords", "locations", "starts_at", "ends_at", "budget", "cost_per_click",
    "cost_per_thousand", "priority", "notes",
    # Extended targeting / delivery (2026-09-29).
    "objective", "format", "audience", "language", "radius_km", "daily_budget", "max_impressions", "max_clicks",
    "deep_link", "tracking_url",
)
# Columns added after the first release (added in place, never a rebuild).
_EXTRA_COLUMNS = {
    "objective": "TEXT", "format": "TEXT", "audience": "TEXT", "language": "TEXT", "radius_km": "REAL",
    "daily_budget": "REAL", "max_impressions": "INTEGER", "max_clicks": "INTEGER", "deep_link": "TEXT",
    "tracking_url": "TEXT", "archived": "INTEGER NOT NULL DEFAULT 0",
}
_BLOCKED_SCHEMES = ("javascript:", "data:", "file:", "vbscript:", "about:", "content:")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(value: datetime | None = None) -> str:
    return (value or _now()).isoformat()


def _loads(raw: Any, default: Any) -> Any:
    try:
        return json.loads(raw) if raw else default
    except (TypeError, ValueError):
        return default


def _norm_list(value: Any) -> List[str]:
    if isinstance(value, str):
        value = value.split(",")
    out: List[str] = []
    for item in value or []:
        text = str(item or "").strip().lower()
        if text and text not in out:
            out.append(text[:80])
    return out[:40]


def _parse_day(value: Any) -> Optional[datetime]:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


class SponsoredError(ValueError):
    pass


class SponsoredRepository:
    def __init__(self, db_path: str = "podx.db") -> None:
        self.db_path = db_path
        self._ensure_schema()

    def _connect(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        from app.services.social_ads_offers_hub import migrate_social_campaign_table

        with self._connect() as conn:
            migrate_social_campaign_table(conn)
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS sponsored_advertisers (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'brand', contact TEXT, notes TEXT,
                    active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sponsored_campaigns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    advertiser_id INTEGER, name TEXT NOT NULL, kind TEXT NOT NULL,
                    label TEXT NOT NULL DEFAULT 'Sponsored', placement TEXT NOT NULL DEFAULT 'chat_results',
                    title TEXT NOT NULL, subtitle TEXT, image_url TEXT, destination_url TEXT,
                    categories_json TEXT NOT NULL DEFAULT '[]', keywords_json TEXT NOT NULL DEFAULT '[]',
                    locations_json TEXT NOT NULL DEFAULT '[]',
                    starts_at TEXT, ends_at TEXT, budget REAL, cost_per_click REAL, cost_per_thousand REAL,
                    priority INTEGER NOT NULL DEFAULT 0, notes TEXT,
                    status TEXT NOT NULL DEFAULT 'DRAFT', approved_by TEXT, approved_at TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sponsored_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id INTEGER NOT NULL, event TEXT NOT NULL, click_id TEXT,
                    category TEXT, location TEXT, amount REAL, note TEXT, created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_sponsored_events_campaign
                    ON sponsored_events(campaign_id, event);
                CREATE INDEX IF NOT EXISTS idx_sponsored_events_click ON sponsored_events(click_id);
                CREATE TABLE IF NOT EXISTS sponsored_search_daily (
                    day TEXT PRIMARY KEY, searches INTEGER NOT NULL DEFAULT 0,
                    organic_results INTEGER NOT NULL DEFAULT 0, sponsored_results INTEGER NOT NULL DEFAULT 0
                );
                """
            )
            have = {r["name"] for r in conn.execute("PRAGMA table_info(sponsored_campaigns)").fetchall()}
            for column, kind in _EXTRA_COLUMNS.items():
                if column not in have:
                    conn.execute(f"ALTER TABLE sponsored_campaigns ADD COLUMN {column} {kind}")

    # ----------------------------------------------------------- advertisers --

    def advertisers(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM sponsored_advertisers ORDER BY id DESC").fetchall()
        return [dict(row) | {"active": bool(row["active"])} for row in rows]

    def save_advertiser(self, data: Dict[str, Any], advertiser_id: int | None = None) -> Dict[str, Any]:
        fields: Dict[str, Any] = {}
        if "name" in data:
            name = str(data.get("name") or "").strip()
            if not name:
                raise SponsoredError("name is required")
            fields["name"] = name[:120]
        if "kind" in data:
            kind = str(data.get("kind") or "").strip().lower()
            if kind not in ADVERTISER_KINDS:
                raise SponsoredError(f"kind must be one of {', '.join(ADVERTISER_KINDS)}")
            fields["kind"] = kind
        for key in ("contact", "notes"):
            if key in data:
                fields[key] = str(data.get(key) or "").strip()[:500]
        if "active" in data:
            fields["active"] = 1 if data.get("active") else 0
        now = _iso()
        with self._connect() as conn:
            if advertiser_id is None:
                if "name" not in fields:
                    raise SponsoredError("name is required")
                fields.setdefault("kind", "brand")
                cols = list(fields) + ["created_at", "updated_at"]
                cur = conn.execute(
                    f"INSERT INTO sponsored_advertisers ({', '.join(cols)}) VALUES ({', '.join('?' for _ in cols)})",
                    [*fields.values(), now, now],
                )
                advertiser_id = int(cur.lastrowid)
            else:
                if not conn.execute("SELECT 1 FROM sponsored_advertisers WHERE id=?", (advertiser_id,)).fetchone():
                    raise KeyError(advertiser_id)
                if fields:
                    sets = ", ".join(f"{k}=?" for k in fields)
                    conn.execute(f"UPDATE sponsored_advertisers SET {sets}, updated_at=? WHERE id=?",
                                 [*fields.values(), now, advertiser_id])
            row = conn.execute("SELECT * FROM sponsored_advertisers WHERE id=?", (advertiser_id,)).fetchone()
        return dict(row) | {"active": bool(row["active"])}

    # ------------------------------------------------------------- campaigns --

    @staticmethod
    def _campaign(row: sqlite3.Row) -> Dict[str, Any]:
        item = dict(row)
        for key in _LIST_FIELDS:
            item[key] = _loads(item.pop(f"{key}_json", "[]"), [])
        return item

    def campaign(self, campaign_id: int) -> Optional[Dict[str, Any]]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM sponsored_campaigns WHERE id=?", (campaign_id,)).fetchone()
        return self._campaign(row) if row else None

    def campaigns(self) -> List[Dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM sponsored_campaigns ORDER BY id DESC").fetchall()
        stats = self.campaign_stats()
        return [self._campaign(row) | {"stats": stats.get(int(row["id"]), self._empty_stats())} for row in rows]

    def _validate(self, data: Dict[str, Any]) -> Dict[str, Any]:
        fields: Dict[str, Any] = {}
        for key in CAMPAIGN_FIELDS:
            if key not in data:
                continue
            value = data.get(key)
            if key in _LIST_FIELDS:
                fields[key] = _norm_list(value)
            elif key == "kind":
                kind = str(value or "").strip().lower()
                if kind not in CAMPAIGN_KINDS:
                    raise SponsoredError(f"kind must be one of {', '.join(CAMPAIGN_KINDS)}")
                fields[key] = kind
            elif key == "label":
                label = str(value or "").strip().capitalize()
                if label not in LABELS:
                    raise SponsoredError("label must be Sponsored or Promoted")
                fields[key] = label
            elif key == "placement":
                placement = str(value or "").strip().lower()
                if placement not in PLACEMENTS:
                    raise SponsoredError(f"placement must be one of {', '.join(PLACEMENTS)}")
                fields[key] = placement
            elif key in ("objective", "format", "audience"):
                choice = str(value or "").strip().lower()
                options = {"objective": OBJECTIVES, "format": FORMATS, "audience": AUDIENCES}[key]
                if choice and choice not in options:
                    raise SponsoredError(f"{key} must be one of {', '.join(options)}")
                fields[key] = choice or None
            elif key == "deep_link":
                link = str(value or "").strip()
                if link and (link.lower().startswith(_BLOCKED_SCHEMES) or "://" not in link):
                    raise SponsoredError("deep_link must be an app link (scheme://...) or https URL")
                fields[key] = link[:1000] or None
            elif key in ("radius_km", "daily_budget"):
                if value in (None, ""):
                    fields[key] = None
                else:
                    try:
                        number = float(value)
                    except (TypeError, ValueError):
                        raise SponsoredError(f"{key} must be a number") from None
                    if number < 0:
                        raise SponsoredError(f"{key} cannot be negative")
                    fields[key] = number
            elif key in ("max_impressions", "max_clicks"):
                if value in (None, ""):
                    fields[key] = None
                else:
                    try:
                        whole = int(value)
                    except (TypeError, ValueError):
                        raise SponsoredError(f"{key} must be a whole number") from None
                    if whole < 1:
                        raise SponsoredError(f"{key} must be at least 1")
                    fields[key] = whole
            elif key == "language":
                fields[key] = str(value or "").strip().lower()[:8] or None
            elif key in ("destination_url", "image_url", "tracking_url"):
                url = str(value or "").strip()
                if url and not url.startswith("https://"):
                    raise SponsoredError(f"{key} must be an https:// URL")
                fields[key] = url[:1000]
            elif key in ("starts_at", "ends_at"):
                text = str(value or "").strip()
                if text and _parse_day(text) is None:
                    raise SponsoredError(f"{key} must be a date (YYYY-MM-DD)")
                fields[key] = text or None
            elif key in ("budget", "cost_per_click", "cost_per_thousand"):
                if value in (None, ""):
                    fields[key] = None
                else:
                    try:
                        number = float(value)
                    except (TypeError, ValueError):
                        raise SponsoredError(f"{key} must be a number") from None
                    if number < 0:
                        raise SponsoredError(f"{key} cannot be negative")
                    fields[key] = number
            elif key in ("priority", "advertiser_id"):
                if value in (None, ""):
                    fields[key] = None if key == "advertiser_id" else 0
                else:
                    try:
                        fields[key] = int(value)
                    except (TypeError, ValueError):
                        raise SponsoredError(f"{key} must be a whole number") from None
            else:
                fields[key] = str(value or "").strip()[:500]
        if "name" in fields and not fields["name"]:
            raise SponsoredError("name is required")
        if "title" in fields and not fields["title"]:
            raise SponsoredError("title is required")
        if fields.get("starts_at") and fields.get("ends_at") and str(fields["ends_at"]) < str(fields["starts_at"]):
            raise SponsoredError("ends_at is before starts_at")
        return fields

    def save_campaign(self, data: Dict[str, Any], campaign_id: int | None = None) -> Dict[str, Any]:
        fields = self._validate(data)
        now = _iso()
        with self._connect() as conn:
            if fields.get("advertiser_id") is not None and not conn.execute(
                "SELECT 1 FROM sponsored_advertisers WHERE id=?", (fields["advertiser_id"],)
            ).fetchone():
                raise SponsoredError("unknown advertiser")
            if campaign_id is None:
                for required in ("name", "title", "kind"):
                    if not fields.get(required):
                        raise SponsoredError(f"{required} is required")
                cols = [k for k in fields if k not in _LIST_FIELDS] + [f"{k}_json" for k in _LIST_FIELDS if k in fields]
                values = [fields[k] for k in fields if k not in _LIST_FIELDS] + [
                    json.dumps(fields[k]) for k in _LIST_FIELDS if k in fields]
                cols += ["status", "created_at", "updated_at"]
                values += ["DRAFT", now, now]
                cur = conn.execute(
                    f"INSERT INTO sponsored_campaigns ({', '.join(cols)}) VALUES ({', '.join('?' for _ in cols)})",
                    values,
                )
                campaign_id = int(cur.lastrowid)
            else:
                row = conn.execute("SELECT status FROM sponsored_campaigns WHERE id=?", (campaign_id,)).fetchone()
                if not row:
                    raise KeyError(campaign_id)
                if fields:
                    sets, values = [], []
                    for key, value in fields.items():
                        column = f"{key}_json" if key in _LIST_FIELDS else key
                        sets.append(f"{column}=?")
                        values.append(json.dumps(value) if key in _LIST_FIELDS else value)
                    if row["status"] == "APPROVED" and _CONTENT_FIELDS & set(fields):
                        sets += ["status=?", "approved_by=?", "approved_at=?"]
                        values += ["DRAFT", None, None]
                    conn.execute(f"UPDATE sponsored_campaigns SET {', '.join(sets)}, updated_at=? WHERE id=?",
                                 [*values, now, campaign_id])
            row = conn.execute("SELECT * FROM sponsored_campaigns WHERE id=?", (campaign_id,)).fetchone()
        return self._campaign(row)

    def duplicate(self, campaign_id: int) -> Dict[str, Any]:
        """A DRAFT copy (needs its own approval); stats are not copied."""
        campaign = self.campaign(campaign_id)
        if campaign is None:
            raise KeyError(campaign_id)
        data = {k: campaign.get(k) for k in CAMPAIGN_FIELDS if campaign.get(k) is not None}
        data["name"] = f"{campaign['name']} (copy)"[:200]
        return self.save_campaign(data)

    def set_archived(self, campaign_id: int, archived: bool) -> Dict[str, Any]:
        """Archive keeps history and stats; an archived campaign is never
        served and is paused. Restore brings it back as DRAFT."""
        if self.campaign(campaign_id) is None:
            raise KeyError(campaign_id)
        with self._connect() as conn:
            conn.execute("UPDATE sponsored_campaigns SET archived=?, status=?, updated_at=? WHERE id=?",
                         (int(archived), "PAUSED" if archived else "DRAFT", _iso(), campaign_id))
        return self.campaign(campaign_id) or {}

    def record_outcome(self, campaign_id: int, event: str, *, amount: float | None = None,
                       note: str = "") -> Dict[str, Any]:
        """Leads / orders attributed to a campaign (admin-recorded or from a
        verified source) -- counted in its report."""
        if event not in ("lead", "order"):
            raise SponsoredError("event must be lead or order")
        if self.campaign(campaign_id) is None:
            raise KeyError(campaign_id)
        if amount is not None and amount < 0:
            raise SponsoredError("amount cannot be negative")
        with self._connect() as conn:
            conn.execute("INSERT INTO sponsored_events (campaign_id, event, amount, note, created_at) "
                         "VALUES (?, ?, ?, ?, ?)", (campaign_id, event, amount, str(note or "")[:300], _iso()))
        return self.campaign_stats().get(campaign_id, self._empty_stats())

    def set_status(self, campaign_id: int, status: str, *, actor: str = "") -> Dict[str, Any]:
        status = str(status or "").strip().upper()
        if status not in STATUSES:
            raise SponsoredError(f"status must be one of {', '.join(STATUSES)}")
        campaign = self.campaign(campaign_id)
        if campaign is None:
            raise KeyError(campaign_id)
        if campaign.get("archived") and status != "DISABLED":
            raise SponsoredError("restore the campaign first")
        if status == "APPROVED":
            if not str(campaign.get("destination_url") or "").startswith("https://"):
                raise SponsoredError("an https destination URL is required before approval")
            if not campaign.get("categories") and not campaign.get("keywords"):
                raise SponsoredError("target at least one category or keyword before approval (no untargeted ads)")
        with self._connect() as conn:
            if status == "APPROVED":
                conn.execute(
                    "UPDATE sponsored_campaigns SET status=?, approved_by=?, approved_at=?, updated_at=? WHERE id=?",
                    (status, actor[:80], _iso(), _iso(), campaign_id),
                )
            else:
                conn.execute("UPDATE sponsored_campaigns SET status=?, updated_at=? WHERE id=?",
                             (status, _iso(), campaign_id))
        return self.campaign(campaign_id) or {}

    # ------------------------------------------------------------- serving --

    @staticmethod
    def _empty_stats() -> Dict[str, Any]:
        return {"impressions": 0, "clicks": 0, "conversions": 0, "conversion_value": 0.0, "spend": 0.0, "ctr": None,
                "leads": 0, "orders": 0, "revenue": 0.0, "spend_today": 0.0}

    def campaign_stats(self, since: datetime | None = None) -> Dict[int, Dict[str, Any]]:
        query = ("SELECT campaign_id, event, COUNT(*) AS n, COALESCE(SUM(amount), 0) AS amount "
                 "FROM sponsored_events")
        params: list[Any] = []
        if since is not None:
            query += " WHERE created_at >= ?"
            params.append(_iso(since))
        query += " GROUP BY campaign_id, event"
        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()
            prices = {int(r["id"]): (r["cost_per_click"], r["cost_per_thousand"])
                      for r in conn.execute("SELECT id, cost_per_click, cost_per_thousand FROM sponsored_campaigns")}
        stats: Dict[int, Dict[str, Any]] = {}
        for row in rows:
            item = stats.setdefault(int(row["campaign_id"]), self._empty_stats())
            if row["event"] == "impression":
                item["impressions"] = int(row["n"])
            elif row["event"] == "click":
                item["clicks"] = int(row["n"])
            elif row["event"] == "conversion":
                item["conversions"] = int(row["n"])
                item["conversion_value"] = round(float(row["amount"] or 0), 2)
            elif row["event"] == "lead":
                item["leads"] = int(row["n"])
            elif row["event"] == "order":
                item["orders"] = int(row["n"])
                item["revenue"] = round(float(row["amount"] or 0), 2)
        today = _iso(_now().replace(hour=0, minute=0, second=0, microsecond=0))
        with self._connect() as conn:
            today_rows = conn.execute(
                "SELECT campaign_id, event, COUNT(*) AS n FROM sponsored_events WHERE created_at >= ? "
                "AND event IN ('impression', 'click') GROUP BY campaign_id, event", (today,)).fetchall()
        today_counts: Dict[int, Dict[str, int]] = {}
        for row in today_rows:
            today_counts.setdefault(int(row["campaign_id"]), {})[row["event"]] = int(row["n"])
        for campaign_id, counts in today_counts.items():
            stats.setdefault(campaign_id, self._empty_stats())
            cpc, cpm = prices.get(campaign_id, (None, None))
            stats[campaign_id]["spend_today"] = round(counts.get("click", 0) * float(cpc or 0)
                                                      + counts.get("impression", 0) / 1000 * float(cpm or 0), 2)
        for campaign_id, item in stats.items():
            cpc, cpm = prices.get(campaign_id, (None, None))
            item["spend"] = round(item["clicks"] * float(cpc or 0) + item["impressions"] / 1000 * float(cpm or 0), 2)
            item["ctr"] = round(item["clicks"] / item["impressions"] * 100, 2) if item["impressions"] else None
        return stats

    @staticmethod
    def _matches_target(campaign: Dict[str, Any], *, category: str, text: str, location: str) -> bool:
        categories = campaign.get("categories") or []
        keywords = campaign.get("keywords") or []
        if not categories and not keywords:
            return False  # never untargeted
        hit = False
        if categories and category and category in categories:
            hit = True
        if not hit and keywords and any(k and k in text for k in keywords):
            hit = True
        if not hit:
            return False
        locations = campaign.get("locations") or []
        if locations:
            place = location.lower()
            if not place or not any(loc in place for loc in locations):
                return False
        return True

    def eligible(self, *, category: str = "", subject: str = "", location: str = "",
                 placement: str = "chat_results", limit: int = 2, now: datetime | None = None,
                 kinds: tuple[str, ...] | None = None, language: str = "") -> List[Dict[str, Any]]:
        now = now or _now()
        category = str(category or "").strip().lower()
        text = f" {str(subject or '').strip().lower()} {category} "
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT c.* FROM sponsored_campaigns c LEFT JOIN sponsored_advertisers a ON a.id = c.advertiser_id "
                "WHERE c.status='APPROVED' AND COALESCE(c.archived, 0)=0 AND c.placement=? AND (c.advertiser_id IS NULL OR a.active=1) "
                "ORDER BY c.priority DESC, COALESCE(c.cost_per_click, 0) DESC, c.id",
                (placement,),
            ).fetchall()
        stats = self.campaign_stats() if rows else {}
        out: List[Dict[str, Any]] = []
        for row in rows:
            campaign = self._campaign(row)
            if kinds is not None and campaign.get("kind") not in kinds:
                continue
            starts, ends = _parse_day(campaign.get("starts_at")), _parse_day(campaign.get("ends_at"))
            if starts and now < starts:
                continue
            if ends and now >= ends + (timedelta(days=1) if len(str(campaign.get("ends_at"))) <= 10 else timedelta()):
                continue
            budget = campaign.get("budget")
            used = stats.get(int(campaign["id"]), self._empty_stats())
            if budget is not None and used["spend"] >= float(budget):
                continue
            if campaign.get("daily_budget") is not None and used["spend_today"] >= float(campaign["daily_budget"]):
                continue  # today's budget is used up; serves again tomorrow
            if campaign.get("max_impressions") and used["impressions"] >= int(campaign["max_impressions"]):
                continue
            if campaign.get("max_clicks") and used["clicks"] >= int(campaign["max_clicks"]):
                continue
            wanted = str(campaign.get("language") or "")
            if wanted and language and wanted != str(language).lower()[:len(wanted)]:
                continue
            if not str(campaign.get("destination_url") or "").startswith("https://"):
                continue
            if not self._matches_target(campaign, category=category, text=text, location=str(location or "")):
                continue
            out.append(campaign)
            if len(out) >= limit:
                break
        return out

    def record_impression(self, campaign_id: int, *, category: str = "", location: str = "") -> str:
        click_id = secrets.token_urlsafe(12)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO sponsored_events (campaign_id, event, click_id, category, location, created_at) "
                "VALUES (?, 'impression', ?, ?, ?, ?)",
                (campaign_id, click_id, category[:80], location[:120], _iso()),
            )
        return click_id

    def open_click(self, click_id: str, *, max_age_days: int = 30) -> Optional[str]:
        """The campaign's stored https URL for a click id ASKODOX issued with an
        impression; the first open is counted once. None when unknown / old."""
        click_id = str(click_id or "")[:40]
        if not click_id:
            return None
        with self._connect() as conn:
            row = conn.execute(
                "SELECT e.campaign_id, e.category, e.location, e.created_at, c.destination_url "
                "FROM sponsored_events e JOIN sponsored_campaigns c ON c.id = e.campaign_id "
                "WHERE e.click_id=? AND e.event='impression'",
                (click_id,),
            ).fetchone()
            if not row:
                return None
            created = _parse_day(row["created_at"])
            if created and _now() - created > timedelta(days=max_age_days):
                return None
            url = str(row["destination_url"] or "")
            if not url.startswith("https://"):
                return None
            if not conn.execute("SELECT 1 FROM sponsored_events WHERE click_id=? AND event='click'",
                                (click_id,)).fetchone():
                conn.execute(
                    "INSERT INTO sponsored_events (campaign_id, event, click_id, category, location, created_at) "
                    "VALUES (?, 'click', ?, ?, ?, ?)",
                    (row["campaign_id"], click_id, row["category"], row["location"], _iso()),
                )
        return url

    def record_conversion(self, campaign_id: int, *, amount: float | None = None, note: str = "") -> Dict[str, Any]:
        if self.campaign(campaign_id) is None:
            raise KeyError(campaign_id)
        if amount is not None and amount < 0:
            raise SponsoredError("amount cannot be negative")
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO sponsored_events (campaign_id, event, amount, note, created_at) "
                "VALUES (?, 'conversion', ?, ?, ?)",
                (campaign_id, amount, str(note or "")[:300], _iso()),
            )
        return self.campaign_stats().get(campaign_id, self._empty_stats())

    def tally_search(self, *, organic: int, sponsored: int) -> None:
        day = _now().date().isoformat()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO sponsored_search_daily (day, searches, organic_results, sponsored_results) "
                "VALUES (?, 1, ?, ?) ON CONFLICT(day) DO UPDATE SET searches = searches + 1, "
                "organic_results = organic_results + excluded.organic_results, "
                "sponsored_results = sponsored_results + excluded.sponsored_results",
                (day, max(0, int(organic)), max(0, int(sponsored))),
            )

    # ------------------------------------------------------------ analytics --

    def analytics(self, days: int = 30) -> Dict[str, Any]:
        days = max(1, min(int(days or 30), 365))
        since = _now() - timedelta(days=days)
        stats = self.campaign_stats(since)
        with self._connect() as conn:
            daily = [dict(r) for r in conn.execute(
                "SELECT * FROM sponsored_search_daily WHERE day >= ? ORDER BY day", (since.date().isoformat(),))]
            names = {int(r["id"]): (r["name"], r["status"])
                     for r in conn.execute("SELECT id, name, status FROM sponsored_campaigns")}
        totals = self._empty_stats()
        for item in stats.values():
            for key in ("impressions", "clicks", "conversions"):
                totals[key] += item[key]
            totals["conversion_value"] = round(totals["conversion_value"] + item["conversion_value"], 2)
            totals["spend"] = round(totals["spend"] + item["spend"], 2)
        totals["ctr"] = round(totals["clicks"] / totals["impressions"] * 100, 2) if totals["impressions"] else None
        searches = sum(int(d["searches"]) for d in daily)
        organic = sum(int(d["organic_results"]) for d in daily)
        sponsored = sum(int(d["sponsored_results"]) for d in daily)
        return {
            "days": days,
            "totals": totals,
            "campaigns": [
                {"id": cid, "name": names.get(cid, ("?", ""))[0], "status": names.get(cid, ("", "?"))[1], **item}
                for cid, item in sorted(stats.items())
            ],
            "organic_vs_sponsored": {
                "searches": searches,
                "organic_results": organic,
                "sponsored_results": sponsored,
                "sponsored_share_percent": round(sponsored / (organic + sponsored) * 100, 2)
                if organic + sponsored else None,
            },
            "daily": daily,
        }
