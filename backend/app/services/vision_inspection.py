"""ASKODOX Vision Inspection: one evidence-tiered contract for every domain.

Universal first: food, vehicle, tyre, livestock, crop, prepared dish,
construction, product condition and anything else share ONE pipeline
(normalize -> one bounded model call -> sanitize -> report). A domain is a
configuration row in ``DOMAIN_PROFILES`` (what to look at, what may never be
claimed from a photo, which checks to recommend), never a separate code path.

Evidence policy (applies to every domain):
- ``observed``        what is directly visible in the supplied photos;
- ``inferred``        reasonable conclusions, each with its basis;
- ``not_verifiable``  what a camera image cannot establish;
- ``recommended_checks`` the real test / instrument / expert that can;
- ``safety_warnings`` always shown when present.

A photo never certifies anything: food safety, roadworthiness, tyre pressure,
exact animal weight, structural safety or a confirmed plant disease are moved
to ``not_verifiable`` whatever the model wrote. Digital zoom or AI
up-scaling is never evidence of detail absent from the source image.

Cost control: quick = 1 image / first model only; deep = 2 images / model
fallback; expert = up to 4 images / model fallback + optional second
provider. Images are down-scaled before the call, identical requests are
served from ``external_call_budget`` (cache + per-provider usage, visible in
Admin), and nothing here runs without a real image.
"""
from __future__ import annotations

import hashlib
import re
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

MODES: Dict[str, Dict[str, Any]] = {
    "quick": {"max_images": 1, "max_px": 1024, "max_models": 1, "second_provider": False},
    "deep": {"max_images": 2, "max_px": 1600, "max_models": 2, "second_provider": False},
    "expert": {"max_images": 4, "max_px": 2048, "max_models": 2, "second_provider": True},
}

LIST_LIMIT = 12
TEXT_LIMIT = 280

GENERAL_LIMITS = (
    "Findings come only from the photos supplied; zoomed or AI-enhanced detail is not new evidence.",
)

