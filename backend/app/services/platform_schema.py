"""Schema + lifecycle for the configurable Command Center resources.

One definition per resource drives validation, the admin API and the admin UI
(forms, tables, filters, action buttons). Adding a resource here gives it
create / edit / view / delete / archive / restore / duplicate / search /
filter / sort / export / audit history and its lifecycle actions -- nothing is
a visual placeholder.

Validation is strict: https-only web links (no open redirects), app deep
links restricted to an allow-listed scheme syntax, bounded numbers, enums,
dates. Secrets never live in these records (integrations keep them encrypted
server-side, see integration_registry.py).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Callable, Dict, List, Optional, Tuple


class SchemaError(ValueError):
    pass


@dataclass(frozen=True)
class F:
    name: str
    label: str
    kind: str = "text"  # text | longtext | url | deeplink | number | int | bool | date | enum | list | json | ref
    required: bool = False
    options: Tuple[str, ...] = ()
    min: float | None = None
    max: float | None = None
    ref: str = ""  # resource name (or "partners") for kind=ref
    help: str = ""
    list_column: bool = False
    filter: bool = False


@dataclass(frozen=True)
class Action:
    name: str
    label: str
    to_status: str | None = None           # status transition
    from_status: Tuple[str, ...] = ()      # allowed current statuses (empty = any non-terminal)
    confirm: bool = False
    manage: bool = True                    # needs the manage permission
    effect: str = ""                       # special effect handled by the service
    perm: str = ""                         # verb override, e.g. "approve" -> <area>:approve


@dataclass(frozen=True)
class Resource:
    name: str
    label: str
    group: str
    prefix: str
    permission: str                        # "<area>" -> <area>:view / <area>:manage
    fields: Tuple[F, ...]
    statuses: Tuple[str, ...]
    initial_status: str
    actions: Tuple[Action, ...] = ()
    name_field: str = "title"
    description: str = ""
    owner_scoped: bool = False             # may be created by an app user (merchant self-service)
    flag: str = ""                         # feature flag gating customer-facing use
    four_eyes: bool = False                # the creator may not approve their own record

    def field(self, name: str) -> Optional[F]:
        return next((f for f in self.fields if f.name == name), None)


_URL = re.compile(r"^https://[^\s/$.?#][^\s]*$", re.IGNORECASE)
_DEEPLINK = re.compile(r"^[a-z][a-z0-9+.\-]{1,30}://[^\s]*$", re.IGNORECASE)
_BLOCKED_SCHEMES = {"javascript", "data", "file", "vbscript", "about", "content"}
_SLUG = re.compile(r"^[a-z0-9][a-z0-9\-]{1,62}$")


def _date(value: str) -> str:
    text = str(value).strip()
    try:
        datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        raise SchemaError("must be a date (YYYY-MM-DD) or date-time") from None
    return text


def clean_value(spec: F, value: Any) -> Any:
    if value is None or (isinstance(value, str) and value.strip() == ""):
        if spec.required:
            raise SchemaError(f"{spec.label} is required")
        return [] if spec.kind == "list" else ({} if spec.kind == "json" else None)
    kind = spec.kind
    if kind in ("text", "longtext"):
        text = str(value).strip()
        limit = 4000 if kind == "longtext" else 300
        if len(text) > limit:
            raise SchemaError(f"{spec.label} is longer than {limit} characters")
        return text
    if kind == "url":
        text = str(value).strip()
        if not _URL.match(text):
            raise SchemaError(f"{spec.label} must be an https:// URL")
        return text[:2000]
    if kind == "deeplink":
        text = str(value).strip()
        scheme = text.split(":", 1)[0].lower()
        if scheme in _BLOCKED_SCHEMES or not (_DEEPLINK.match(text) or _URL.match(text)):
            raise SchemaError(f"{spec.label} must be an app link (scheme://...) or https URL")
        return text[:2000]
    if kind in ("number", "int"):
        try:
            number = float(value)
        except (TypeError, ValueError):
            raise SchemaError(f"{spec.label} must be a number") from None
        if spec.min is not None and number < spec.min:
            raise SchemaError(f"{spec.label} must be at least {spec.min:g}")
        if spec.max is not None and number > spec.max:
            raise SchemaError(f"{spec.label} must be at most {spec.max:g}")
        return int(number) if kind == "int" else round(number, 4)
    if kind == "bool":
        if isinstance(value, bool):
            return value
        return str(value).strip().lower() in ("1", "true", "yes", "on")
    if kind == "date":
        return _date(value)
    if kind == "enum":
        text = str(value).strip().lower()
        if text not in spec.options:
            raise SchemaError(f"{spec.label} must be one of: {', '.join(spec.options)}")
        return text
    if kind == "list":
        items = value.split(",") if isinstance(value, str) else list(value or [])
        out: List[str] = []
        for item in items:
            text = str(item).strip()
            if text and text.lower() not in (o.lower() for o in out):
                out.append(text[:120])
        if spec.options:
            bad = [o for o in out if o.lower() not in spec.options]
            if bad:
                raise SchemaError(f"{spec.label}: unknown {', '.join(bad)}")
            out = [o.lower() for o in out]
        return out[:60]
    if kind == "json":
        if not isinstance(value, dict):
            raise SchemaError(f"{spec.label} must be an object")
        return {str(k)[:60]: v for k, v in list(value.items())[:40]}
    if kind == "ref":
        text = str(value).strip()
        if len(text) > 80:
            raise SchemaError(f"{spec.label} is not a valid reference")
        return text
    raise SchemaError(f"unsupported field kind {kind}")


# --------------------------------------------------------------- common --

LIFECYCLE = ("DRAFT", "PENDING_REVIEW", "SCHEDULED", "ACTIVE", "PAUSED", "REJECTED", "EXPIRED", "DISABLED")
_A = Action
COMMON_ACTIONS = (
    _A("submit", "Submit for review", "PENDING_REVIEW", ("DRAFT", "REJECTED")),
    _A("approve", "Approve", "ACTIVE", ("PENDING_REVIEW", "DRAFT")),
    _A("reject", "Reject", "REJECTED", ("PENDING_REVIEW", "DRAFT"), confirm=True),
    _A("schedule", "Schedule", "SCHEDULED", ("DRAFT", "PENDING_REVIEW", "PAUSED"), effect="schedule"),
    _A("enable", "Enable", "ACTIVE", ("DISABLED", "DRAFT", "EXPIRED")),
    _A("disable", "Disable", "DISABLED", (), confirm=True),
    _A("pause", "Pause", "PAUSED", ("ACTIVE", "SCHEDULED")),
    _A("resume", "Resume", "ACTIVE", ("PAUSED",)),
    _A("expire", "Expire now", "EXPIRED", ("ACTIVE", "PAUSED", "SCHEDULED"), confirm=True),
)
VALIDITY = (F("valid_from", "Valid from", "date"), F("valid_to", "Valid to", "date", list_column=True))

AFFILIATE_LINK_TYPES = ("product", "service", "travel", "food", "ticket", "insurance", "commerce", "custom")
COMMISSION_TYPES = ("percent", "fixed", "tiered", "none")
RELATIONSHIPS = ("organic", "merchant", "creator", "affiliate", "sponsored")
PLATFORMS = ("youtube", "instagram", "facebook", "merchant", "creator", "askodox", "other")
VIDEO_TYPES = ("review", "user_review", "unboxing", "comparison", "howto", "demo", "explanation", "service_demo",
               "shop_intro", "deal", "influencer", "short", "long")
OFFER_KINDS = ("flat", "percent", "cashback", "voucher", "gift", "free_item", "bogo", "bundle", "points",
               "free_delivery", "special_price", "custom")
NOTIFICATION_CHANNELS = ("in_app", "push", "email", "sms", "whatsapp")
NOTIFICATION_TYPES = ("order", "offer", "coupon", "reward", "payment", "seller_response", "support", "referral",
                      "campaign", "system")

RESOURCES: Dict[str, Resource] = {}


def _register(resource: Resource) -> Resource:
    RESOURCES[resource.name] = resource
    return resource


_register(Resource(
    name="affiliate_programs", label="Affiliate programs", group="Affiliate", prefix="afp",
    permission="affiliate", name_field="name", initial_status="DRAFT", statuses=LIFECYCLE,
    description="Networks / merchants / programs ASKODOX earns commission from. Credentials stay in Integrations.",
    fields=(
        F("name", "Program name", required=True, list_column=True),
        F("network", "Network / merchant", list_column=True, filter=True),
        F("partner_id", "Partner Hub partner id", "ref", ref="partners"),
        F("program_id", "Program id"),
        F("affiliate_id", "Affiliate id"),
        F("tracking_id", "Tracking id"),
        F("commission_type", "Commission type", "enum", options=COMMISSION_TYPES, list_column=True),
        F("commission_percent", "Commission %", "number", min=0, max=100),
        F("commission_fixed", "Fixed commission ₹", "number", min=0),
        F("attribution_days", "Cookie / attribution window (days)", "int", min=0, max=365),
        F("categories", "Categories", "list", filter=True),
        F("countries", "Countries", "list"),
        *VALIDITY,
        F("notes", "Notes", "longtext"),
    ),
    actions=COMMON_ACTIONS,
))

_register(Resource(
    name="affiliate_links", label="Affiliate links", group="Affiliate", prefix="afl",
    permission="affiliate", initial_status="DRAFT", statuses=LIFECYCLE, flag="results.affiliate",
    description="Paste affiliate / tracking / deep links. ACTIVE links matching a search are shown as disclosed "
                "affiliate options and open through ASKODOX's tracked redirect.",
    fields=(
        F("title", "Title shown to customers", required=True, list_column=True),
        F("program_id", "Affiliate program", "ref", ref="affiliate_programs", required=True, list_column=True),
        F("link_type", "Link type", "enum", options=AFFILIATE_LINK_TYPES, required=True, list_column=True,
          filter=True),
        F("original_url", "Original URL", "url"),
        F("affiliate_url", "Affiliate / tracking URL", "url", required=True),
        F("deep_link", "App deep link", "deeplink"),
        F("image_url", "Image URL", "url"),
        F("keywords", "Match keywords", "list", filter=True),
        F("category", "Category", filter=True),
        F("country", "Country"),
        F("commission_type", "Commission type (override)", "enum", options=COMMISSION_TYPES),
        F("commission_percent", "Commission % (override)", "number", min=0, max=100),
        F("commission_fixed", "Fixed commission ₹ (override)", "number", min=0),
        *VALIDITY,
    ),
    actions=COMMON_ACTIONS,
))

_register(Resource(
    name="smart_links", label="Smart links", group="Links", prefix="lnk",
    permission="links", initial_status="ACTIVE", statuses=("ACTIVE", "DISABLED"),
    description="One ASKODOX link that tries the installed app, then the deep link, then the web, then a safe page.",
    fields=(
        F("title", "Title", required=True, list_column=True),
        F("slug", "Slug (askodox.link/l/<slug>)", required=True, list_column=True),
        F("link_type", "Type", "enum", required=True, list_column=True, filter=True,
          options=("web", "app_link", "universal_link", "deep_link", "affiliate", "campaign", "merchant",
                   "whatsapp", "call", "maps", "product", "service")),
        F("web_url", "Web URL", "url"),
        F("android_app_link", "Android App Link", "url"),
        F("ios_universal_link", "iOS Universal Link", "url"),
        F("deep_link", "Deep link (scheme://...)", "deeplink"),
        F("android_package", "Android package"),
        F("phone", "Phone (for call / WhatsApp)"),
        F("message", "Prefilled message (WhatsApp)"),
        F("latitude", "Latitude (maps)", "number", min=-90, max=90),
        F("longitude", "Longitude (maps)", "number", min=-180, max=180),
        F("fallback_url", "Safe fallback URL", "url"),
        F("campaign_id", "Campaign id", "ref"),
        F("utm", "UTM parameters", "json"),
    ),
    actions=(
        _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
        _A("disable", "Disable", "DISABLED", ("ACTIVE",), confirm=True),
        _A("test", "Test link health", None, (), effect="link_test"),
    ),
))

_register(Resource(
    name="merchant_offers", label="Merchant offers", group="Offers", prefix="mof",
    permission="offers", initial_status="PENDING_REVIEW", statuses=LIFECYCLE, owner_scoped=True,
    flag="offers.merchant",
    description="Offers local merchants / sellers / providers give ASKODOX customers. Approved offers appear on "
                "that merchant's results; claims and redemptions are tracked.",
    fields=(
        F("title", "Offer title", required=True, list_column=True),
        F("merchant_name", "Merchant", list_column=True, filter=True),
        F("offer_kind", "Offer type", "enum", options=OFFER_KINDS, required=True, list_column=True, filter=True),
        F("value", "Value (₹ or %)", "number", min=0),
        F("max_discount", "Maximum discount ₹", "number", min=0),
        F("min_bill", "Minimum bill ₹", "number", min=0),
        F("description", "Description", "longtext"),
        F("products", "Products / services", "list"),
        F("categories", "Categories", "list", filter=True),
        F("location", "Location", filter=True),
        F("radius_km", "Radius km", "number", min=0, max=500),
        F("redemption_limit", "Total redemptions", "int", min=1),
        F("per_user_limit", "Per customer", "int", min=1, max=100),
        F("budget", "Budget ₹", "number", min=0),
        F("eligibility", "Customers", "enum", options=("all", "new", "existing")),
        F("terms", "Terms", "longtext"),
        *VALIDITY,
    ),
    actions=COMMON_ACTIONS,
))

_register(Resource(
    name="creators", label="Creators & influencers", group="Video & Social", prefix="cre",
    permission="content", name_field="name", initial_status="PENDING_REVIEW", statuses=LIFECYCLE,
    fields=(
        F("name", "Name", required=True, list_column=True),
        F("platform", "Platform", "enum", options=PLATFORMS, required=True, list_column=True, filter=True),
        F("profile_url", "Profile URL", "url"),
        F("handle", "Handle"),
        F("categories", "Content categories", "list", filter=True),
        F("languages", "Languages", "list"),
        F("relationship", "Commercial relationship", "enum", options=("none", "affiliate", "sponsored", "campaign"),
          list_column=True),
        F("verified", "Verified", "bool", list_column=True),
        F("notes", "Notes", "longtext"),
    ),
    actions=COMMON_ACTIONS + (
        _A("verify", "Verify", None, (), effect="verify"),
        _A("unverify", "Unverify", None, (), effect="unverify"),
    ),
))

_register(Resource(
    name="video_sources", label="Video sources", group="Video & Social", prefix="vsr",
    permission="content", name_field="name", initial_status="DISABLED", statuses=LIFECYCLE,
    description="Where videos come from. API providers need credentials in Integrations; manual / embed sources "
                "work without them.",
    fields=(
        F("name", "Name", required=True, list_column=True),
        F("platform", "Platform", "enum", options=PLATFORMS, required=True, list_column=True, filter=True),
        F("provider", "Provider", "enum", options=("api", "embed", "manual"), list_column=True),
        F("channel_url", "Channel / profile URL", "url"),
        F("creator_id", "Creator", "ref", ref="creators"),
        F("category", "Category", filter=True),
        F("language", "Language"),
        F("location", "Location relevance"),
        F("priority", "Priority", "int", min=0, max=100),
        F("relationship", "Relationship", "enum", options=RELATIONSHIPS),
    ),
    actions=COMMON_ACTIONS,
))

_register(Resource(
    name="videos", label="Videos", group="Video & Social", prefix="vid",
    permission="content", initial_status="PENDING_REVIEW", flag="results.videos",
    statuses=("PENDING_REVIEW", "SCHEDULED", "ACTIVE", "PAUSED", "REJECTED", "EXPIRED", "DISABLED"),
    description="Approved (ACTIVE) videos join search results when their keywords / category / products match. "
                "Sponsored and affiliate videos are always disclosed.",
    fields=(
        F("title", "Title", required=True, list_column=True),
        F("platform", "Platform", "enum", options=PLATFORMS, required=True, list_column=True, filter=True),
        F("url", "Video URL", "url", required=True),
        F("thumbnail_url", "Thumbnail URL", "url"),
        F("duration", "Duration (mm:ss)"),
        F("language", "Language", filter=True),
        F("video_type", "Type", "enum", options=VIDEO_TYPES, list_column=True, filter=True),
        F("description", "Description", "longtext"),
        F("keywords", "Keywords", "list", filter=True),
        F("categories", "Categories", "list", filter=True),
        F("products", "Related products", "list"),
        F("services", "Related services", "list"),
        F("location", "Location relevance"),
        F("creator_id", "Creator", "ref", ref="creators", list_column=True),
        F("merchant_ref", "Merchant / seller (user ref)", "ref"),
        F("provider_ref", "Service provider (user ref)", "ref"),
        F("source_id", "Source", "ref", ref="video_sources"),
        F("source_ref", "Discovered as (web video reference yt_/wv_)"),
        F("relationship", "Relationship", "enum", options=RELATIONSHIPS, required=True, list_column=True,
          filter=True),
        F("affiliate_link_id", "Affiliate link", "ref", ref="affiliate_links"),
        F("campaign_id", "Sponsored campaign id", "ref"),
        F("transcript", "Transcript / captions (only if legitimately provided)", "longtext"),
        F("featured", "Featured", "bool", list_column=True),
        F("start_at", "Show from", "date"),
        F("end_at", "Show until", "date"),
    ),
    actions=(
        _A("approve", "Approve", "ACTIVE", ("PENDING_REVIEW",)),
        _A("reject", "Reject", "REJECTED", ("PENDING_REVIEW",), confirm=True),
        _A("schedule", "Schedule", "SCHEDULED", ("PENDING_REVIEW", "PAUSED"), effect="schedule"),
        _A("pause", "Pause", "PAUSED", ("ACTIVE", "SCHEDULED")),
        _A("resume", "Resume", "ACTIVE", ("PAUSED",)),
        _A("disable", "Disable", "DISABLED", (), confirm=True),
        _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
        _A("feature", "Feature", None, (), effect="feature"),
        _A("unfeature", "Unfeature", None, (), effect="unfeature"),
    ),
))

_register(Resource(
    name="reviews", label="Reviews", group="Video & Social", prefix="rev",
    permission="content", name_field="subject_name", initial_status="PENDING_REVIEW",
    statuses=("PENDING_REVIEW", "ACTIVE", "REJECTED", "DISABLED"),
    description="Written, rating, video and creator reviews with their source. Promotional content is never "
                "labelled an independent review.",
    fields=(
        F("subject_name", "Product / service / business", required=True, list_column=True),
        F("subject_type", "Subject", "enum", options=("product", "service", "merchant"), required=True,
          list_column=True, filter=True),
        F("subject_ref", "Subject reference", "ref"),
        F("rating", "Rating (1-5)", "number", min=1, max=5, list_column=True),
        F("text", "Review", "longtext"),
        F("review_kind", "Kind", "enum", options=("written", "rating", "video", "creator"), required=True,
          filter=True),
        F("author_type", "Author", "enum", options=("user", "creator", "merchant", "expert"), required=True,
          list_column=True, filter=True),
        F("relationship", "Relationship", "enum", options=("independent", "sponsored", "affiliate", "merchant"),
          required=True, list_column=True, filter=True),
        F("source", "Source (askodox / youtube / ...)"),
        F("source_url", "Source URL", "url"),
        F("video_id", "Video", "ref", ref="videos"),
        F("keywords", "Keywords", "list"),
        F("merchant_response", "Merchant response", "longtext"),
    ),
    actions=(
        _A("approve", "Approve", "ACTIVE", ("PENDING_REVIEW",)),
        _A("reject", "Reject", "REJECTED", ("PENDING_REVIEW",), confirm=True),
        _A("disable", "Disable", "DISABLED", ("ACTIVE",), confirm=True),
        _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
    ),
))

_register(Resource(
    name="notification_templates", label="Notification templates", group="Notifications", prefix="ntp",
    permission="notifications", name_field="key", initial_status="ACTIVE", statuses=("ACTIVE", "DISABLED"),
    description="Message text per channel / type / language. {placeholders} are filled from the event.",
    fields=(
        F("key", "Template key", required=True, list_column=True),
        F("channel", "Channel", "enum", options=NOTIFICATION_CHANNELS, required=True, list_column=True,
          filter=True),
        F("type", "Type", "enum", options=NOTIFICATION_TYPES, required=True, list_column=True, filter=True),
        F("language", "Language", list_column=True),
        F("title", "Title", required=True),
        F("body", "Body", "longtext", required=True),
    ),
    actions=(
        _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
        _A("disable", "Disable", "DISABLED", ("ACTIVE",), confirm=True),
        _A("preview", "Preview", None, (), manage=False, effect="preview"),
    ),
))

_register(Resource(
    name="notification_rules", label="Notification rules", group="Notifications", prefix="nrl",
    permission="notifications", name_field="name", initial_status="DISABLED", statuses=("ACTIVE", "DISABLED"),
    fields=(
        F("name", "Rule name", required=True, list_column=True),
        F("event", "When this event happens", required=True, list_column=True),
        F("template_key", "Template key", required=True, list_column=True),
        F("channels", "Channels", "list", options=NOTIFICATION_CHANNELS, list_column=True),
        F("throttle_minutes", "At most once per (minutes)", "int", min=0, max=10080),
    ),
    actions=(
        _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
        _A("disable", "Disable", "DISABLED", ("ACTIVE",), confirm=True),
    ),
))

_register(Resource(
    name="subscription_promos", label="Subscription promotions", group="Subscriptions", prefix="spr",
    permission="growth", initial_status="DRAFT", statuses=LIFECYCLE,
    description="Coupons, waivers, free periods, special-day offers, promotional credit and usage benefits for "
                "plans (prices stay editable in Plans).",
    fields=(
        F("title", "Title", required=True, list_column=True),
        F("kind", "Kind", "enum", required=True, list_column=True, filter=True,
          options=("coupon", "waiver", "free_period", "special_day", "promo_credit", "usage_benefit")),
        F("plan_code", "Plan code", list_column=True),
        F("code", "Promo code"),
        F("value", "Value (₹ / % / credit)", "number", min=0),
        F("days", "Free days", "int", min=0, max=3650),
        F("max_uses", "Maximum uses", "int", min=1),
        *VALIDITY,
    ),
    actions=COMMON_ACTIONS,
))

TERMINAL = {"REJECTED", "EXPIRED"}


class UnknownResource(SchemaError, KeyError):
    pass


_register(Resource(
    name="promotion_campaigns", label="Targeted promotions", group="Notifications", prefix="prm",
    permission="notifications", name_field="title", initial_status="DRAFT", statuses=LIFECYCLE, four_eyes=True,
    flag="notifications.promotions",
    description="Targeted in-app cards and (with the customer's opt-in) push / SMS / WhatsApp / e-mail. "
                "Audience from ASKODOX data only, frequency-capped, reviewed by a second person before it runs. "
                "Compact / quarter / half-screen cards only -- never full-screen.",
    fields=(
        F("title", "Title", required=True, list_column=True),
        F("body", "Message", "longtext", required=True),
        F("size", "Card size", "enum", options=("compact", "quarter", "half"), required=True, list_column=True),
        F("image_url", "Small image (https)", "url"),
        F("cta_label", "Button label"),
        F("deep_link", "Button opens (app link or https)", "deeplink"),
        F("channels", "Channels", "list", options=NOTIFICATION_CHANNELS, required=True, list_column=True),
        F("pricing", "Pricing", "enum", options=("free", "paid", "promo_credit", "subscription", "custom"),
          required=True, list_column=True, filter=True),
        F("price", "Price (₹)", "number", min=0, max=10000000),
        F("advertiser", "Advertiser / merchant"),
        F("sponsored", "Sponsored (shows a 'Sponsored' label)", "bool"),
        F("audience", "Audience", "enum", options=("all", "users", "roles", "party_a", "party_b"), required=True,
          filter=True),
        F("user_refs", "User references (u_...)", "list"),
        F("roles", "Roles", "list", options=("buyers", "sellers", "service_providers", "job_seekers",
                                              "delivery_ride")),
        F("categories", "Categories", "list"),
        F("intents", "Intents", "list", options=("buy", "sell", "hire", "work", "rent", "book", "service",
                                                  "deliver", "ride")),
        F("interests", "Interests (keywords)", "list"),
        F("town", "Town / city"),
        F("district", "District"),
        F("pincode", "PIN code"),
        F("state", "State"),
        F("country", "Country"),
        F("latitude", "Centre latitude", "number", min=-90, max=90),
        F("longitude", "Centre longitude", "number", min=-180, max=180),
        F("radius_km", "Radius (km)", "number", min=0.1, max=500),
        F("schedule", "Schedule", "enum", required=True, list_column=True,
          options=("immediate", "one_time", "hourly", "daily", "weekly", "monthly", "yearly", "custom")),
        F("start_at", "Start", "date", list_column=True),
        F("end_at", "End", "date"),
        F("interval_hours", "Custom interval (hours)", "int", min=1, max=8760),
        F("cap_per_user_day", "Max per user per day", "int", min=1, max=5),
        F("cap_per_user_week", "Max per user per week", "int", min=1, max=20),
        F("max_sends", "Stop after this many messages", "int", min=1, max=10000000),
    ),
    actions=(
        _A("submit", "Submit for review", "PENDING_REVIEW", ("DRAFT", "REJECTED")),
        _A("approve", "Approve", "ACTIVE", ("PENDING_REVIEW",), perm="approve"),
        _A("reject", "Reject", "REJECTED", ("PENDING_REVIEW",), confirm=True, perm="approve"),
        _A("pause", "Pause", "PAUSED", ("ACTIVE",)),
        _A("resume", "Resume", "ACTIVE", ("PAUSED",)),
        _A("disable", "Stop", "DISABLED", (), confirm=True),
        _A("estimate", "Estimate audience", effect="promo_estimate", manage=False),
        _A("preview", "Preview card", effect="promo_preview", manage=False),
        _A("send_now", "Send due messages now", effect="promo_run", confirm=True),
    ),
))


# --- Owner OS configuration (staging round) --------------------------------
ENABLE_DISABLE = (
    _A("enable", "Enable", "ACTIVE", ("DISABLED",)),
    _A("disable", "Disable", "DISABLED", ("ACTIVE",), confirm=True),
)
USER_ROLES = ("buyer", "seller", "service_provider", "job_seeker", "employer", "delivery_partner", "driver",
              "creator", "any")
PRIORITY_TYPES = ("nearby_request", "opportunity", "offer", "lead", "job", "delivery", "campaign")

_register(Resource(
    name="referral_credit_rules", label="Referral credit rules", group="Growth", prefix="rcr",
    permission="growth", name_field="name", initial_status="DISABLED", statuses=("ACTIVE", "DISABLED"),
    description="Referrals earn ASKODOX Priority Notification Credits (not cash). Every number here is "
                "configurable; the ACTIVE rule with the highest priority applies. Staging defaults are for testing.",
    fields=(
        F("name", "Rule name", required=True, list_column=True),
        F("priority", "Priority (higher wins)", "int", min=0, max=1000),
        F("referrals_required", "Referrals required per award", "int", required=True, min=1, max=1000,
          list_column=True),
        F("credits_awarded", "Credits per award", "int", required=True, min=0, max=100000, list_column=True),
        F("bonus_slabs", "Bonus slabs", "json",
          help='{"<referrals>": <extra credits>}, e.g. {"5": 5, "10": 10}: extra credits when the referrer '
               'reaches that many registered referrals.'),
        F("expiry_days", "Credits expire after (days, 0 = never)", "int", min=0, max=3650, list_column=True),
        F("max_balance", "Maximum balance (0 = no cap)", "int", min=0, max=1000000),
        F("eligible_roles", "Eligible referrer roles", "list", options=USER_ROLES),
        F("eligible_notification_types", "Credits can boost", "list", options=PRIORITY_TYPES),
        F("daily_limit", "Max credits earned per day (0 = none)", "int", min=0, max=100000),
        F("monthly_limit", "Max credits earned per month (0 = none)", "int", min=0, max=1000000),
        F("spend_daily_limit", "Max priority sends per user per day (0 = none)", "int", min=0, max=1000),
    ),
    actions=ENABLE_DISABLE,
))

_register(Resource(
    name="greeting_templates", label="Greetings & conversation texts", group="Conversation", prefix="grt",
    permission="content", name_field="text", initial_status="ACTIVE", statuses=("ACTIVE", "DISABLED"),
    description="Chosen automatically from the user's local time, language and context. Language is any "
                "BCP-47 tag (e.g. en, te, hi, ta, es, ar, fr-CA); blank = fallback for every language. "
                "{name} is replaced by the user's first name when known. Several texts per kind rotate so "
                "the same greeting is not repeated.",
    fields=(
        F("kind", "Kind", "enum", required=True, list_column=True, filter=True,
          options=("morning", "afternoon", "evening", "night", "returning", "role_switch", "no_result",
                   "fallback")),
        F("language", "Language (BCP-47, blank = any)", list_column=True, filter=True),
        F("text", "Text", "longtext", required=True, list_column=True),
    ),
    actions=ENABLE_DISABLE,
))

_register(Resource(
    name="email_roles", label="Domain & e-mail roles", group="Setup", prefix="eml",
    permission="integrations", name_field="role", initial_status="DISABLED", statuses=("ACTIVE", "DISABLED"),
    description="Which address serves each purpose and how (forwarding such as Namecheap, a mailbox, or "
                "send-only through a mail provider). Nothing here buys or creates a mailbox; passwords/API keys "
                "stay in Integrations.",
    fields=(
        F("role", "Purpose", "enum", required=True, list_column=True, filter=True,
          options=("support", "admin", "partners", "notifications", "no_reply", "security", "billing", "other")),
        F("address", "Address (e.g. support@your-domain)", required=True, list_column=True),
        F("mode", "Mode", "enum", required=True, list_column=True,
          options=("forwarding", "mailbox", "send_only", "not_configured")),
        F("forwards_to", "Forwards to (owner inbox)"),
        F("needs_inbound", "Must receive mail", "bool"),
        F("needs_outbound", "ASKODOX sends from it", "bool"),
        F("verified_on", "Last verified (test mail received)", "date", list_column=True),
        F("notes", "Notes (DNS: MX / SPF / DKIM / DMARC status)", "longtext"),
    ),
    actions=ENABLE_DISABLE,
))

_register(Resource(
    name="delivery_partners", label="Delivery partners", group="Delivery", prefix="dlp",
    permission="delivery", name_field="name", initial_status="PENDING_REVIEW", statuses=LIFECYCLE,
    four_eyes=True,
    description="Party B for delivery requests: ASKODOX-registered independent partners/drivers and external "
                "logistics partners (connected later through Integrations). Matching uses service type, "
                "availability and distance -- never one hard-wired provider.",
    fields=(
        F("name", "Name", required=True, list_column=True),
        F("kind", "Kind", "enum", required=True, list_column=True, filter=True,
          options=("independent", "external")),
        F("user_ref", "ASKODOX user (u_...) for independents"),
        F("integration_key", "Integration key (external partners)"),
        F("services", "Services", "list", required=True, list_column=True,
          options=("food", "grocery", "parcel", "product", "pickup_drop", "documents", "other")),
        F("vehicle", "Vehicle", "enum", options=("walk", "bicycle", "two_wheeler", "three_wheeler", "car",
                                                  "van", "truck", "any")),
        F("town", "Town / city", filter=True, list_column=True),
        F("country", "Country"),
        F("latitude", "Base latitude", "number", min=-90, max=90),
        F("longitude", "Base longitude", "number", min=-180, max=180),
        F("radius_km", "Serves within (km)", "number", min=0.1, max=500),
        F("available", "Available now", "bool", list_column=True),
        F("verified", "Identity / licence verified", "bool"),
    ),
    actions=(
        _A("submit", "Submit for review", "PENDING_REVIEW", ("DRAFT", "REJECTED")),
        _A("approve", "Approve", "ACTIVE", ("PENDING_REVIEW",), perm="approve"),
        _A("reject", "Reject", "REJECTED", ("PENDING_REVIEW",), confirm=True, perm="approve"),
        _A("pause", "Suspend", "PAUSED", ("ACTIVE",), confirm=True),
        _A("resume", "Reinstate", "ACTIVE", ("PAUSED",)),
    ),
))

QA_STATUSES = ("OPEN", "NOT TESTED", "CODE READY", "STAGING VERIFIED", "PHONE VERIFIED", "LIVE VERIFIED")

_register(Resource(
    name="qa_checks", label="Phone-test / QA center", group="Setup", prefix="qac",
    permission="qa", name_field="title", initial_status="OPEN", statuses=QA_STATUSES,
    description="Every phone-test finding with its evidence. A finding moves to PHONE VERIFIED only with an "
                "evidence link / note from a real phone test.",
    fields=(
        F("title", "Finding / check", required=True, list_column=True),
        F("area", "Area", filter=True, list_column=True),
        F("build", "Build tested", list_column=True),
        F("result", "What happened", "longtext"),
        F("evidence", "Evidence (link or note)", "longtext"),
        F("tested_on", "Tested on", "date", list_column=True),
    ),
    actions=tuple(_A(s.lower().replace(" ", "_"), "Mark " + s, s, ()) for s in QA_STATUSES),
))

def resource(name: str) -> Resource:
    try:
        return RESOURCES[name]
    except KeyError:
        raise UnknownResource(f"unknown resource {name}") from None


def clean_data(res: Resource, data: Dict[str, Any], *, partial: bool = False,
               existing: Dict[str, Any] | None = None) -> Dict[str, Any]:
    known = {f.name for f in res.fields}
    unknown = sorted(set(data) - known)
    if unknown:
        raise SchemaError(f"unknown field(s): {', '.join(unknown)}")
    out = dict(existing or {})
    for spec in res.fields:
        if partial and spec.name not in data:
            continue
        try:
            out[spec.name] = clean_value(spec, data.get(spec.name))
        except SchemaError as error:
            raise SchemaError(f"{spec.name}: {error}") from None
    # Cross-field rules.
    frm, to = out.get("valid_from") or out.get("start_at"), out.get("valid_to") or out.get("end_at")
    if frm and to and str(to) < str(frm):
        raise SchemaError("end date is before start date")
    if res.name == "smart_links":
        if out.get("slug"):
            out["slug"] = str(out["slug"]).strip().lower()
        if not _SLUG.match(str(out.get("slug") or "")):
            raise SchemaError("slug: lowercase letters, digits and dashes (2-63)")
        lt = out.get("link_type")
        if lt in ("whatsapp", "call") and not out.get("phone"):
            raise SchemaError("phone is required for call / WhatsApp links")
        if lt == "maps" and (out.get("latitude") is None or out.get("longitude") is None) and not out.get("web_url"):
            raise SchemaError("maps links need latitude + longitude or a web URL")
        if lt not in ("whatsapp", "call", "maps") and not any(
                out.get(k) for k in ("web_url", "android_app_link", "ios_universal_link", "deep_link",
                                     "fallback_url")):
            raise SchemaError("give at least one destination (web, app link, deep link or fallback)")
    if res.name in ("affiliate_links", "affiliate_programs"):
        if out.get("commission_type") == "percent" and out.get("commission_percent") is None:
            raise SchemaError("commission_percent is required for a percent commission")
        if out.get("commission_type") == "fixed" and out.get("commission_fixed") is None:
            raise SchemaError("commission_fixed is required for a fixed commission")
    if res.name == "videos" and out.get("relationship") == "affiliate" and not out.get("affiliate_link_id"):
        raise SchemaError("an affiliate video must name its affiliate link")
    if res.name == "videos" and out.get("relationship") == "sponsored" and not out.get("campaign_id"):
        raise SchemaError("a sponsored video must name its campaign")
    return out


def record_name(res: Resource, data: Dict[str, Any]) -> str:
    return str(data.get(res.name_field) or data.get("title") or data.get("name") or res.label)[:200]


def allowed_action(res: Resource, action_name: str, status: str) -> Action:
    action = next((a for a in res.actions if a.name == action_name), None)
    if action is None:
        raise SchemaError(f"{res.label} has no action {action_name}")
    if action.to_status is None:
        return action
    if action.from_status and status not in action.from_status:
        raise SchemaError(f"cannot {action.label.lower()} from {status}")
    if not action.from_status and status in TERMINAL and action.to_status not in ("DISABLED",):
        raise SchemaError(f"cannot {action.label.lower()} from {status}")
    if action.to_status not in res.statuses:
        raise SchemaError(f"{action.to_status} is not a {res.label} status")
    return action


def public_schema() -> List[Dict[str, Any]]:
    """The admin UI's description of every resource (no secrets)."""
    out = []
    for res in RESOURCES.values():
        out.append({
            "name": res.name, "label": res.label, "group": res.group, "description": res.description,
            "statuses": list(res.statuses), "initial_status": res.initial_status, "name_field": res.name_field,
            "permission": res.permission, "flag": res.flag,
            "fields": [{"name": f.name, "label": f.label, "kind": f.kind, "required": f.required,
                        "options": list(f.options), "ref": f.ref, "list_column": f.list_column,
                        "filter": f.filter, "min": f.min, "max": f.max} for f in res.fields],
            "actions": [{"name": a.name, "label": a.label, "to_status": a.to_status,
                         "from_status": list(a.from_status), "confirm": a.confirm, "manage": a.manage}
                        for a in res.actions],
        })
    return out


def is_live(record: Dict[str, Any], *, now: datetime | None = None) -> bool:
    """ACTIVE (or SCHEDULED and inside its window) and not past its end."""
    from datetime import timezone

    now = now or datetime.now(timezone.utc)
    status = record.get("status")
    if record.get("archived") or status not in ("ACTIVE", "SCHEDULED"):
        return False
    data = record.get("data") or {}

    def parse(value: Any) -> Optional[datetime]:
        if not value:
            return None
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)

    start = parse(data.get("valid_from") or data.get("start_at"))
    end = parse(data.get("valid_to") or data.get("end_at"))
    if status == "SCHEDULED" and (start is None or now < start):
        return False
    if start and now < start:
        return False
    if end:
        day_end = end if len(str(data.get("valid_to") or data.get("end_at"))) > 10 else end.replace(
            hour=23, minute=59, second=59)
        if now > day_end:
            return False
    return True


PERMISSION_AREAS: Tuple[str, ...] = tuple(sorted({r.permission for r in RESOURCES.values()} | {
    "payments", "finance", "support", "analytics", "insights", "integrations", "accounts", "rewards"}))

Hook = Callable[..., Any]
