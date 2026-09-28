"""Resolve user-facing online results from normal and affiliate mappings."""
from __future__ import annotations

import re
from urllib.parse import quote_plus, urlparse
from typing import Any, Iterable


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

            normal_url = UniversalExternalResultService._http_url(
                provider.get("normal_url") or provider.get("destination_url") or provider.get("base_url")
            )
            affiliate_url = UniversalExternalResultService._template_url(
                provider.get("affiliate_url") or provider.get("affiliate_url_template"),
                subject,
            )
            destination = affiliate_url or normal_url
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
_PRODUCT_PATH = re.compile(r"/(dp|gp/product|p|product|products|item|buy|listing|ad|ads)/", re.IGNORECASE)
_ARTICLE_WORDS = re.compile(
    r"\b(review|reviews|vs\.?|versus|best \d*|top \d+|buying guide|how to|what is|explained|news|"
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
    if _ARTICLE_WORDS.search(str(title or "")):
        return PAGE_ARTICLE
    if _host_matches(url, _STORE_HOSTS):
        return PAGE_PRODUCT if _PRODUCT_PATH.search(url) else PAGE_STORE
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
            url = UniversalExternalResultService._http_url(row.get("url"))
            if not url or _is_video_host(url):
                continue
            title, snippet = row.get("title"), row.get("snippet")
            if not relevant_to(subject, title, snippet):
                self._drop("not_relevant")
                continue
            if region_mismatch(url, title, snippet, country=self.country, wanted_place=location_text):
                self._drop("wrong_region")
                continue
            page_type = classify_page(url, title, snippet)
            if page_type not in BUYABLE_PAGES and not (allow_directories and page_type == PAGE_DIRECTORY):
                self._drop("not_purchasable")  # review / article / forum / video
                continue
            item = self._row("online", len(results), title, snippet, url)
            item["image_url"] = row.get("thumbnail") or None
            item["source_name"] = row.get("host") or item["provider_id"]
            item.update(_price_fields(title, snippet))
            item["page_type"] = page_type
            results.append(item)
            if len(results) >= limit:
                break
        self.status["online"] = STATUS_OK if results else STATUS_NO_RESULTS
        return results

    def videos(self, *, category: str, subject: str, limit: int = 4) -> list[dict[str, Any]]:
        subject = " ".join(str(subject or "").split())
        if not subject or str(category or "").strip().upper() in _NO_VIDEO_DOMAINS:
            return []
        if not self._search_configured:
            self.status["videos"] = STATUS_UNAVAILABLE
            return []
        query = f"{subject} review"
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