# Each profile: label (en/te), what the model should examine, claims a photo can
# never support (regex -> neutral wording placed in not_verifiable), checks to
# recommend, warnings always attached, and capture guidance for the app.
DOMAIN_PROFILES: Dict[str, Dict[str, Any]] = {
    "general": {
        "label": ("General inspection", "సాధారణ పరిశీలన"),
        "focus": "the main subject, its visible condition, visible text/labels and anything unusual",
        "forbidden": [],
        "checks": [],
        "warnings": [],
        "guidance": [
            ("Fill the frame with the subject in good, even light.", "మంచి వెలుతురులో వస్తువు ఫ్రేమ్ నిండేలా తీయండి."),
            ("Add a close-up of any label or damaged area.", "లేబుల్ లేదా దెబ్బతిన్న భాగాన్ని దగ్గరగా తీయండి."),
        ],
    },
    "food": {
        "label": ("Food quality & freshness", "ఆహార నాణ్యత & తాజాదనం"),
        "focus": ("colour, texture, surface defects, visible spoilage or mould, ripeness, packaging condition, "
                  "printed dates and ingredient labels"),
        "forbidden": [
            (r"\b(is|looks|appears)?\s*(safe|fit|ok|okay|good)\s+(to eat|for (human )?consumption|to consume)",
             "Whether it is safe to eat cannot be confirmed from a photo."),
            (r"\b(free (of|from)|no|without)\s+(any\s+)?(contamination|contaminants|adulterat\w*|bacteria|pathogens?|"
             r"chemicals?|pesticides?|preservatives?|formalin|toxins?)",
             "Invisible contaminants, adulterants, chemicals or pathogens cannot be ruled out from a photo."),
            (r"\b(contains?|has been (treated|injected) with|adulterated with)\s+(formalin|chemicals?|urea|detergent|"
             r"carbide|dye|colou?r)",
             "The presence of a specific adulterant or chemical cannot be confirmed from a photo."),
            (r"\b100\s*%\s*(pure|fresh|natural|organic)", "Purity or organic status cannot be confirmed from a photo."),
        ],
        "checks": [
            "Smell and feel the item before buying; reject sour, slimy or off odours.",
            "For adulteration or chemical doubts use an FSSAI-recognised lab test (or FSSAI DART kit for basic checks).",
        ],
        "warnings": ["A photo cannot certify that food is safe to eat."],
        "guidance": [
            ("Photograph in daylight, close enough to see texture.", "పగటి వెలుతురులో, టెక్స్చర్ కనిపించేంత దగ్గరగా తీయండి."),
            ("Include the printed date / label if packaged.", "ప్యాక్ అయితే తేదీ / లేబుల్ కూడా తీయండి."),
        ],
    },
    "dish": {
        "label": ("Dish & reverse recipe", "వంటకం & రివర్స్ రెసిపీ"),
        "focus": ("visible ingredients (rice, meat, vegetables, herbs, spices, garnish), texture and colour; list "
                  "hypothesised hidden ingredients and likely cooking method only as inferences"),
        "forbidden": [
            (r"\b(exact|precise)\s+(recipe|quantities|temperature|cooking time)",
             "Exact recipe quantities, temperatures and times cannot be read from a photo."),
        ],
        "checks": ["Treat the recipe as an approximation; taste and adjust while cooking."],
        "warnings": [],
        "guidance": [
            ("Shoot from above, then one close-up of the rice / gravy.", "పై నుండి ఒకటి, అన్నం / గ్రేవీ దగ్గరగా మరొకటి తీయండి."),
        ],
    },
    "vehicle": {
        "label": ("Vehicle exterior inspection", "వాహన బాహ్య పరిశీలన"),
        "focus": ("body panels, scratches, dents, paint mismatch, rust, lights, glass, mirrors, tyre appearance and "
                  "any dashboard warning lights or document text visible"),
        "forbidden": [
            (r"\b(is|looks)?\s*road\s*-?worthy\b", "Roadworthiness cannot be certified from photos."),
            (r"\b(engine|gearbox|transmission|suspension|brakes?|clutch|chassis)\s+(is|are|looks?|seems?)\s+"
             r"(fine|good|ok|okay|healthy|perfect|in good condition)",
             "Internal mechanical condition cannot be judged from exterior photos."),
            (r"\bno\s+(mechanical|engine|internal|accident)\s+(problems?|issues?|damage|history)",
             "Mechanical problems or accident history cannot be ruled out from photos."),
            (r"\b(odometer|mileage|kms?)\s+(is|are)\s+(genuine|original|not tampered)",
             "Odometer genuineness cannot be verified from a photo."),
        ],
        "checks": [
            "Get a mechanic's inspection and a test drive before buying.",
            "Match chassis / engine numbers with the RC and check challans and loan status on the official VAHAN / Parivahan service.",
        ],
        "warnings": ["Photo inspection does not certify roadworthiness or mechanical condition."],
        "guidance": [
            ("Take front, rear, left and right in daylight.", "ముందు, వెనుక, ఎడమ, కుడి వైపులు పగటి వెలుతురులో తీయండి."),
            ("Add close-ups of damage and the dashboard with engine on.", "దెబ్బలు, ఇంజిన్ ఆన్‌లో డ్యాష్‌బోర్డ్ దగ్గరగా తీయండి."),
        ],
    },
    "tyre": {
        "label": ("Tyre condition", "టైర్ పరిస్థితి"),
        "focus": "tread wear pattern, cracks, bulges, cuts, sidewall damage, uneven wear and the DOT / date code if visible",
        "forbidden": [
            (r"\b\d+(\.\d+)?\s*(psi|bar|kpa)\b", "Tyre pressure cannot be read from a photo; use a pressure gauge or TPMS."),
            (r"\btread\s+depth\s+(is|of)\s+\d+(\.\d+)?\s*mm",
             "Exact tread depth needs a tread-depth gauge; a photo only shows the wear pattern."),
            (r"\b(is|looks)?\s*safe\s+to\s+drive", "Driving safety cannot be certified from a photo."),
        ],
        "checks": ["Check pressure with a gauge when tyres are cold; measure tread with a depth gauge."],
        "warnings": ["Replace any tyre with a bulge, deep cut or exposed cords before driving."],
        "guidance": [
            ("Photograph the full tread and each sidewall.", "ట్రెడ్ మొత్తం, రెండు సైడ్‌వాల్‌లు తీయండి."),
        ],
    },
    "livestock": {
        "label": ("Livestock condition & weight (experimental)", "పశువుల పరిస్థితి & బరువు (ప్రయోగాత్మకం)"),
        "focus": ("species, visible body condition, posture, coat/feathers/scales, visible injuries and, only when a "
                  "reference object of known size is visible, an approximate live-weight RANGE with its basis"),
        "forbidden": [
            (r"\b(weighs|weight is|exactly)\s+\d+(\.\d+)?\s*(kg|kilo|kilos|kilograms?|g|grams?)\b",
             "An exact weight cannot be measured from a photo; use a weighing scale."),
            (r"\b(is|looks)?\s*(healthy|disease[- ]free|free of disease)\b",
             "Health or freedom from disease cannot be confirmed from a photo."),
        ],
        "checks": ["Confirm weight on a weighing scale; consult a veterinarian for health concerns."],
        "warnings": ["No validated photo-weight model is configured: any weight shown is an experimental range."],
        "guidance": [
            ("Side view, whole animal, standing straight, on level ground.", "జంతువు మొత్తం, పక్కనుండి, సమతల నేలపై నిలబడి ఉన్నప్పుడు తీయండి."),
            ("Place a known-size object (A4 sheet, 1 m stick) beside it.", "పక్కనే తెలిసిన సైజు వస్తువు (A4 పేపర్, 1 మీ. కర్ర) ఉంచండి."),
        ],
    },
    "crop": {
        "label": ("Crop & leaf symptoms", "పంట & ఆకు లక్షణాలు"),
        "focus": ("visible leaf/plant symptoms (spots, yellowing, curling, holes, mould, insects), growth stage and "
                  "affected area; name possible causes only as suspected"),
        "forbidden": [
            (r"\b(confirmed|definitely|certainly)\s+(diagnos\w*|disease|infection|infested)",
             "A disease is only suspected from photos; a lab or field expert confirms it."),
            (r"\b\d+(\.\d+)?\s*(ml|g|gm|grams?|kg|l|litres?|liters?)\s*(per|/)\s*(acre|hectare|ha|litre|liter|l|tank|pump)\b",
             "Chemical doses are not given from a photo; ask your local agriculture officer / KVK."),
        ],
        "checks": [
            "Confirm with your local agriculture officer, KVK or a plant-clinic / soil lab before spraying anything.",
        ],
        "warnings": ["Use pesticides only as advised by an agriculture officer and as printed on the label."],
        "guidance": [
            ("Photograph both sides of an affected leaf and the whole plant.", "దెబ్బతిన్న ఆకు రెండు వైపులా, మొక్క మొత్తం తీయండి."),
        ],
    },
    "construction": {
        "label": ("Construction & material check", "నిర్మాణం & మెటీరియల్ పరిశీలన"),
        "focus": ("visible cracks (width/pattern), dampness, finish quality, material type and visible defects; "
                  "describe crack patterns without judging structural safety"),
        "forbidden": [
            (r"\b(structurally|structure is)\s+(safe|sound|stable|fine|ok|okay)",
             "Structural safety needs a qualified structural engineer; it cannot be judged from photos."),
            (r"\b(is|are)\s+(load[- ]bearing|not load[- ]bearing)\b",
             "Whether a wall is load-bearing must be checked by an engineer from drawings / site inspection."),
        ],
        "checks": ["For widening, diagonal or structural cracks consult a structural engineer."],
        "warnings": [],
        "guidance": [
            ("Photograph the crack with a coin or scale beside it for size.", "పగులు పక్కన నాణెం లేదా స్కేల్ ఉంచి తీయండి."),
        ],
    },
    "product": {
        "label": ("Product condition & authenticity signs", "వస్తువు పరిస్థితి & నిజమైనదా సూచనలు"),
        "focus": ("visible condition, wear, damage, labels, model / serial text, packaging, seals and print quality; "
                  "list authenticity warning signs without declaring the item genuine or fake"),
        "forbidden": [
            (r"\b(is|looks)?\s*(100\s*%\s*)?(genuine|original|authentic)\b(?!\s+(signs?|markers?|features?))",
             "Authenticity cannot be confirmed from photos; verify the serial / IMEI with the brand."),
            (r"\b(is|looks)?\s*(definitely\s+)?(fake|counterfeit|duplicate)\b",
             "A photo can show warning signs but cannot prove an item is counterfeit."),
        ],
        "checks": ["Verify the serial number / IMEI on the brand's official site and ask for the purchase invoice."],
        "warnings": [],
        "guidance": [
            ("Photograph the label, serial number and any seal.", "లేబుల్, సీరియల్ నంబర్, సీల్ తీయండి."),
        ],
    },
}

