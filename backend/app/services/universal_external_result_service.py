"""Resolve user-facing online results from normal and affiliate mappings."""
from __future__ import annotations

import ipaddress
import json
import os
import re
import socket
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import quote_plus, urlparse
from typing import Any, Iterable


class PartnerApiConnector:
    """Small fail-closed connector for explicitly configured partner search APIs."""

    @staticmethod
    def search(provider: dict[str, Any], subject: str) -> list[dict[str, Any]]:
        if not provider.get("api_enabled", False):
            return []
        template = str(provider.get("api_base_url") or "").strip()
        if not template:
            return []
        url = template.replace("{query}", quote_plus(str(subject or "").strip()))
        parsed = urlparse(url)
        if parsed.scheme != "https" or not PartnerApiConnector._safe_public_host(parsed.hostname or "", provider):
            return []
        headers = {"Accept": "application/json", "User-Agent": "ASKODOX/1.0"}
        provider_id = re.sub(r"[^A-Z0-9]+", "_", str(provider.get("provider_id") or "").upper()).strip("_")
        api_key = os.getenv(f"ASKODOX_PARTNER_{provider_id}_API_KEY", "").strip() if provider_id else ""
        header_name = os.getenv(f"ASKODOX_PARTNER_{provider_id}_API_KEY_HEADER", "Authorization").strip()
        if api_key:
            headers[header_name] = api_key
        try:
            with urlopen(Request(url, headers=headers), timeout=4) as response:
                payload = json.loads(response.read(1024 * 1024).decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            return []
        rows = payload.get("results") if isinstance(payload, dict) else payload
        if not isinstance(rows, list):
            return []
        out: list[dict[str, Any]] = []
        for index, row in enumerate(rows[:10]):
            if not isinstance(row, dict):
                continue
            destination = UniversalExternalResultService._http_url(
                row.get("url") or row.get("destination_url")
            )
            if not destination:
                continue
            out.append({
                "id": f"partner-api-{provider.get('provider_id')}-{index}",
                "match_id": f"partner-api-{provider.get('provider_id')}-{index}",
                "provider_id": str(provider.get("provider_id") or "partner-api"),
                "title": str(row.get("title") or row.get("name") or provider.get("name") or "Online option"),
                "subtitle": str(row.get("subtitle") or row.get("description") or "Partner API result"),
                "price": row.get("price") if isinstance(row.get("price"), (int, float)) else None,
                "source": "partner_api",
                "match_source": "online",
                "destination_url": destination,
                "web_fallback_url": destination,
                "open_strategy": "web",
                "affiliate": False,
                "disclosure": str(provider.get("disclosure") or ""),
                "demo": False,
            })
        return out

    @staticmethod
    def _safe_public_host(host: str, provider: dict[str, Any]) -> bool:
        """Fail closed for localhost/private/link-local API destinations; optional host allow-list."""
        host = host.strip().lower().rstrip(".")
        allowed = {h.strip().lower().rstrip(".") for h in str(provider.get("api_allowed_hosts") or "").split(",") if h.strip()}
        if allowed and host not in allowed:
            return False
        if not host or host == "localhost" or host.endswith(".local"):
            return False
        try:
            addresses = {item[4][0] for item in socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)}
            return bool(addresses) and all(ipaddress.ip_address(ip).is_global for ip in addresses)
        except (OSError, ValueError):
            return False


