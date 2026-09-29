"""Customer-facing commerce engines built on the platform store.

- SmartLinkEngine    one ASKODOX link -> installed app -> deep link -> web ->
                     safe fallback page; link health checks.
- AffiliateEngine    manually pasted / program affiliate links as disclosed
                     result rows, tracked redirect, conversions -> commission
                     ledger (pending / approved / rejected / paid).
- MerchantOfferEngine  merchant offers attached to that merchant's results;
                     claim (lead) -> redeem, with per-user, total and budget
                     limits (duplicate redemption refused).
- VideoEngine        approved videos matched to the current intent, embed
                     URLs where the platform allows embedding, honest
                     explanations (only from a transcript actually provided).
- ReviewEngine       approved reviews with their source + relationship label.

Relevance is keyword / category overlap with the request -- no random filler:
when nothing matches, nothing is returned.
"""
from __future__ import annotations

import html
import json
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Callable, Dict, Iterable, List, Optional
from urllib.parse import parse_qs, quote, urlencode, urlparse, urlunparse

from app.repositories.platform_repository import PlatformConflict, PlatformRepository, now_iso
from app.services import platform_schema as ps

_WORD = re.compile(r"[a-z0-9ఀ-౿ऀ-ॿ]+", re.IGNORECASE)
_STOP = {"the", "a", "an", "in", "near", "me", "for", "to", "of", "and", "i", "want", "need", "buy", "show",
         "best", "with", "my", "on", "at", "is", "it", "some", "any", "please", "find", "get"}


def words(*texts: Any) -> set[str]:
    out: set[str] = set()
    for text in texts:
        if isinstance(text, (list, tuple, set)):
            out |= words(*text)
            continue
        for w in _WORD.findall(str(text or "").lower()):
            if w not in _STOP and len(w) > 1:
                out.add(w[:-1] if w.endswith("s") and len(w) > 3 else w)
    return out


def relevance(record_words: set[str], query_words: set[str]) -> float:
    if not record_words or not query_words:
        return 0.0
    hit = record_words & query_words
    return len(hit) / max(1, len(query_words))


def _age_ok(created_at: str, days: int) -> bool:
    try:
        created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return False
    return datetime.now(timezone.utc) - created <= timedelta(days=days)


# ---------------------------------------------------------------- links --