_DOMAIN_ALIASES = {
    "auto": "general", "": "general", "other": "general",
    "meat": "food", "fish": "food", "milk": "food", "fruit": "food", "vegetable": "food", "grocery": "food",
    "recipe": "dish", "biryani": "dish", "meal": "dish",
    "car": "vehicle", "bike": "vehicle", "motorcycle": "vehicle", "scooter": "vehicle",
    "animal": "livestock", "goat": "livestock", "sheep": "livestock", "chicken_live": "livestock",
    "plant": "crop", "leaf": "crop", "agriculture": "crop",
    "wall": "construction", "crack": "construction", "building": "construction",
    "electronics": "product", "appliance": "product",
}


def resolve_domain(value: str | None) -> str:
    key = str(value or "").strip().lower()
    key = _DOMAIN_ALIASES.get(key, key)
    return key if key in DOMAIN_PROFILES else "general"


def resolve_mode(value: str | None) -> str:
    key = str(value or "").strip().lower()
    return key if key in MODES else "quick"


def profiles_for_app(language: str = "en") -> List[Dict[str, Any]]:
    """Domain list + capture guidance for the app, so Flutter keeps no copy."""
    te = str(language or "").lower().startswith("te")
    out = []
    for key, profile in DOMAIN_PROFILES.items():
        out.append({
            "domain": key,
            "label": profile["label"][1 if te else 0],
            "guidance": [pair[1 if te else 0] for pair in profile["guidance"]],
            "warnings": list(profile["warnings"]),
        })
    return out