class UniversalExternalResultService:
    """Convert configured external mappings into source-neutral online results.

    Mapping order and explicit relevance metadata are preserved; commission data
    is never read or used for ranking.
    """

    @staticmethod
    def resolve(
        *,
        category: str,
        subject: str,
        providers: Iterable[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        wanted = {str(category or "").strip().casefold(), str(subject or "").strip().casefold()}
        wanted.discard("")
        results: list[dict[str, Any]] = []
        for provider in providers:
            if not provider.get("active", True):
                continue
            provider_category = str(provider.get("category") or "").strip().casefold()
            if provider_category and provider_category not in wanted and provider_category not in {"general", "product"}:
                continue

            api_results = PartnerApiConnector.search(provider, subject)
            if api_results:
                results.extend(api_results)
                continue

            normal_url = UniversalExternalResultService._http_url(
                provider.get("normal_url") or provider.get("destination_url") or provider.get("base_url")
            )
            affiliate_url = UniversalExternalResultService._template_url(
                provider.get("affiliate_url") or provider.get("affiliate_url_template"),
                subject,
            )
            deep_link = UniversalExternalResultService._deep_link(
                provider.get("deep_link") or provider.get("app_link"), subject
            )
            web_fallback = affiliate_url or normal_url
            destination = deep_link or web_fallback
            if not destination:
                continue

            is_affiliate = bool(affiliate_url)
            results.append(
                {
                    "id": f"online-{provider.get('provider_id') or provider.get('name') or len(results)}",
                    "match_id": f"online-{provider.get('provider_id') or provider.get('name') or len(results)}",
                    "provider_id": str(provider.get("provider_id") or provider.get("name") or "online-provider"),
                    "title": str(provider.get("name") or provider.get("provider_id") or "Online option"),
                    "subtitle": str(provider.get("description") or "Verified online destination"),
                    "score": float(provider.get("relevance_score") or 0.35),
                    "match_source": "online",
                    "source": "online",
                    "destination_url": destination,
                    "deep_link": deep_link or "",
                    "web_fallback_url": web_fallback or "",
                    "open_strategy": "deep_link_then_web" if deep_link and web_fallback else ("deep_link" if deep_link else "web"),
                    "tracking_template": str(provider.get("tracking_template") or ""),
                    "callback_enabled": bool(provider.get("callback_enabled", False)),
                    "gateway": str(provider.get("gateway") or "external"),
                    "affiliate": is_affiliate,
                    "disclosure": str(provider.get("disclosure") or ("Affiliate link" if is_affiliate else "")),
                    "demo": False,
                }
            )
        return results

    @staticmethod
    def _template_url(value: Any, subject: str) -> str | None:
        if not value:
            return None
        return UniversalExternalResultService._http_url(
            str(value).replace("{query}", quote_plus(str(subject or "").strip()))
        )

    @staticmethod
    def _deep_link(value: Any, subject: str) -> str | None:
        if not value:
            return None
        url = str(value).replace("{query}", quote_plus(str(subject or "").strip())).strip()
        try:
            parsed = urlparse(url)
        except ValueError:
            return None
        if not parsed.scheme or parsed.scheme.casefold() in {"http", "https", "javascript", "data", "file"}:
            return None
        return url

    @staticmethod
    def _http_url(value: Any) -> str | None:
        url = str(value or "").strip()
        if url.startswith("https://") or url.startswith("http://"):
            return url
        return None


# Domains where a "watch a video about it" result is not meaningful (a ride,
# a parcel run or a job opening is not something people review on video).
_NO_VIDEO_DOMAINS = {
    "RIDE", "MOBILITY", "DELIVERY", "COURIER", "PARCEL", "WORK", "WORKERS", "JOBS", "JOB",
}

_VIDEO_HOSTS = ("youtube.com", "youtu.be", "instagram.com", "facebook.com", "fb.watch", "vimeo.com",
                "dailymotion.com", "sharechat.com", "mojapp.in", "josh.in")


def _host(url: str) -> str:
    try:
        return (urlparse(url).hostname or "").lower()
    except ValueError:
        return ""


def _is_video_host(url: str) -> bool:
    host = _host(url)
    return any(host == item or host.endswith("." + item) for item in _VIDEO_HOSTS)


_PRICE = re.compile(r"(?:₹|rs\.?|inr)\s*([0-9][0-9,]{2,})(?:\.\d+)?", re.IGNORECASE)


def price_from_text(*texts: Any) -> float | None:
    """A rupee price literally present in the returned page text, if any."""
    for text in texts:
        match = _PRICE.search(str(text or ""))
        if match:
            try:
                return float(match.group(1).replace(",", ""))
            except ValueError:
                return None
    return None


# ------------------------------------------------ page classification --
# A web page is only an "option" when it is a place to buy/book (a product
# page, a marketplace listing, a store/service page). Reviews, articles,
# forums and videos are content: useful to read, never shown as if they
# were purchasable. Directories (Justdial-style) list providers: useful for
# services, not a product listing.
PAGE_PRODUCT = "product_page"
PAGE_LISTING = "listing"
PAGE_STORE = "store"
PAGE_DIRECTORY = "directory"
PAGE_ARTICLE = "article"
PAGE_REVIEW = "review"
PAGE_FORUM = "forum"
PAGE_VIDEO = "video"
# A job opening (apply, never "buy") and a page that is only information
# (no price, nothing to buy/book on it) -- neither is shown as a shop.
PAGE_JOB = "job_listing"
PAGE_INFO = "info"
BUYABLE_PAGES = {PAGE_PRODUCT, PAGE_LISTING, PAGE_STORE}

_REVIEW_HOSTS = ("tripadvisor.", "trustpilot.", "mouthshut.com", "gadgets360.", "91mobiles.com",
                 "smartprix.com", "rtings.com", "techradar.com", "gsmarena.com", "zigwheels.com/news")
_FORUM_HOSTS = ("reddit.com", "quora.com", "team-bhp.com", "stackexchange.com", "xda-developers.com")
_DIRECTORY_HOSTS = ("justdial.com", "sulekha.com", "yelp.", "yellowpages.", "asklaila.com", "grotal.com")
_LISTING_HOSTS = ("olx.in", "quikr.com", "cars24.com", "spinny.com", "cardekho.com", "carwale.com",
                  "indiamart.com", "tradeindia.com", "magicbricks.com", "99acres.com")
JOB_HOSTS = ("naukri.com", "indeed.com", "indeed.co.in", "shine.com", "apna.co", "foundit.in",
             "timesjobs.com", "workindia.in", "glassdoor.co.in", "linkedin.com/jobs", "freshersworld.com",
             "quikr.com/jobs", "olx.in/jobs")
_STORE_HOSTS = ("amazon.in", "flipkart.com", "croma.com", "reliancedigital.in", "vijaysales.com",
                "tatacliq.com", "jiomart.com", "bigbasket.com", "meesho.com", "myntra.com", "nykaa.com",
                "urbancompany.com", "licious.in", "freshtohome.com", "swiggy.com", "zomato.com",
                "pepperfry.com", "ikea.com/in", "decathlon.in", "samsung.com/in", "lg.com/in", "mi.com/in")
_STORE_EDITORIAL_PATH = re.compile(r"(//(blog|blogs|stories|news)\.|/(blog|blogs|stories|story|article|articles|news|guides?)/)",
                                   re.IGNORECASE)
_PRODUCT_PATH = re.compile(r"/(dp|gp/product|p|product|products|item|buy|listing|ad|ads)/", re.IGNORECASE)
_ARTICLE_WORDS = re.compile(
    r"\b(review|reviews|vs\.?|versus|best (?!prices?\b|deals?\b|offers?\b|rates?\b)\d*|top \d+|buying guide|how to|what is|explained|news|"
    r"comparison|compared|tips|guide to|blog|opinion|ranked)\b",
    re.IGNORECASE,
)


def _host_matches(url: str, hosts: tuple[str, ...]) -> bool:
    low = url.casefold()
    host = _host(url)
    return any(item in host or item in low for item in hosts)


_BUY_WORDS = re.compile(
    r"\b(buy|shop|order|add to cart|in stock|price|prices|emi|book now|booking|for sale|sell(ing)?|store|"
    r"offers?|deals?|discount|sale|clearance|open box|second hand|used)\b|₹|% off",
    re.IGNORECASE,
)


def classify_page(url: str, title: Any = "", snippet: Any = "") -> str:
    """What kind of page a web result is (never guessed as buyable)."""
    if _is_video_host(url):
        return PAGE_VIDEO
    if _host_matches(url, JOB_HOSTS) or re.search(r"/jobs?/|/careers?/|job-listings?", url, re.IGNORECASE):
        return PAGE_JOB
    if _host_matches(url, _FORUM_HOSTS):
        return PAGE_FORUM
    if _host_matches(url, _REVIEW_HOSTS):
        return PAGE_REVIEW
    if _host_matches(url, _DIRECTORY_HOSTS):
        return PAGE_DIRECTORY
    if _host_matches(url, _LISTING_HOSTS):
        return PAGE_LISTING
    # A marketplace's own catalogue page ("Buy ... Online at Best Prices |
    # Amazon.in") is a store page; only its blog / stories pages are articles.
    if _host_matches(url, _STORE_HOSTS) and not _STORE_EDITORIAL_PATH.search(url):
        return PAGE_PRODUCT if _PRODUCT_PATH.search(url) else PAGE_STORE
    if _ARTICLE_WORDS.search(str(title or "")):
        return PAGE_ARTICLE
    if _PRODUCT_PATH.search(url):
        return PAGE_PRODUCT
    if _ARTICLE_WORDS.search(str(snippet or "")[:120]):
        return PAGE_ARTICLE
    # Unknown site: a shop only when the page itself offers something to
    # buy/book or states a price; otherwise it is information, not an option.
    if price_from_text(title, snippet) is not None or _BUY_WORDS.search(f"{title or ''} {snippet or ''}"):
        return PAGE_STORE
    return PAGE_INFO


# ----------------------------------------------------- region filtering --
# ASKODOX is India-first: a Home Depot / Manhattan / US$ page is not an
# option for "AC service in Vijayawada" unless the customer asked abroad.
_FOREIGN_TLDS = (".co.uk", ".uk", ".com.au", ".au", ".ca", ".us", ".de", ".fr", ".ae", ".sg",
                 ".co.nz", ".nz", ".ie", ".za", ".ph", ".my", ".pk", ".bd", ".lk", ".np")
_FOREIGN_CHAINS = ("homedepot.com", "lowes.com", "bestbuy.com", "walmart.com", "target.com", "costco.com",
                   "angi.com", "thumbtack.com", "homeadvisor.com", "craigslist.org", "ebay.com",
                   "amazon.com/", "carmax.com", "autotrader.com", "cars.com", "kbb.com", "edmunds.com",
                   "karrotmarket.com", "daangn.com", "offerup.com", "mercari.com", "poshmark.com",
                   "zillow.com", "realtor.com", "gumtree.com", "nextdoor.com", "yelp.com", "facebook.com/marketplace",
                   "argos.co", "currys.co", "jbhifi.", "harveynorman.")
_FOREIGN_MONEY = re.compile(r"(?:US\$|\$\s?\d|\bUSD\b|£\s?\d|€\s?\d|\bAUD\b|\bCAD\b|\bGBP\b|\bEUR\b)")
_INDIA_MONEY = re.compile(r"(?:₹|\brs\.?\s?\d|\binr\b|\blakh|\bcrore)", re.IGNORECASE)
_US_PLACES = re.compile(
    r"\b(manhattan|brooklyn|queens|new york|nyc|new jersey|los angeles|san francisco|seattle|boston|houston|"
    r"atlanta|california|texas|florida|chicago|usa|united states|london|toronto|vancouver|sydney|"
    r"melbourne|dubai|singapore|canada|australia)\b",
    re.IGNORECASE,
)


def region_mismatch(url: str, title: Any = "", snippet: Any = "", *, country: str = "IN",
                    wanted_place: str = "") -> bool:
    """True when a result is clearly for another country than the request."""
    if str(country or "").upper() != "IN":
        return False
    host = _host(url)
    if host.endswith(".in") or ".in/" in url.casefold():
        return False
    if any(host.endswith(tld) for tld in _FOREIGN_TLDS):
        return True
    if _host_matches(url, _FOREIGN_CHAINS):
        return True
    text = f"{title or ''} {snippet or ''}"
    if _FOREIGN_MONEY.search(text) and not _INDIA_MONEY.search(text):
        return True
    # A foreign place in the page address itself (".../manhattan/...",
    # "new-york") is decisive: the snippet mentioning India does not rescue it.
    url_words = re.sub(r"[-_/.+]+", " ", urlparse(url).path if "://" in url else url)
    url_place = _US_PLACES.search(url_words)
    if url_place and url_place.group(0).casefold() not in str(wanted_place or "").casefold():
        return True
    place_hit = _US_PLACES.search(text)
    if place_hit and place_hit.group(0).casefold() not in str(wanted_place or "").casefold():
        return not _INDIA_MONEY.search(text) and "india" not in text.casefold()
    return False


_FOREIGN_ADDRESS = re.compile(
    r"\b(usa|united states|u\.s\.a|canada|united kingdom|uk|australia|singapore|uae|united arab emirates|"
    r"new zealand|pakistan|bangladesh|sri lanka|nepal|germany|france|south korea|korea)\b"
    r"|,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b",  # US "City, NY 10001"
)


def place_region_mismatch(address: Any, *, country: str = "IN") -> bool:
    """A Maps place whose address is in another country (Home Depot in the
    US for "AC installation") is never a nearby option in India."""
    if str(country or "").upper() != "IN":
        return False
    text = str(address or "").strip()
    if not text or "india" in text.casefold():
        return False
    return bool(_FOREIGN_ADDRESS.search(text) or _FOREIGN_ADDRESS.search(text.casefold()))


def _tokens(text: str) -> set[str]:
    return {token for token in re.findall(r"[a-z0-9]+", str(text or "").casefold()) if len(token) > 1}


def relevant_to(subject: str, *texts: Any) -> bool:
    """A returned row is relevant only if it mentions the requirement's key words."""
    wanted = {token for token in _tokens(subject) if not token.isdigit()} or _tokens(subject)
    if not wanted:
        return False
    hay = _tokens(" ".join(str(text or "") for text in texts))
    return len(wanted & hay) >= max(1, -(-len(wanted) // 2))


# ----------------------------------------------------- category relevance --
# A row must belong to the SAME kind of thing the conversation is about. A
# word overlap alone ("fresh", "home", "store") let Used Cars / classifieds /
# kitchen-appliance pages into a grocery conversation; these rules drop a row
# whose own category plainly differs from the requirement's.
_VEHICLE_HOSTS = ("cars24.com", "spinny.com", "cardekho.com", "carwale.com", "bikedekho.com", "droom.in",
                  "bikewale.com", "carandbike.com", "truebil.com")
_CLASSIFIED_HOSTS = ("olx.in", "quikr.com", "click.in", "locanto.")
_PROPERTY_HOSTS = ("magicbricks.com", "99acres.com", "housing.com", "nobroker.in", "commonfloor.com")
_VEHICLE_WORDS = re.compile(r"\b(cars?|bikes?|motorcycles?|scooters?|scooty|vehicles?|suv|sedan|hatchback|"
                            r"two[- ]wheelers?|four[- ]wheelers?|auto ?rickshaw|tractors?)\b", re.IGNORECASE)
_PROPERTY_WORDS = re.compile(r"\b(flats?|apartments?|plots?|houses? for (sale|rent)|villas?|bhk|real estate|"
                             r"property|properties)\b", re.IGNORECASE)
_APPLIANCE_WORDS = re.compile(r"\b(refrigerators?|fridges?|washing machines?|microwaves?|mixer grinders?|"
                              r"air conditioners?|\bac\b|televisions?|tvs?|kitchen appliances?|home appliances?|"
                              r"geysers?|chimneys?|induction)\b", re.IGNORECASE)
_USED_WORDS_RE = re.compile(r"\b(used|second[- ]hand|pre[- ]owned|old)\b", re.IGNORECASE)
_GOODS_CATEGORIES = {"grocery", "groceries", "kirana", "food", "fruits", "vegetables", "fruits_vegetables",
                     "fashion", "clothing", "clothes", "apparel", "footwear", "meat", "chicken", "fish", "dairy",
                     "bakery", "pharmacy", "medicine", "stationery", "cosmetics", "beauty"}


# Same keyword, different intent: "fresh chicken delivery" is food for a
# kitchen, not day-old chicks, hatcheries or poultry-farm supplies; a retail
# request is not a manufacturer / exporter / wholesale (B2B) listing.
_LIVESTOCK_WORDS = re.compile(r"\b(chicks?|day[- ]old|hatcher(y|ies)|broiler farm|layer farm|poultry farm(ing)?|"
                              r"poultry (feed|equipment|cage|shed)|breeding|breeders?|livestock|fertile eggs|"
                              r"incubators?|cattle feed|fish seed|fingerlings)\b", re.IGNORECASE)
_FOOD_WORDS = re.compile(r"\b(chicken|mutton|meat|fish|prawns?|eggs?|curry cut|boneless|grocery|groceries|"
                         r"vegetables?|fruits?|milk|food|biryani)\b", re.IGNORECASE)
_B2B_HOSTS = ("indiamart.com", "tradeindia.com", "exportersindia.com", "alibaba.com", "made-in-china.com",
              "go4worldbusiness.com", "dir.indiamart")
_B2B_WORDS = re.compile(r"\b(manufacturers?|exporters?|wholesalers?|wholesale|bulk (supplier|order|buy)|"
                        r"b2b|moq|minimum order|per tonne|per ton|metric ton)\b", re.IGNORECASE)
_WANTS_B2B = re.compile(r"\b(wholesale|bulk|manufacturer|exporter|b2b|distributor|dealer(ship)?)\b", re.IGNORECASE)


def intent_conflict(subject: Any, category: Any, url: str, title: Any = "", snippet: Any = "") -> str | None:
    """A row that shares the keyword but serves another intent, or None."""
    want = f"{subject or ''} {category or ''}"
    row = f"{title or ''} {snippet or ''}"
    if _FOOD_WORDS.search(want) and _LIVESTOCK_WORDS.search(row) and not _LIVESTOCK_WORDS.search(want):
        return "livestock_page"
    if not _WANTS_B2B.search(want) and (_host_matches(url, _B2B_HOSTS) or _B2B_WORDS.search(str(title or ""))):
        return "wholesale_page"
    return None


def category_conflict(subject: Any, category: Any, url: str, title: Any = "", snippet: Any = "") -> str | None:
    """Why a row does NOT belong to this requirement's category, or None."""
    want = f"{subject or ''} {category or ''}"
    row = f"{title or ''} {snippet or ''}"
    wants_vehicle = bool(_VEHICLE_WORDS.search(want))
    wants_property = bool(_PROPERTY_WORDS.search(want))
    wants_used = bool(_USED_WORDS_RE.search(want))
    goods = bool(set(re.findall(r"[a-z_]+", str(category or "").casefold())) & _GOODS_CATEGORIES) or bool(
        set(re.findall(r"[a-z]+", str(subject or "").casefold())) & _GOODS_CATEGORIES)
    if not wants_vehicle and (_host_matches(url, _VEHICLE_HOSTS) or
                              (_VEHICLE_WORDS.search(str(title or "")) and not _VEHICLE_WORDS.search(want))):
        return "vehicle_page"
    if not wants_property and (_host_matches(url, _PROPERTY_HOSTS) or _PROPERTY_WORDS.search(str(title or ""))):
        return "property_page"
    if _host_matches(url, _CLASSIFIED_HOSTS) and (goods or not (wants_used or wants_vehicle or wants_property)):
        # Classifieds are for used goods / vehicles / property, not a shop's
        # grocery or clothing catalogue.
        return "classifieds_page"
    if goods and _APPLIANCE_WORDS.search(row) and not _APPLIANCE_WORDS.search(want):
        return "other_category"
    return None


STATUS_OK = "ok"
STATUS_NO_RESULTS = "no_results"
STATUS_UNAVAILABLE = "unavailable"
# The provider was called and failed (auth, quota, network) -- reported
# honestly instead of looking like "nothing found".
STATUS_ERROR = "error"


def _price_fields(*texts: Any) -> dict[str, Any]:
    """A price only when the page text literally states one -- flagged as
    unverified (a snippet can be stale, an EMI, or another variant)."""
    price = price_from_text(*texts)
    if price is None:
        return {"price": None, "price_verified": False, "price_source": None}
    return {"price": price, "price_verified": False, "price_source": "page_text"}


class UniversalOnlineFallbackService:
    """Real online product pages and actual videos for a requirement.

    2026-09-26 (Build 1238): the earlier version returned placeholder links
    ("Search online for TV", "TV reviews on YouTube") whenever the web
    provider was unconfigured or empty. Those are gone: only rows the Brave
    provider actually returned are shown, and ``status`` records per source
    whether it returned results, returned nothing, or is unavailable, so the
    chat can say so honestly instead of faking a section.
    """

    def __init__(self, web_search=None, *, country: str = "IN") -> None:
        self.web_search = web_search
        self.country = country
        self.status: dict[str, str] = {}
        self.filtered: dict[str, int] = {}

    def _drop(self, reason: str) -> None:
        self.filtered[reason] = self.filtered.get(reason, 0) + 1

    @property
    def _search_configured(self) -> bool:
        return callable(self.web_search) and bool(getattr(self.web_search, "configured", True))

    def online(self, *, category: str, subject: str, limit: int = 4, query: str | None = None,
               location_text: str = "", allow_directories: bool = False) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject:
            return []
        if not self._search_configured:
            self.status["online"] = STATUS_UNAVAILABLE
            return []
        # Always anchored to the customer's geography (India by default).
        where = location_text.strip() or "India"
        results: list[dict[str, Any]] = []
        rows = self._search(query or f"{subject} price buy online {where}", limit * 3)
        if getattr(self.web_search, "last_error", False):
            self.status["online"] = STATUS_ERROR
            return []
        for row in rows:
            item = self._accept(row, len(results), subject=subject, category=category,
                                location_text=location_text, allow_directories=allow_directories)
            if item is None:
                continue
            results.append(item)
            if len(results) >= limit:
                break
        self.status["online"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

    def _accept(self, row: dict[str, Any], index: int, *, subject: str, category: str, location_text: str,
                allow_directories: bool = False, kind: str = "online") -> dict[str, Any] | None:
        """One web row through every relevance / category / intent / region /
        page-kind filter; the result row, or None (counted under ``filtered``)."""
        url = UniversalExternalResultService._http_url(row.get("url"))
        if not url or _is_video_host(url):
            return None
        title, snippet = row.get("title"), row.get("snippet")
        if not relevant_to(subject, title, snippet):
            self._drop("not_relevant")
            return None
        hint = f"{category} {getattr(self, 'category_hint', '')}"
        if category_conflict(subject, hint, url, title, snippet):
            self._drop("other_category")
            return None
        if intent_conflict(subject, hint, url, title, snippet):
            self._drop("other_intent")
            return None
        if region_mismatch(url, title, snippet, country=self.country, wanted_place=location_text):
            self._drop("wrong_region")
            return None
        page_type = classify_page(url, title, snippet)
        if page_type not in BUYABLE_PAGES and not (allow_directories and page_type == PAGE_DIRECTORY):
            self._drop("not_purchasable")  # review / article / forum / video
            return None
        item = self._row(kind, index, title, snippet, url)
        item["image_url"] = row.get("thumbnail") or None
        item["source_name"] = row.get("host") or item["provider_id"]
        item.update(_price_fields(title, snippet))
        item["page_type"] = page_type
        return item

    def marketplaces(self, *, category: str, subject: str, sites: dict[str, tuple[str, str]],
                     per_site: int = 2, location_text: str = "") -> list[dict[str, Any]]:
        """Organic results from approved marketplaces (Amazon.in / Flipkart /
        Meesho ...) through ONE legitimate web-search query restricted to
        their sites. ``sites`` maps a platform id to (search host, display
        name). Same filters as ``online``; nothing is invented -- a platform
        the search engine returns nothing for simply has no row."""
        subject = " ".join(str(subject or "").split())
        if not subject or not sites:
            return []
        if not self._search_configured:
            self.status["marketplaces"] = STATUS_UNAVAILABLE
            return []
        query = f"{subject} " + " OR ".join(f"site:{host}" for host, _ in sites.values())
        rows = self._search(query, 20)
        if getattr(self.web_search, "last_error", False):
            self.status["marketplaces"] = STATUS_ERROR
            return []
        taken: dict[str, int] = {}
        results: list[dict[str, Any]] = []
        self.marketplace_hits: dict[str, int] = {platform: 0 for platform in sites}
        for row in rows:
            host = _host(str(row.get("url") or ""))
            platform = next((pid for pid, (site, _) in sites.items()
                             if host == site or host.endswith("." + site)), None)
            if platform is None:
                continue  # the engine ignored the site restriction for this row
            self.marketplace_hits[platform] += 1
            if taken.get(platform, 0) >= per_site:
                continue
            item = self._accept(row, len(results), subject=subject, category=category,
                                location_text=location_text, kind="online")
            if item is None:
                continue
            item["id"] = item["match_id"] = f"marketplace-{platform}-{len(results)}"
            item["marketplace"] = platform
            item["source_name"] = sites[platform][1]
            item["routing"] = "organic"
            results.append(item)
            taken[platform] = taken.get(platform, 0) + 1
        self.status["marketplaces"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

    def videos(self, *, category: str, subject: str, limit: int = 4, service: bool = False) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject or str(category or "").strip().upper() in _NO_VIDEO_DOMAINS:
            return []
        if not self._search_configured:
            self.status["videos"] = STATUS_UNAVAILABLE
            return []
        # A service need wants to see the work explained ("AC service
        # explained"); "review" finds marketing videos for businesses.
        query = f"{subject} explained" if service else f"{subject} review"
        video_search = getattr(self.web_search, "videos", None)
        rows: list[dict[str, Any]] = []
        if callable(video_search):
            try:
                rows = [row for row in (video_search(query, limit * 3) or []) if isinstance(row, dict)]
            except Exception:
                rows = []
        if not rows:
            rows = [row for row in self._search(f"{subject} review video", limit * 4)
                    if _is_video_host(str(row.get("url") or ""))]
        results: list[dict[str, Any]] = []
        for row in rows:
            url = UniversalExternalResultService._http_url(row.get("url"))
            if not url or not relevant_to(subject, row.get("title"), row.get("snippet")):
                self.filtered["video_not_relevant"] = self.filtered.get("video_not_relevant", 0) + 1
                continue
            item = self._row("video", len(results), row.get("title"), row.get("snippet"), url)
            item["image_url"] = row.get("thumbnail") or None
            item["source_name"] = row.get("creator") or row.get("publisher") or row.get("host") or item["provider_id"]
            item["duration"] = row.get("duration") or None
            item["page_type"] = PAGE_VIDEO
            results.append(item)
            if len(results) >= limit:
                break
        self.status["videos"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

    def _search(self, query: str, limit: int) -> list[dict[str, Any]]:
        try:
            rows = self.web_search(query, limit)
        except Exception:  # provider failures must never break matching
            return []
        return [row for row in rows or [] if isinstance(row, dict)]

    @staticmethod
    def _row(kind: str, index: int, title: Any, subtitle: Any, url: str) -> dict[str, Any]:
        host = _host(url).removeprefix("www.")
        return {
            "id": f"{kind}-{index}-{host or 'link'}",
            "match_id": f"{kind}-{index}-{host or 'link'}",
            "provider_id": host,
            "title": str(title or host or "Online option").strip()[:160],
            "subtitle": str(subtitle or "").strip()[:280],
            "score": None,
            "match_source": kind,
            "source": kind,
            "destination_url": url,
            "affiliate": False,
            "disclosure": "",
            "fallback": True,
            "demo": False,
        }