class SmartLinkEngine:
    def __init__(self, repo: PlatformRepository) -> None:
        self.repo = repo

    def by_slug(self, slug: str) -> Optional[Dict[str, Any]]:
        slug = str(slug or "").strip().lower()
        for record in self.repo.list("smart_links"):
            if str(record["data"].get("slug") or "").lower() == slug:
                return record
        return None

    @staticmethod
    def _with_utm(url: str, utm: Dict[str, Any] | None) -> str:
        if not url or not utm or not url.startswith("https://"):
            return url
        parts = urlparse(url)
        query = parse_qs(parts.query)
        for key, value in utm.items():
            if str(key).startswith("utm_") and value:
                query.setdefault(str(key), [str(value)])
        return urlunparse(parts._replace(query=urlencode(query, doseq=True)))

    def plan(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """The ordered attempts for this link. Only values validated by the
        schema are used, so nothing here can become an open redirect."""
        d = record["data"]
        lt = d.get("link_type")
        digits = re.sub(r"\D", "", str(d.get("phone") or ""))
        attempts: List[Dict[str, str]] = []
        if lt == "whatsapp" and digits:
            text = f"?text={quote(str(d.get('message') or ''))}" if d.get("message") else ""
            attempts.append({"kind": "whatsapp", "url": f"https://wa.me/{digits}{text}"})
        elif lt == "call" and digits:
            attempts.append({"kind": "call", "url": f"tel:+{digits}"})
        elif lt == "maps" and d.get("latitude") is not None and d.get("longitude") is not None:
            lat, lng = d["latitude"], d["longitude"]
            attempts.append({"kind": "maps_app", "url": f"geo:{lat},{lng}?q={lat},{lng}"})
            attempts.append({"kind": "maps_web", "url": f"https://www.google.com/maps/search/?api=1&query={lat},{lng}"})
        for key, kind in (("android_app_link", "android_app_link"), ("ios_universal_link", "ios_universal_link"),
                          ("deep_link", "deep_link")):
            if d.get(key):
                attempts.append({"kind": kind, "url": str(d[key])})
        if d.get("web_url"):
            attempts.append({"kind": "web", "url": self._with_utm(str(d["web_url"]), d.get("utm"))})
        if d.get("fallback_url"):
            attempts.append({"kind": "fallback", "url": str(d["fallback_url"])})
        return {"attempts": attempts, "package": d.get("android_package") or ""}

    def landing_page(self, record: Dict[str, Any], *, platform: str) -> str:
        """Tries the app / deep link first, then the web, then a safe page --
        all client-side, with no credentials involved."""
        plan = self.plan(record)
        app_first = [a for a in plan["attempts"]
                     if a["kind"] in ("deep_link", "maps_app", "call") or
                     (a["kind"] == "android_app_link" and platform == "android") or
                     (a["kind"] == "ios_universal_link" and platform == "ios")]
        web = [a for a in plan["attempts"] if a["kind"] in ("web", "whatsapp", "maps_web", "fallback",
                                                            "android_app_link", "ios_universal_link")]
        first = app_first[0]["url"] if app_first else ""
        second = web[0]["url"] if web else ""
        title = html.escape(record["name"])
        links = "".join(f'<li><a rel="noopener" href="{html.escape(a["url"])}">{html.escape(a["kind"])}</a></li>'
                        for a in plan["attempts"] if not a["url"].startswith("tel:") or a["kind"] == "call")
        return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · ASKODOX</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;background:#f6f7fb;color:#172033}}main{{max-width:420px;margin:12vh auto;padding:24px;background:#fff;border-radius:16px;box-shadow:0 8px 30px #0001}}h1{{font-size:18px}}a{{color:#5b3df5}}</style>
</head><body><main><h1>{title}</h1><p id="s">Opening…</p><ul>{links}</ul>
<p style="font-size:12px;color:#667">If nothing opens, choose a link above.</p></main>
<script>
var first={json.dumps(first)}, second={json.dumps(second)};
function go(u){{ if(u) window.location.href=u; }}
if(first){{ var t=setTimeout(function(){{ document.getElementById('s').textContent='Opening in the browser…'; go(second); }}, 1400);
  document.addEventListener('visibilitychange',function(){{ if(document.hidden) clearTimeout(t); }}); go(first); }}
else {{ go(second); }}
if(!first && !second) document.getElementById('s').textContent='This link has no destination yet.';
</script></body></html>"""

    def health(self, record: Dict[str, Any], fetch: Callable[[str], int]) -> Dict[str, Any]:
        """Checks every https destination (app-only schemes cannot be probed
        from a server and are reported as such)."""
        results = []
        for attempt in self.plan(record)["attempts"]:
            url = attempt["url"]
            if not url.startswith("https://"):
                results.append({"kind": attempt["kind"], "url": url, "status": "not_checkable"})
                continue
            try:
                code = int(fetch(url))
                results.append({"kind": attempt["kind"], "url": url, "status": code,
                                "ok": 200 <= code < 400})
            except Exception as error:  # network / DNS / TLS
                results.append({"kind": attempt["kind"], "url": url, "status": f"error:{type(error).__name__}",
                                "ok": False})
        checkable = [r for r in results if "ok" in r]
        return {"checked_at": now_iso(), "results": results,
                "ok": bool(checkable) and all(r["ok"] for r in checkable),
                "state": "OK" if checkable and all(r["ok"] for r in checkable)
                else ("NOT_CHECKABLE" if not checkable else "ERROR")}


# ------------------------------------------------------------ affiliate --

DISCLOSURE_AFFILIATE = "Affiliate link -- ASKODOX may earn a commission if you buy."


class AffiliateEngine:
    def __init__(self, repo: PlatformRepository) -> None:
        self.repo = repo

    def _program(self, program_id: str) -> Optional[Dict[str, Any]]:
        record = self.repo.get(program_id)
        return record if record and record["resource"] == "affiliate_programs" else None

    def rows(self, demand: Dict[str, Any], *, limit: int = 3, trace_key: str = "") -> List[Dict[str, Any]]:
        if str(demand.get("side") or "").upper() == "OFFER":
            return []
        query = words(demand.get("subject"), demand.get("raw_text"))
        category = str(demand.get("domain") or "").lower()
        scored = []
        for link in self.repo.list("affiliate_links"):
            if not ps.is_live(link):
                continue
            program = self._program(link["data"].get("program_id") or "")
            if not program or not ps.is_live(program):
                continue  # a paused / expired program switches its links off
            d = link["data"]
            score = relevance(words(d.get("keywords"), d.get("title")), query)
            if d.get("category") and category and str(d["category"]).lower() == category:
                score += .25
            if score >= .34:
                scored.append((score, link, program))
        scored.sort(key=lambda s: -s[0])
        rows = []
        for score, link, program in scored[:limit]:
            click_id = f"afc_{secrets.token_urlsafe(12)}"
            d = link["data"]
            self.repo.record_event("impression", click_id=click_id, link_id=link["id"],
                                   partner_id=program["id"], category=category,
                                   detail={"kind": "affiliate", "trace": trace_key})
            rows.append({
                "id": f"affiliate-{link['id']}", "title": d.get("title"), "subtitle": program["name"],
                "source": "online", "match_source": "online", "segment": "partner", "affiliate": True,
                "source_name": program["data"].get("network") or program["name"],
                "destination_url": d.get("affiliate_url"), "redirect_path": f"/go/af/{click_id}",
                "click_id": click_id, "image_url": d.get("image_url"), "price": None, "price_verified": False,
                "disclosure": DISCLOSURE_AFFILIATE, "affiliate_link_id": link["id"], "relevance": round(score, 3),
            })
        return rows

    def open_click(self, click_id: str) -> Optional[str]:
        """The stored affiliate URL for a click id ASKODOX issued (<= 30 days,
        link still live); counted once."""
        impressions = self.repo.events(event="impression", click_id=click_id, limit=1)
        if not impressions or not _age_ok(impressions[0]["at"], 30):
            return None
        link = self.repo.get(impressions[0]["link_id"] or "")
        if not link or not ps.is_live(link):
            return None
        url = str(link["data"].get("affiliate_url") or "")
        if not url.startswith("https://"):
            return None
        self.repo.record_event("click", click_id=click_id, link_id=link["id"],
                               partner_id=impressions[0]["partner_id"], dedupe_key=f"click:{click_id}",
                               detail={"kind": "affiliate"})
        self.repo.record_event("redirect", click_id=click_id, link_id=link["id"],
                               partner_id=impressions[0]["partner_id"], dedupe_key=f"redirect:{click_id}")
        return url

    @staticmethod
    def commission(program: Dict[str, Any], link: Optional[Dict[str, Any]], order_value: float | None) -> float | None:
        source = link["data"] if link and link["data"].get("commission_type") else program["data"]
        kind = source.get("commission_type")
        if kind == "percent" and order_value is not None and source.get("commission_percent") is not None:
            return round(float(order_value) * float(source["commission_percent"]) / 100, 2)
        if kind == "fixed" and source.get("commission_fixed") is not None:
            return round(float(source["commission_fixed"]), 2)
        return None

    def record_conversion(self, *, click_id: str, order_value: float | None, external_ref: str,
                          status: str = "pending", actor: str) -> Dict[str, Any]:
        """A conversion reported by the network / merchant (postback, report
        or manual entry from its dashboard) -> commission in the ledger."""
        clicks = self.repo.events(event="click", click_id=click_id, limit=1)
        if not clicks:
            raise PlatformConflict("unknown click id -- conversions must come from an ASKODOX click")
        link = self.repo.get(clicks[0]["link_id"] or "")
        program = self._program(link["data"].get("program_id") if link else "") if link else None
        if not program:
            raise PlatformConflict("the click's program no longer exists")
        days = int(program["data"].get("attribution_days") or 30)
        if not _age_ok(clicks[0]["at"], days):
            raise PlatformConflict(f"outside the {days}-day attribution window")
        amount = self.commission(program, link, order_value)
        state = {"pending": "PENDING", "approved": "CONFIRMED", "rejected": "REJECTED"}.get(status)
        if state is None:
            raise PlatformConflict("status must be pending, approved or rejected")
        conversion_id = f"cnv_{external_ref}"[:80]
        self.repo.record_event("conversion", click_id=click_id, link_id=link["id"], partner_id=program["id"],
                               conversion_id=conversion_id, value=order_value, currency="INR",
                               dedupe_key=f"conversion:{program['id']}:{external_ref}", detail={"kind": "affiliate"})
        entry, created = self.repo.ledger_add(
            idempotency_key=f"affiliate:{program['id']}:{external_ref}", kind="affiliate_commission",
            amount=amount or 0.0, state="EXPECTED" if amount is None else state, partner_id=program["id"],
            conversion_id=conversion_id, source_ref=click_id,
            note="commission unknown until the network reports it" if amount is None else "", actor=actor)
        if created and amount is not None:
            self.repo.record_event("commission", click_id=click_id, partner_id=program["id"],
                                   conversion_id=conversion_id, value=amount, currency="INR",
                                   dedupe_key=f"commission:{entry['id']}")
        return {"conversion_id": conversion_id, "ledger": entry, "created": created}


# --------------------------------------------------------- merchant offers --

class MerchantOfferEngine:
    def __init__(self, repo: PlatformRepository, *, is_new_customer: Callable[[str], bool] | None = None) -> None:
        self.repo = repo
        self.is_new_customer = is_new_customer or (lambda _user: True)

    def live_for(self, merchant_ids: Iterable[str]) -> Dict[str, Dict[str, Any]]:
        wanted = {str(m) for m in merchant_ids if m}
        best: Dict[str, Dict[str, Any]] = {}
        for offer in self.repo.list("merchant_offers"):
            if offer["owner_ref"] in wanted and ps.is_live(offer) and self._remaining(offer) != 0:
                best.setdefault(offer["owner_ref"], offer)
        return best

    def _claims(self, offer_id: str) -> List[Dict[str, Any]]:
        return [r for r in self.repo.rewards() if r["campaign_id"] == offer_id and r["source"] == "merchant_offer"]

    def _remaining(self, offer: Dict[str, Any]) -> Optional[int]:
        limit = offer["data"].get("redemption_limit")
        if not limit:
            return None
        used = sum(1 for r in self._claims(offer["id"]) if r["state"] in ("CLAIMED", "REDEEMED"))
        return max(0, int(limit) - used)

    @staticmethod
    def benefit_value(offer: Dict[str, Any], bill: float | None) -> float | None:
        d = offer["data"]
        kind, value = d.get("offer_kind"), d.get("value")
        if value is None:
            return None
        if kind == "percent":
            if bill is None:
                return None
            amount = float(bill) * float(value) / 100
        elif kind in ("flat", "cashback", "voucher"):
            amount = float(value)
        else:
            return None
        if d.get("max_discount") is not None:
            amount = min(amount, float(d["max_discount"]))
        return round(amount, 2)

    def summary(self, offer: Dict[str, Any]) -> str:
        d = offer["data"]
        kind, value = d.get("offer_kind"), d.get("value")
        text = {"flat": f"₹{value:g} off" if value else "Discount", "percent": f"{value:g}% off" if value else
                "Discount", "cashback": f"₹{value:g} cashback" if value else "Cashback",
                "bogo": "Buy 1 Get 1", "free_delivery": "Free delivery", "gift": "Free gift",
                "free_item": "Free item", "bundle": "Bundle offer", "points": "Reward points",
                "voucher": "Voucher", "special_price": "Special price", "custom": d.get("title")}.get(kind, d.get("title"))
        if d.get("max_discount") and kind == "percent":
            text += f" up to ₹{d['max_discount']:g}"
        if d.get("min_bill"):
            text += f" on ₹{d['min_bill']:g}+"
        return str(text)

    def claim(self, offer_id: str, user_id: str) -> Dict[str, Any]:
        offer = self.repo.get(offer_id)
        if not offer or offer["resource"] != "merchant_offers" or not ps.is_live(offer):
            raise PlatformConflict("this offer is not available")
        if offer["owner_ref"] == user_id:
            raise PlatformConflict("merchants cannot claim their own offer")
        d = offer["data"]
        eligibility = d.get("eligibility") or "all"
        if eligibility != "all" and self.is_new_customer(user_id) != (eligibility == "new"):
            raise PlatformConflict(f"this offer is for {eligibility} customers")
        mine = [r for r in self._claims(offer_id) if r["user_ref"] == user_id]
        active = [r for r in mine if r["state"] == "CLAIMED"]
        if active:
            return active[0] | {"offer": self.summary(offer), "claim_code": active[0]["id"],
                                "already": True}  # idempotent
        per_user = int(d.get("per_user_limit") or 1)
        if len([r for r in mine if r["state"] in ("CLAIMED", "REDEEMED")]) >= per_user:
            raise PlatformConflict("you have already used this offer")
        if self._remaining(offer) == 0:
            raise PlatformConflict("this offer has been fully claimed")
        reward, _ = self.repo.reward_add(
            idempotency_key=f"mof:{offer_id}:{user_id}:{len(mine) + 1}", user_ref=user_id, reward_type="merchant",
            state="AVAILABLE", amount=float(d.get("value") or 0) or None, points=None if d.get("value") else 1,
            source="merchant_offer", campaign_id=offer_id, title=self.summary(offer), expires_at=d.get("valid_to"),
            actor=user_id)
        reward = self.repo.transition_reward(reward["id"], "CLAIMED", actor=user_id, user_ref=user_id)
        self.repo.record_event("claim", user_ref=user_id, offer_id=offer_id, merchant_id=offer["owner_ref"],
                               dedupe_key=f"claim:{reward['id']}")
        self.repo.record_event("lead", user_ref=user_id, offer_id=offer_id, merchant_id=offer["owner_ref"],
                               dedupe_key=f"lead:{reward['id']}", detail={"kind": "merchant_offer"})
        return reward | {"offer": self.summary(offer), "claim_code": reward["id"]}

    def redeem(self, claim_code: str, merchant_id: str, *, bill_amount: float | None) -> Dict[str, Any]:
        reward = self.repo.reward(claim_code)
        if not reward or reward["source"] != "merchant_offer":
            raise KeyError(claim_code)
        offer = self.repo.get(reward["campaign_id"] or "")
        if not offer or offer["owner_ref"] != merchant_id:
            raise KeyError(claim_code)  # only the offering merchant can redeem
        if reward["state"] == "REDEEMED":
            raise PlatformConflict("this claim was already redeemed")
        min_bill = offer["data"].get("min_bill")
        if min_bill and (bill_amount is None or float(bill_amount) < float(min_bill)):
            raise PlatformConflict(f"minimum bill is ₹{float(min_bill):g}")
        budget = offer["data"].get("budget")
        benefit = self.benefit_value(offer, bill_amount)
        if budget is not None and benefit is not None:
            spent = sum(float((e["value"] or 0)) for e in self.repo.events(event="redemption", offer_id=offer["id"],
                                                                          limit=100000))
            if spent + benefit > float(budget) + 1e-9:
                raise PlatformConflict("the offer budget is used up")
        reward = self.repo.transition_reward(claim_code, "REDEEMED", actor=merchant_id)
        self.repo.record_event("redemption", user_ref=reward["user_ref"], offer_id=offer["id"],
                               merchant_id=merchant_id, value=benefit, currency="INR",
                               dedupe_key=f"redeem:{claim_code}", detail={"bill": bill_amount})
        return reward | {"benefit": benefit}

    def report(self, offer_id: str) -> Dict[str, Any]:
        claims = self._claims(offer_id)
        redemptions = self.repo.events(event="redemption", offer_id=offer_id, limit=100000)
        offer = self.repo.get(offer_id) or {"data": {}, "id": offer_id}
        return {"claims": sum(1 for c in claims if c["state"] in ("CLAIMED", "REDEEMED")),
                "redeemed": sum(1 for c in claims if c["state"] == "REDEEMED"),
                "expired": sum(1 for c in claims if c["state"] == "EXPIRED"),
                "benefit_given": round(sum(float(e["value"] or 0) for e in redemptions), 2),
                "remaining": self._remaining(offer)}


# ---------------------------------------------------------------- videos --

_YT = re.compile(r"(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})")


def embed_url(platform: str, url: str) -> Optional[str]:
    """In-app playback only where the platform provides an official embed."""
    if platform == "youtube":
        match = _YT.search(url or "")
        if match:
            return f"https://www.youtube-nocookie.com/embed/{match.group(1)}?playsinline=1&rel=0"
    return None  # Instagram / Facebook / others: open via their app / web link


RELATION_LABEL = {
    "organic": "", "merchant": "From the business", "creator": "Creator's opinion",
    "affiliate": "Affiliate -- ASKODOX may earn a commission", "sponsored": "Sponsored",
}


class VideoEngine:
    def __init__(self, repo: PlatformRepository) -> None:
        self.repo = repo

    def _creator(self, creator_id: str | None) -> Optional[Dict[str, Any]]:
        record = self.repo.get(creator_id) if creator_id else None
        return record if record and record["resource"] == "creators" else None

    def card(self, video: Dict[str, Any], *, score: float = 0, reason: str = "") -> Dict[str, Any]:
        d = video["data"]
        creator = self._creator(d.get("creator_id"))
        relationship = d.get("relationship") or "organic"
        return {
            "id": f"video-{video['id']}", "video_id": video["id"], "title": d.get("title"),
            "source": "video", "match_source": "video", "segment": "video",
            "destination_url": d.get("url"), "embed_url": embed_url(d.get("platform") or "", d.get("url") or ""),
            "image_url": d.get("thumbnail_url"), "duration": d.get("duration"), "platform": d.get("platform"),
            "source_name": creator["name"] if creator else (d.get("platform") or "").title(),
            "creator_id": d.get("creator_id"), "video_type": d.get("video_type"),
            "relationship": relationship, "sponsored": relationship == "sponsored",
            "sponsored_label": "Sponsored" if relationship == "sponsored" else None,
            "affiliate": relationship == "affiliate",
            "disclosure": RELATION_LABEL.get(relationship) or None,
            "products": d.get("products") or [], "services": d.get("services") or [],
            "language": d.get("language"), "analyzed": bool(d.get("transcript")),
            "reason": reason, "relevance": round(score, 3),
        }

    def rows(self, demand: Dict[str, Any], *, limit: int = 4) -> List[Dict[str, Any]]:
        query = words(demand.get("subject"), demand.get("raw_text"))
        category = str(demand.get("domain") or "").lower()
        location = str(demand.get("location_text") or "").lower()
        scored = []
        for video in self.repo.list("videos"):
            if not ps.is_live(video):
                continue
            d = video["data"]
            vw = words(d.get("keywords"), d.get("title"), d.get("products"), d.get("services"))
            score = relevance(vw, query)
            if category and category in [c.lower() for c in d.get("categories") or []]:
                score += .2
            if d.get("location") and location and str(d["location"]).lower() in location:
                score += .1
            if d.get("featured"):
                score += .05
            if score >= .34:  # at least a real overlap with what the user asked
                scored.append((score, video))
        scored.sort(key=lambda s: (-s[0], s[1]["data"].get("relationship") == "sponsored"))
        return [self.card(v, score=s, reason="matches your search") for s, v in scored[:limit]]

    def explain(self, video_id: str, question: str, *, language: str = "en") -> Dict[str, Any]:
        video = self.repo.get(video_id)
        if not video or video["resource"] != "videos" or video["status"] not in ("ACTIVE", "SCHEDULED", "PAUSED"):
            raise KeyError(video_id)
        d = video["data"]
        te = language == "te"
        relationship = d.get("relationship") or "organic"
        label = RELATION_LABEL.get(relationship) or ""
        creator = self._creator(d.get("creator_id"))
        transcript = str(d.get("transcript") or "").strip()
        if not transcript:
            return {
                "video_id": video_id, "analyzed": False,
                "answer": ("ఈ వీడియోలోని మాటలను నేను విశ్లేషించలేదు. శీర్షిక, వివరణ మాత్రమే చెప్పగలను."
                           if te else "I haven't analyzed what is said in this video. I can only go by its title and "
                                      "description."),
                "from_source": [s for s in (d.get("title"), d.get("description")) if s],
                "relationship": relationship, "relationship_label": label,
                "creator": creator["name"] if creator else None,
                "next": self._next(d, te),
            }
        sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+", transcript) if len(s.strip()) > 12]
        q = words(question)
        pros = {"good", "best", "advantage", "pro", "benefit", "great", "fast", "love", "strong"}
        cons = {"bad", "disadvantage", "con", "problem", "issue", "slow", "weak", "drawback", "expensive"}
        if q & {"advantage", "pro", "good", "benefit"}:
            q |= pros
        if q & {"disadvantage", "con", "bad", "problem", "drawback"}:
            q |= cons
        ranked = sorted(sentences, key=lambda s: -len(words(s) & q))
        picked = [s for s in ranked if words(s) & q][:4] or sentences[:3]
        return {
            "video_id": video_id, "analyzed": True,
            "answer": ("వీడియోలో చెప్పినది (మూల భాషలో):" if te else "What the video says:"),
            "from_source": picked, "relationship": relationship, "relationship_label": label,
            "creator": creator["name"] if creator else None,
            "note": (label or ("Creator's opinion" if creator else "")) or None,
            "next": self._next(d, te),
        }

    @staticmethod
    def _next(d: Dict[str, Any], te: bool) -> List[Dict[str, str]]:
        subject = (d.get("products") or d.get("services") or [d.get("title")])[0]
        actions = [("find_local", "దగ్గరలో కనుగొనండి" if te else "Find near me", f"{subject} near me"),
                   ("deals", "డీల్స్ చూపించండి" if te else "Show deals", f"{subject} offers"),
                   ("compare", "పోల్చండి" if te else "Compare", f"Compare {subject} with alternatives"),
                   ("reviews", "రివ్యూలు" if te else "Show reviews", f"{subject} reviews")]
        if d.get("services"):
            actions.insert(1, ("local_service", "స్థానిక సేవ" if te else "Local service",
                               f"{d['services'][0]} service near me"))
        else:
            actions.insert(2, ("used", "వాడినది" if te else "Used / cheaper", f"used {subject}"))
        return [{"action": a, "label": label, "ask": ask} for a, label, ask in actions]


class ReviewEngine:
    def __init__(self, repo: PlatformRepository) -> None:
        self.repo = repo

    def for_query(self, text: str, *, limit: int = 6) -> Dict[str, Any]:
        query = words(text)
        rows = []
        for review in self.repo.list("reviews", status="ACTIVE"):
            d = review["data"]
            score = relevance(words(d.get("subject_name"), d.get("keywords")), query)
            if score >= .34:
                rows.append((score, review))
        rows.sort(key=lambda s: -s[0])
        items = [{
            "id": r["id"], "subject": r["data"].get("subject_name"), "rating": r["data"].get("rating"),
            "text": r["data"].get("text"), "kind": r["data"].get("review_kind"),
            "author_type": r["data"].get("author_type"), "source": r["data"].get("source"),
            "source_url": r["data"].get("source_url"), "video_id": r["data"].get("video_id"),
            "relationship": r["data"].get("relationship"),
            "label": {"independent": "Independent review", "sponsored": "Sponsored review",
                      "affiliate": "Affiliate review", "merchant": "From the business"}.get(
                r["data"].get("relationship"), ""),
            "merchant_response": r["data"].get("merchant_response"),
        } for _, r in rows[:limit]]
        independent = [i["rating"] for i in items if i["rating"] is not None and i["relationship"] == "independent"]
        return {"items": items, "independent_average": round(sum(independent) / len(independent), 2)
                if independent else None, "independent_count": len(independent)}