def build_prompt(domain: str, mode: str, caption: str | None, language: str, image_count: int,
                 reference_object: str | None = None) -> str:
    profile = DOMAIN_PROFILES[resolve_domain(domain)]
    cap = str(caption or "").strip()[:600]
    ref = str(reference_object or "").strip()[:120]
    lang = "Telugu" if str(language or "").lower().startswith("te") else "English"
    detail = {
        "quick": "Give a short first look: the 3-5 most useful findings.",
        "deep": "Examine the important regions closely and explain each finding.",
        "expert": "Compare all images (angles / times), note changes between them and state uncertainty explicitly.",
    }[resolve_mode(mode)]
    return (
        "You are ASKODOX visual inspection. Return exactly one JSON object, no markdown. "
        f"Write every text value in {lang}. You received {image_count} image(s). {detail} "
        f"Examine: {profile['focus']}. "
        "Rules: put only what is directly visible in observed; put conclusions in inferred with their basis; "
        "put what a camera cannot establish in not_verifiable; never invent text, numbers, brands or measurements; "
        "never treat zoomed or blurry regions as clear evidence; when the photos are insufficient, say what extra "
        "photo, reference object, measurement or expert check is needed in needs_more_evidence. "
        "Give any estimated quantity only as a low-high range with its basis, never a single exact value. "
        "Schema: {\"subject\":string,\"observed\":[{\"finding\":string,\"region\":string|null,\"confidence\":0..1}],"
        "\"inferred\":[{\"finding\":string,\"basis\":string,\"confidence\":0..1}],\"not_verifiable\":[string],"
        "\"recommended_checks\":[string],\"safety_warnings\":[string],"
        "\"quantities\":[{\"name\":string,\"low\":number,\"high\":number,\"unit\":string,\"basis\":string}],"
        "\"visible_text\":string|null,\"image_quality\":{\"usable\":boolean,\"issues\":[string]},"
        "\"needs_more_evidence\":[string],\"confidence\":0..1}.\n"
        f"Reference object in photo: {ref if ref else '<none stated>'}\n"
        f"User note: {cap if cap else '<none>'}"
    )


# ---------------------------------------------------------------- sanitizing

def _text(value: Any) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    return text[:TEXT_LIMIT]


def _conf(value: Any) -> float:
    try:
        return round(max(0.0, min(float(value), 1.0)), 2)
    except (TypeError, ValueError):
        return 0.0


def _num(value: Any) -> Optional[float]:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or number in (float("inf"), float("-inf")):
        return None
    return round(number, 3)


def _strings(value: Any) -> List[str]:
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, Iterable) or isinstance(value, (bytes, dict)):
        return []
    out: List[str] = []
    for item in value:
        text = _text(item.get("finding") if isinstance(item, dict) else item)
        if text and text not in out:
            out.append(text)
    return out[:LIST_LIMIT]


def _forbidden_hit(text: str, rules: Sequence[Tuple[str, str]]) -> Optional[str]:
    for pattern, replacement in rules:
        if re.search(pattern, text, flags=re.I):
            return replacement
    return None


def _add(target: List[str], value: str) -> None:
    if value and value not in target and len(target) < LIST_LIMIT:
        target.append(value)


def sanitize_report(raw: Dict[str, Any] | None, domain: str, mode: str, *,
                    reference_object: str | None = None) -> Dict[str, Any]:
    """Coerce a model payload into the evidence contract and enforce the
    domain's never-claim rules. Pure and deterministic (unit-tested)."""
    domain = resolve_domain(domain)
    mode = resolve_mode(mode)
    profile = DOMAIN_PROFILES[domain]
    rules: List[Tuple[str, str]] = list(profile["forbidden"])
    raw = raw if isinstance(raw, dict) else {}

    not_verifiable = _strings(raw.get("not_verifiable"))
    corrected: List[str] = []

    observed: List[Dict[str, Any]] = []
    for item in raw.get("observed") or []:
        finding = _text(item.get("finding") if isinstance(item, dict) else item)
        if not finding:
            continue
        hit = _forbidden_hit(finding, rules)
        if hit:
            _add(not_verifiable, hit)
            corrected.append(finding)
            continue
        observed.append({
            "finding": finding,
            "region": _text(item.get("region")) or None if isinstance(item, dict) else None,
            "confidence": _conf(item.get("confidence")) if isinstance(item, dict) else 0.0,
        })
        if len(observed) >= LIST_LIMIT:
            break

    inferred: List[Dict[str, Any]] = []
    for item in raw.get("inferred") or []:
        finding = _text(item.get("finding") if isinstance(item, dict) else item)
        if not finding:
            continue
        hit = _forbidden_hit(finding, rules)
        if hit:
            _add(not_verifiable, hit)
            corrected.append(finding)
            continue
        basis = _text(item.get("basis")) if isinstance(item, dict) else ""
        # An inference without a basis is not evidence-backed: keep it, but at
        # low confidence so the app shows it as tentative.
        confidence = _conf(item.get("confidence")) if isinstance(item, dict) else 0.0
        inferred.append({"finding": finding, "basis": basis or None,
                         "confidence": confidence if basis else min(confidence, 0.4)})
        if len(inferred) >= LIST_LIMIT:
            break

    checks = [c for c in _strings(raw.get("recommended_checks")) if not _forbidden_hit(c, rules)]
    for check in profile["checks"]:
        _add(checks, check)
    warnings = [w for w in _strings(raw.get("safety_warnings")) if not _forbidden_hit(w, rules)]
    for warning in profile["warnings"]:
        _add(warnings, warning)

    quantities: List[Dict[str, Any]] = []
    for item in raw.get("quantities") or []:
        if not isinstance(item, dict):
            continue
        low, high = _num(item.get("low")), _num(item.get("high"))
        if low is None or high is None or low < 0 or high < low:
            continue
        name, unit, basis = _text(item.get("name")), _text(item.get("unit"))[:24], _text(item.get("basis"))
        if not name or not unit:
            continue
        status = "estimate"
        if domain == "livestock" and re.search(r"weight|బరువు", name, flags=re.I):
            if not str(reference_object or "").strip():
                _add(not_verifiable, "Weight needs a known-size reference object in the photo or a weighing scale.")
                continue
            status = "experimental"
        if high == low:
            # A single value is false precision: widen to an honest range.
            spread = max(abs(high) * 0.1, 0.01)
            low, high = round(low - spread, 3), round(high + spread, 3)
        quantities.append({"name": name, "low": max(low, 0.0), "high": high, "unit": unit,
                           "basis": basis or None, "status": status})
        if len(quantities) >= 6:
            break

    quality = raw.get("image_quality") if isinstance(raw.get("image_quality"), dict) else {}
    usable = bool(quality.get("usable", True))
    issues = _strings(quality.get("issues"))
    needs_more = _strings(raw.get("needs_more_evidence"))
    if not usable and not needs_more:
        needs_more = ["Retake the photo in better light, closer and in focus."]

    confidence = _conf(raw.get("confidence"))
    if corrected:
        confidence = min(confidence, 0.6)
    if not usable:
        confidence = min(confidence, 0.3)

    limits = list(GENERAL_LIMITS)
    status = "ok"
    if not observed and not inferred:
        status = "insufficient_evidence"
    elif not usable or confidence < 0.4:
        status = "low_confidence"

    return {
        "domain": domain,
        "mode": mode,
        "subject": _text(raw.get("subject")) or None,
        "status": status,
        "observed": observed,
        "inferred": inferred,
        "not_verifiable": not_verifiable,
        "recommended_checks": checks,
        "safety_warnings": warnings,
        "quantities": quantities,
        "visible_text": _text(raw.get("visible_text")) or None,
        "image_quality": {"usable": usable, "issues": issues},
        "needs_more_evidence": needs_more,
        "confidence": confidence,
        "corrected_claims": len(corrected),
        "limits": limits,
    }


def report_facts(report: Dict[str, Any]) -> str:
    """Short plain-text summary for the conversation context (never shown raw)."""
    parts = [f"Inspection ({report.get('domain')}, {report.get('mode')}): {report.get('subject') or 'subject unclear'}."]
    observed = [o["finding"] for o in report.get("observed") or []][:4]
    if observed:
        parts.append("Seen: " + "; ".join(observed) + ".")
    inferred = [i["finding"] for i in report.get("inferred") or []][:3]
    if inferred:
        parts.append("Likely: " + "; ".join(inferred) + ".")
    unknown = (report.get("not_verifiable") or [])[:2]
    if unknown:
        parts.append("Cannot confirm from photo: " + "; ".join(unknown))
    return " ".join(parts)[:1200]


# ---------------------------------------------------------------- service

class InspectionUnavailable(Exception):
    """No vision provider answered (none configured, or all failed)."""

    def __init__(self, model_calls: int) -> None:
        super().__init__("vision inspection unavailable")
        self.model_calls = model_calls


class VisionInspectionService:
    """Bounded, cached inspection over the existing multimodal image brain."""

    PROVIDER = "vision_inspect"
    CACHE_TTL_SECONDS = 3600

    def __init__(self, image_service: Any, normalizer: Any | None = None,
                 cached_call: Callable[..., Any] | None = None) -> None:
        self.image_service = image_service
        if normalizer is None:
            from app.services.image_normalization_service import ImageNormalizationService

            normalizer = ImageNormalizationService
        self._normalizer_factory = normalizer
        if cached_call is None:
            from app.services import external_call_budget

            cached_call = external_call_budget.cached_call
        self._cached_call = cached_call

    def _prepare(self, images: Sequence[Tuple[bytes, str]], mode: str) -> List[Tuple[bytes, str]]:
        settings = MODES[mode]
        try:
            normalizer = self._normalizer_factory(analysis_max_px=settings["max_px"])
        except TypeError:
            normalizer = self._normalizer_factory
        prepared: List[Tuple[bytes, str]] = []
        for data, mime in list(images)[: settings["max_images"]]:
            normalized = None
            try:
                normalized = normalizer.normalize(data)
            except Exception:
                normalized = None
            if normalized is not None:
                prepared.append((normalized.analysis_bytes, normalized.analysis_mime_type))
            else:
                prepared.append((data, mime))
        return prepared

    def inspect(self, images: Sequence[Tuple[bytes, str]], *, domain: str = "general", mode: str = "quick",
                caption: str | None = None, language: str = "en",
                reference_object: str | None = None) -> Dict[str, Any]:
        domain, mode = resolve_domain(domain), resolve_mode(mode)
        usable = [(data, mime) for data, mime in images if data]
        if not usable:
            raise ValueError("no image")
        dropped = max(len(usable) - MODES[mode]["max_images"], 0)
        prepared = self._prepare(usable, mode)
        prompt = build_prompt(domain, mode, caption, language, len(prepared), reference_object)
        digest = hashlib.sha256()
        for data, _ in prepared:
            digest.update(hashlib.sha256(data).digest())
        digest.update(prompt.encode("utf-8"))
        calls = {"model_calls": 0}

        def fetch() -> Dict[str, Any]:
            settings = MODES[mode]
            payload, used = self.image_service.analyze_with_prompt(
                prepared, prompt, max_models=settings["max_models"],
                allow_second_provider=settings["second_provider"])
            calls["model_calls"] = used
            return payload or {}

        raw = self._cached_call(self.PROVIDER, (digest.hexdigest(),), fetch, ttl=self.CACHE_TTL_SECONDS,
                                cache_if=lambda value: bool(value))
        if not raw:
            raise InspectionUnavailable(calls["model_calls"])
        report = sanitize_report(raw, domain, mode, reference_object=reference_object)
        report["cost"] = {
            "images_sent": len(prepared),
            "images_dropped": dropped,
            "model_calls": calls["model_calls"],
            "cached": calls["model_calls"] == 0 and bool(raw),
        }
        if dropped:
            _add(report["limits"], f"{mode.title()} scan uses up to {MODES[mode]['max_images']} image(s); "
                                   f"{dropped} extra image(s) were not sent.")
        return report
