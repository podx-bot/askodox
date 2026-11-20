"""AI product video for a Staff Workspace item (owner 2026-11-20: "staff add the Meesho link, photos, price and review
screenshots -- the video makes itself").

One 9:16 video (~30 s) per item:

* the item's own photos (store photos are allowed -- owner 2026-11-20), moving slowly scene by scene;
* a Telugu (or Hindi / English) script written by the model ONLY from the item record and the review summary;
* the voice: ElevenLabs when configured, else Sarvam, else no voice (captions only) -- never a fake;
* a presenter from the ASKODOX AI model library (``assets/presenters``) in a circle that pulses with the voice and
  carries the label "AI ప్రజెంటర్", or the product itself talking (eyes + mouth) for household things;
* a rating card and a "what buyers said" card only when real review screenshots were read;
* the end card "<store> లో చూడండి -- లింక్ కింద ఉంది".

Truth rules (the script prompt and ``clean_script`` both enforce them): no first-person use claims by an AI person
("నేను వాడాను"), no fact that is not in the item / reviews, reviews summarised and attributed to buyers, never a
reviewer's name, a low share of bad ratings is said honestly. Children never speak: a child's product is presented by
an adult presenter. Nothing is published here -- the caller stores the video for staff review.
"""
from __future__ import annotations

import array
import json
import math
import os
import re
import subprocess
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
PRESENTER_DIR = os.path.join(ASSETS, "presenters")
FONT_LATIN = os.path.join(ASSETS, "fonts", "NotoSans-Bold.ttf")
FONT_TELUGU = os.path.join(ASSETS, "fonts", "NotoSansTelugu-Bold.ttf")
W, H, FPS = 720, 1280, 25
AY, AH = 300, 980  # picture area
FACE_BOX = (125, 10, 275, 160)  # the face in every 400x800 presenter photo
NAVY = (20, 27, 77)
VIOLET = (124, 92, 255)
PINK = (244, 51, 151)
MAX_PHOTOS = 6
TIMEOUT_S = 600
SILENT_SECONDS = 24.0  # length of a video with no voice (captions only)
_TELUGU = re.compile(r"[ఀ-౿]")

# The ASKODOX AI model library (owner 2026-11-20). speaks=False: children are shown, never voiced.
PRESENTERS: Dict[str, Dict[str, Any]] = {
    "girl_7": {"file": "01_girl_7.jpg", "gender": "female", "age": 7, "speaks": False},
    "boy_7": {"file": "02_boy_7.jpg", "gender": "male", "age": 7, "speaks": False},
    "teen_girl_15": {"file": "03_teen_girl_15.jpg", "gender": "female", "age": 15, "speaks": False},
    "woman_22": {"file": "05_woman_22.jpg", "gender": "female", "age": 22, "speaks": True},
    "man_22": {"file": "06_man_22.jpg", "gender": "male", "age": 22, "speaks": True},
    "woman_30": {"file": "07_woman_30.jpg", "gender": "female", "age": 30, "speaks": True},
    "man_30": {"file": "08_man_30.jpg", "gender": "male", "age": 30, "speaks": True},
    "woman_42": {"file": "09_woman_42.jpg", "gender": "female", "age": 42, "speaks": True},
    "man_42": {"file": "10_man_42.jpg", "gender": "male", "age": 42, "speaks": True},
    "woman_55": {"file": "11_woman_55.jpg", "gender": "female", "age": 55, "speaks": True},
    "man_55": {"file": "12_man_55.jpg", "gender": "male", "age": 55, "speaks": True},
}
DEFAULT_PRESENTER = "woman_30"
LANGUAGES = {"te": "Telugu", "hi": "Hindi", "en": "English"}
FIRST_PERSON_USE = re.compile(r"(నేను\s*(వాడ|ఉపయోగి|కొన్న|వేసుకు|ట్రై)|मैंने\s*(इस्तेमाल|खरीद|पहन)|\bI\s+(used|bought|wore|tried)\b)",
                              re.IGNORECASE)

REVIEW_PROMPT = (
    "You read screenshots of ONE product's ratings and reviews in a shopping app (Meesho, Amazon, Flipkart ...; any "
    "language). Return ONLY JSON: {\"rating\": number or null, \"ratings_count\": integer or null, \"reviews_count\": "
    "integer or null, \"stars\": {\"5\": int, \"4\": int, \"3\": int, \"2\": int, \"1\": int} or null, \"good\": [string], "
    "\"bad\": [string]}. stars = the count per star level as shown (Very Good = 5 ... Very Bad = 1). good / bad = at most "
    "4 short English points each that several visible reviews actually say (e.g. 'colour same as photo', 'size runs "
    "small'); paraphrase, never copy a review, never include a reviewer's name. null / [] when not visible -- NEVER "
    "guess numbers.")


# ------------------------------------------------------------------ reviews --

def _int(value: Any) -> Optional[int]:
    try:
        n = int(float(str(value).replace(",", "").strip()))
    except (TypeError, ValueError):
        return None
    return n if 0 <= n <= 100_000_000 else None


def clean_reviews(payload: Any) -> Dict[str, Any]:
    """The model's review JSON -> only sane, visible numbers and short points (no names, no quotes)."""
    if not isinstance(payload, dict):
        return {}
    out: Dict[str, Any] = {}
    try:
        rating = float(payload.get("rating"))
        if 0 < rating <= 5:
            out["rating"] = round(rating, 1)
    except (TypeError, ValueError):
        pass
    for key in ("ratings_count", "reviews_count"):
        n = _int(payload.get(key))
        if n:
            out[key] = n
    stars = payload.get("stars")
    if isinstance(stars, dict):
        clean = {k: _int(stars.get(k)) for k in ("5", "4", "3", "2", "1")}
        if all(v is not None for v in clean.values()) and sum(clean.values()) > 0:
            out["stars"] = clean
            out.setdefault("ratings_count", sum(clean.values()))
    for key in ("good", "bad"):
        points = payload.get(key)
        if isinstance(points, list):
            kept = [re.sub(r"\s+", " ", str(p)).strip()[:80] for p in points if isinstance(p, str) and p.strip()]
            if kept:
                out[key] = kept[:4]
    return out


def read_reviews(image_service: Any, images: Sequence[Tuple[bytes, str]]) -> Dict[str, Any]:
    """Review screenshots -> {"reviews": {...}, "read": bool}. Never raises for a provider failure."""
    photos = [(d, m) for d, m in list(images)[:4] if d]
    if not photos or image_service is None or not hasattr(image_service, "analyze_with_prompt"):
        return {"reviews": {}, "read": False}
    try:
        payload, _calls = image_service.analyze_with_prompt(photos, REVIEW_PROMPT, max_models=2,
                                                            allow_second_provider=True)
    except Exception:
        return {"reviews": {}, "read": False}
    reviews = clean_reviews(payload)
    return {"reviews": reviews, "read": bool(reviews.get("rating") or reviews.get("good") or reviews.get("bad"))}


def low_share(reviews: Dict[str, Any]) -> Tuple[int, int]:
    """(1-2 star ratings, all ratings) when the star counts are known, else (0, 0)."""
    stars = reviews.get("stars") or {}
    if not stars:
        return 0, 0
    return int(stars.get("1", 0)) + int(stars.get("2", 0)), sum(int(v) for v in stars.values())


# ------------------------------------------------------------------- script --

def _facts(item: Dict[str, Any]) -> Dict[str, Any]:
    keep = ("title", "brand", "category", "description", "price", "mrp", "seller", "variants")
    out = {k: item.get(k) for k in keep if item.get(k) not in (None, "", [])}
    if isinstance(out.get("description"), str):
        out["description"] = out["description"][:900]
    return out


def script_prompt(item: Dict[str, Any], reviews: Dict[str, Any], store: str, language: str) -> str:
    lang = LANGUAGES.get(language, "Telugu")
    people = ", ".join(f"{k} ({v['gender']}, {v['age']})" for k, v in PRESENTERS.items() if v["speaks"])
    bad, total = low_share(reviews)
    return (
        f"Write the voice-over for a 25-30 second vertical shopping video in {lang} (simple spoken {lang}; English "
        "product words like cotton, size, quality may stay in English). Return ONLY JSON: {\"style\": \"presenter\" or "
        "\"product_talks\", \"presenter\": one id, \"lines\": [{\"caption\": string, \"spoken\": string, \"scene\": "
        "\"photo\" or \"rating\" or \"reviews\" or \"end\"}], \"points\": {\"good\": [string], \"bad\": "
        f"[string]}}}}. points = the REVIEWS good / bad points translated into short {lang} (max 6 words each; [] when "
        "no reviews).\n"
        f"Presenters (pick the one the buyer of this product would trust; a child's product -> an adult parent "
        f"presenter): {people}. style product_talks = the product itself speaks in first person (only for household / "
        "kitchen / cleaning / gadget things); otherwise presenter.\n"
        "Lines: 6-7 short lines, about 70-85 words in total. 1) a warm hello from ASKODOX, 2) a hook question, 3-4) "
        "what it is: ONLY facts from PRODUCT below (colour, material, design, use), 5-6) ratings + what buyers said "
        "ONLY from REVIEWS below (attribute to buyers: 'buyers said ...'; mention the unhappy share honestly when "
        "given; never a reviewer's name), last) where to buy: the link is below the video"
        + (" and the price" if item.get("price") else "") + ".\n"
        "caption = what is shown on screen (digits allowed, max 90 characters); spoken = the same line written for "
        f"the voice (numbers in {lang} words). Rules: a presenter NEVER says they used / bought / wore it; no claim "
        "that is not in PRODUCT or REVIEWS (no 'best', 'cheapest', guarantees, health or safety claims); no emojis.\n"
        f"STORE: {store}\nPRODUCT: {json.dumps(_facts(item), ensure_ascii=False)}\n"
        f"REVIEWS: {json.dumps(reviews, ensure_ascii=False) if reviews else 'none -- skip the review lines'}\n"
        + (f"UNHAPPY: {bad} of {total} ratings are 1-2 stars.\n" if total else ""))


def _json_object(text: str) -> Optional[dict]:
    if not text:
        return None
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        value = json.loads(match.group(0))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def clean_script(raw: Any, *, reviews: Dict[str, Any], presenter: str = "auto", style: str = "auto") -> Optional[dict]:
    """Model JSON -> a safe script, or None. Lines that break the truth rules are dropped, review scenes need real
    reviews, the presenter must be a speaking adult from the library."""
    if not isinstance(raw, dict):
        return None
    lines = []
    for line in raw.get("lines") or []:
        if not isinstance(line, dict):
            continue
        caption = re.sub(r"\s+", " ", str(line.get("caption") or "")).strip()[:120]
        spoken = re.sub(r"\s+", " ", str(line.get("spoken") or caption)).strip()[:300]
        scene = str(line.get("scene") or "photo").strip().lower()
        if scene not in ("photo", "rating", "reviews", "end"):
            scene = "photo"
        if scene in ("rating", "reviews") and not reviews:
            continue
        if not caption or FIRST_PERSON_USE.search(spoken) or FIRST_PERSON_USE.search(caption):
            continue
        lines.append({"caption": caption, "spoken": spoken, "scene": scene})
    if len(lines) < 3:
        return None
    if lines[-1]["scene"] != "end":
        lines[-1]["scene"] = "end"
    chosen = presenter if presenter in PRESENTERS else str(raw.get("presenter") or "")
    if chosen not in PRESENTERS or not PRESENTERS[chosen]["speaks"]:
        chosen = DEFAULT_PRESENTER
    chosen_style = style if style in ("presenter", "product_talks") else str(raw.get("style") or "presenter")
    if chosen_style not in ("presenter", "product_talks"):
        chosen_style = "presenter"
    points: Dict[str, List[str]] = {}
    raw_points = raw.get("points") if isinstance(raw.get("points"), dict) else {}
    for key in ("good", "bad"):
        given = raw_points.get(key) if reviews.get(key) else None
        if isinstance(given, list):
            kept = [re.sub(r"\s+", " ", str(p)).strip()[:60] for p in given if isinstance(p, str) and p.strip()]
            if kept:
                points[key] = kept[:4]
    return {"style": chosen_style, "presenter": chosen, "lines": lines[:8], "points": points}


def fallback_script(item: Dict[str, Any], reviews: Dict[str, Any], store: str, price: str) -> dict:
    """No model answer: a short, plain script from the record itself (Telugu)."""
    title = str(item.get("title") or "ఈ product").strip()[:80]
    lines = [{"caption": "నమస్తే! ASKODOX నుంచి.", "spoken": "నమస్తే! ASKODOX నుంచి.", "scene": "photo"},
             {"caption": title, "spoken": f"ఇది {title}.", "scene": "photo"}]
    if reviews.get("rating"):
        n = reviews.get("ratings_count")
        cap = f"{store} లో రేటింగ్ {reviews['rating']} / 5" + (f" ({n} మంది)" if n else "")
        lines.append({"caption": cap, "spoken": cap.replace("/ 5", "").replace("(", "").replace(")", ""),
                      "scene": "rating"})
    if price:
        lines.append({"caption": f"ధర {price}", "spoken": f"ధర {price}", "scene": "photo"})
    lines.append({"caption": "లింక్ కిందే ఉంది. ఇప్పుడే చూడండి!", "spoken": "లింక్ కిందే ఉంది. ఇప్పుడే చూడండి!",
                  "scene": "end"})
    return {"style": "presenter", "presenter": DEFAULT_PRESENTER, "lines": lines}


def write_script(write: Optional[Callable[[str], str]], item: Dict[str, Any], reviews: Dict[str, Any], store: str,
                 price: str, *, language: str = "te", presenter: str = "auto", style: str = "auto") -> dict:
    script = None
    if write is not None:
        try:
            script = clean_script(_json_object(write(script_prompt(item, reviews, store, language))),
                                  reviews=reviews, presenter=presenter, style=style)
        except Exception:
            script = None
    if script is None:
        script = fallback_script(item, reviews, store, price)
        if presenter in PRESENTERS and PRESENTERS[presenter]["speaks"]:
            script["presenter"] = presenter
        if style in ("presenter", "product_talks"):
            script["style"] = style
        script["fallback"] = True
    return script


# -------------------------------------------------------------------- voice --

def synthesize(container: Any, text: str, gender: str) -> Tuple[Optional[bytes], str]:
    """(audio bytes, path) -- ElevenLabs, then Sarvam; (None, "none") when no voice is available."""
    try:
        from app.services.elevenlabs_tts import ElevenLabsTTS

        eleven = ElevenLabsTTS(timeout_seconds=90.0)
        if eleven.configured:
            spoken = eleven.synthesize(text, voice=gender)
            if spoken.get("success") and spoken.get("content"):
                return bytes(spoken["content"]), "elevenlabs"
    except Exception:
        pass
    synth = getattr(getattr(container, "voice_assistant_service", None), "synthesize", None)
    if callable(synth):
        try:
            try:
                result = synth(text, voice=gender) or {}
            except TypeError:
                result = synth(text) or {}
            if result.get("success") and result.get("content"):
                return bytes(result["content"]), str(result.get("tts_path") or "sarvam")
        except Exception:
            pass
    return None, "none"


# ------------------------------------------------------------------- render --

def _font(text: str, size: int):
    from PIL import ImageFont

    path = FONT_TELUGU if _TELUGU.search(text or "") else FONT_LATIN
    try:
        return ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)
    except Exception:
        return ImageFont.truetype(path, size)


def _wrap(draw: Any, text: str, font: Any, width: int) -> List[str]:
    words, out, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out[:3]


def _cover(img: Any, w: int, h: int) -> Any:
    from PIL import Image

    k = max(w / img.width, h / img.height)
    big = img.resize((max(w, int(img.width * k + 0.5)), max(h, int(img.height * k + 0.5))), Image.BILINEAR)
    x, y = (big.width - w) // 2, (big.height - h) // 2
    return big.crop((x, y, x + w, y + h))


def _pad(img: Any) -> Any:
    """A photo on a canvas of the picture area's shape (white sides) so every crop box stays inside."""
    from PIL import Image

    aspect = W / AH
    if img.width / img.height > aspect:
        cw, ch = img.width, int(img.width / aspect)
    else:
        cw, ch = int(img.height * aspect), img.height
    canvas = Image.new("RGB", (cw, ch), (255, 255, 255))
    canvas.paste(img, ((cw - img.width) // 2, (ch - img.height) // 2))
    return canvas


def _ease(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def envelope(exe: str, audio: str, frames_hint: int = 0) -> List[float]:
    """Loudness per video frame (0..~1.2) from the audio (pure Python, no numpy)."""
    raw = subprocess.run([exe, "-v", "error", "-i", audio, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
                         capture_output=True, timeout=120).stdout
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) // 2 * 2])
    hop = 16000 // FPS
    rms = []
    for i in range(len(samples) // hop):
        chunk = samples[i * hop:(i + 1) * hop]
        rms.append(math.sqrt(sum(s * s for s in chunk) / len(chunk)) / 32768)
    if not rms:
        return [0.0] * frames_hint
    top = sorted(rms)[int(len(rms) * 0.95)] or 1e-6
    smooth = [(rms[i] + rms[max(0, i - 1)]) / 2 / top for i in range(len(rms))]
    return [min(v, 1.2) for v in smooth]


def cut_points(env: List[float], spoken: List[str]) -> List[int]:
    """Frame where each line starts: text-length share of the speech, moved to the nearest pause (<= 1.8 s away)."""
    n = len(env)
    if n == 0:
        return [0] * (len(spoken) + 1)
    quiet = [v < 0.08 for v in env]
    pauses, i = [], 0
    while i < n:
        if quiet[i]:
            j = i
            while j < n and quiet[j]:
                j += 1
            if j - i >= 3 and i > 0 and j < n:
                pauses.append((i + j) // 2)
            i = j
        else:
            i += 1
    loud = [k for k in range(n) if not quiet[k]] or [0, n - 1]
    a, b = loud[0], loud[-1]
    weights = [max(1, len(s.replace(" ", ""))) for s in spoken]
    total, acc, cuts = sum(weights), 0, []
    for w in weights[:-1]:
        acc += w
        want = a + (b - a) * acc / total
        near = min(pauses, key=lambda m: abs(m - want)) if pauses else int(want)
        cut = near if abs(near - want) <= FPS * 1.8 else int(want)
        cuts.append(max(cut, (cuts[-1] + FPS // 2) if cuts else FPS // 2))
    return [0] + cuts + [n]


class Painter:
    """Draws every frame (PIL)."""

    def __init__(self, photos: List[Any], script: dict, reviews: Dict[str, Any], store: str, price: str) -> None:
        from PIL import Image, ImageDraw, ImageFilter

        self.Image, self.ImageDraw = Image, ImageDraw
        self.photos = [_pad(p.convert("RGB")) for p in photos[:MAX_PHOTOS]]
        self.script, self.reviews, self.store, self.price = script, reviews, store, price
        self.blur = _cover(photos[0].convert("RGB"), W, AH).filter(ImageFilter.GaussianBlur(14)).point(
            lambda v: int(v * 0.55 + 110))
        self.style = script.get("style") or "presenter"
        meta = PRESENTERS.get(script.get("presenter") or "", PRESENTERS[DEFAULT_PRESENTER])
        if self.style == "presenter":
            face = Image.open(os.path.join(PRESENTER_DIR, meta["file"])).convert("RGB").crop(FACE_BOX)
        else:
            src = photos[0].convert("RGB")
            side = min(src.width, src.height)
            face = src.crop(((src.width - side) // 2, (src.height - side) // 2,
                             (src.width + side) // 2, (src.height + side) // 2))
        self.face = face.resize((210, 210), Image.LANCZOS)
        self.mask = Image.new("L", (210, 210), 0)
        ImageDraw.Draw(self.mask).ellipse([0, 0, 209, 209], fill=255)
        self.photo_scenes = [i for i, l in enumerate(script["lines"]) if l["scene"] == "photo"]

    # -- scenes
    def _shot(self, k: int, zoom_from: float, zoom_to: float, u: float, drift: Tuple[float, float]) -> Any:
        img = self.photos[k % len(self.photos)]
        z = zoom_from + (zoom_to - zoom_from) * _ease(u)
        bw, bh = img.width / z, img.height / z
        cx = img.width / 2 + drift[0] * img.width * (1 - 1 / z) * (u - 0.5)
        cy = img.height / 2 + drift[1] * img.height * (1 - 1 / z) * (u - 0.5)
        box = (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)
        return img.crop(tuple(int(v) for v in box)).resize((W, AH), self.Image.BILINEAR)

    def _rating(self, u: float) -> Any:
        img = self.blur.copy()
        d = self.ImageDraw.Draw(img, "RGBA")
        r = self.reviews
        d.rounded_rectangle([50, 70, W - 50, 630], radius=36, fill=(255, 255, 255, 240))
        d.text((90, 105), f"{self.store} రేటింగ్", font=_font("రే", 38), fill=NAVY)
        if r.get("rating"):
            d.text((90, 170), f"{r['rating']}", font=_font("1", 120), fill=(56, 158, 92))
        if r.get("ratings_count"):
            d.text((290, 200), f"{r['ratings_count']} రేటింగ్స్", font=_font("రే", 34), fill=(90, 98, 120))
        if r.get("reviews_count"):
            d.text((290, 250), f"{r['reviews_count']} రివ్యూలు", font=_font("రి", 34), fill=(90, 98, 120))
        stars = r.get("stars")
        if stars:
            top = max(stars.values()) or 1
            rows = [("5 ★", "5", (56, 140, 90)), ("4 ★", "4", (90, 190, 120)), ("3 ★", "3", (240, 190, 60)),
                    ("2 ★", "2", (240, 130, 60)), ("1 ★", "1", (220, 60, 50))]
            grow = _ease(u * 2.5)
            for k, (lab, key, col) in enumerate(rows):
                y = 350 + k * 54
                d.text((90, y - 6), lab.replace(" ★", ""), font=_font("1", 30), fill=NAVY)
                d.ellipse([118, y + 2, 136, y + 20], fill=col)
                d.rounded_rectangle([170, y + 6, W - 150, y + 26], radius=10, fill=(230, 233, 240))
                d.rounded_rectangle([170, y + 6, 170 + (W - 320) * stars[key] / top * grow, y + 26], radius=10, fill=col)
                d.text((W - 135, y - 4), str(stars[key]), font=_font("1", 28), fill=NAVY)
        return img

    def _review_list(self, u: float) -> Any:
        img = self.blur.copy()
        d = self.ImageDraw.Draw(img, "RGBA")
        d.rounded_rectangle([50, 50, W - 50, 640], radius=36, fill=(255, 255, 255, 242))
        d.text((90, 80), "కొన్నవాళ్లు ఏమన్నారు", font=_font("కొ", 38), fill=NAVY)
        said = self.script.get("points") or {}
        good = said.get("good") or self.reviews.get("good", [])
        bad_points = said.get("bad") or self.reviews.get("bad", [])
        items = [(p, True) for p in good[:3]] + [(p, False) for p in bad_points[:2]]
        bad, total = low_share(self.reviews)
        if total and bad:
            items.append((f"{total} లో {bad} మందికి నచ్చలేదు", False))
        for k, (txt, good) in enumerate(items[:5]):
            if u < 0.06 + 0.12 * k:
                continue
            y = 160 + k * 86
            col = (56, 158, 92) if good else (230, 140, 40)
            d.ellipse([90, y + 4, 136, y + 50], fill=col)
            if good:
                d.line([101, y + 27, 111, y + 38, 127, y + 16], fill=(255, 255, 255), width=6)
            else:
                d.text((107, y + 2), "!", font=_font("!", 34), fill=(255, 255, 255))
            font = _font(txt, 30)
            line = _wrap(d, txt, font, W - 260)[0]
            d.text((160, y + 6), line, font=font, fill=NAVY)
        d.text((90, 598), f"{self.store} లో ఉన్న నిజమైన రివ్యూల సారాంశం", font=_font("లో", 22), fill=(120, 126, 140))
        return img

    def scene(self, s: int, u: float) -> Any:
        kind = self.script["lines"][s]["scene"]
        if kind == "rating":
            return self._rating(u)
        if kind == "reviews":
            return self._review_list(u)
        if kind == "end":
            return self._shot(len(self.photos) - 1 if len(self.photos) > 1 else 0, 1.0, 1.12, u, (0, 0.2))
        order = self.photo_scenes.index(s) if s in self.photo_scenes else s
        drift = [(0, -0.4), (0.3, 0.3), (-0.3, 0.2), (0, 0.5), (0.2, -0.2), (-0.2, 0.4)][order % 6]
        zoom = [(1.0, 1.15), (1.25, 1.7), (1.6, 2.1), (1.3, 1.8), (1.1, 1.5), (1.2, 1.6)][order % 6]
        return self._shot(order, zoom[0], zoom[1], u, drift)

    # -- overlay
    def _badge(self, img: Any, text: str, x: int, y: int, size: int, fill=(255, 255, 255), bg=(20, 27, 77, 230)) -> None:
        d = self.ImageDraw.Draw(img, "RGBA")
        f = _font(text, size)
        w = d.textlength(text, font=f)
        d.rounded_rectangle([x, y, x + w + 28, y + size + 22], radius=(size + 22) // 2, fill=bg)
        d.text((x + 14, y + 6), text, font=f, fill=fill)

    def frame(self, s: int, u: float, prev: Optional[Tuple[int, float]], a: float, t: float) -> Any:
        pic = self.scene(s, u)
        if prev is not None:
            pic = self.Image.blend(self.scene(prev[0], 1.0), pic, prev[1])
        img = self.Image.new("RGB", (W, H), NAVY)
        img.paste(pic, (0, AY))
        self._badge(img, "ASKODOX Picks", 30, 40, 26)
        self._badge(img, f"{self.store} లో ఉంది", W - 270, 40, 26, fill=NAVY, bg=(255, 255, 255, 235))
        d = self.ImageDraw.Draw(img, "RGBA")
        cap = self.script["lines"][s]["caption"]
        size = 36 if len(cap) < 70 else 32
        f = _font(cap, size)
        lines = _wrap(d, cap, f, W - 80)
        top = 110
        d.rounded_rectangle([20, top - 8, W - 20, top + len(lines) * (size + 14) + 12], radius=20,
                            fill=(255, 255, 255, 30))
        for k, line in enumerate(lines):
            lw = d.textlength(line, font=f)
            d.text(((W - lw) / 2, top + k * (size + 14)), line, font=f, fill=(255, 255, 255))
        # presenter / talking product, pulsing with the voice
        cx, cy = 145, H - 190
        r = 118 + int(16 * a)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*VIOLET, 120))
        d.ellipse([cx - 110, cy - 110, cx + 110, cy + 110], fill=(255, 255, 255))
        img.paste(self.face, (cx - 105, cy - 105), self.mask)
        if self.style == "product_talks":
            self._eyes(d, cx, cy, a, t)
            self._badge(img, "ASKODOX", cx - 64, cy + 112, 20, bg=(*VIOLET, 240))
        else:
            self._badge(img, "AI ప్రజెంటర్", cx - 82, cy + 112, 20, bg=(*VIOLET, 240))
        if self.script["lines"][s]["scene"] == "end":
            pulse = 1 + 0.04 * math.sin(t * 6)
            text = f"{self.store} లో చూడండి"
            f2 = _font(text, int(40 * pulse))
            w = d.textlength(text, font=f2)
            x0, y0 = (W - w) / 2 - 36, 900
            d.rounded_rectangle([x0, y0, x0 + w + 72, y0 + 84], radius=42, fill=PINK)
            d.text((x0 + 36, y0 + 14), text, font=f2, fill=(255, 255, 255))
            sub = "లింక్ కింద ఉంది" + (f" · {self.price}" if self.price else "")
            self._badge(img, sub, int((W - d.textlength(sub, font=_font(sub, 26))) / 2) - 14, 1000, 26,
                        fill=NAVY, bg=(255, 255, 255, 240))
        return img

    def _eyes(self, d: Any, cx: int, cy: int, a: float, t: float) -> None:
        blink = (t % 3.3) < 0.12
        for ex in (cx - 32, cx + 32):
            ey = cy - 20
            d.ellipse([ex - 18, ey - 20, ex + 18, ey + 20], fill=(255, 255, 255), outline=NAVY, width=3)
            if blink:
                d.line([ex - 15, ey, ex + 15, ey], fill=NAVY, width=4)
            else:
                look = 4 * math.sin(t * 0.9)
                d.ellipse([ex - 9 + look, ey - 9, ex + 9 + look, ey + 9], fill=(20, 25, 40))
        mw, mh = 18 + 6 * a, 3 + 22 * a
        d.rounded_rectangle([cx - mw, cy + 40 - mh / 2, cx + mw, cy + 40 + mh / 2], radius=int(min(mw, mh / 2 + 1)),
                            fill=(120, 20, 35), outline=NAVY, width=3)


def render(photos: List[Any], script: dict, reviews: Dict[str, Any], store: str, price: str, audio: Optional[str],
           out: str, *, exe: str, seconds_without_voice: Optional[float] = None) -> Dict[str, Any]:
    """Write the MP4. Returns {"ok": True, "seconds": n} or {"ok": False, "reason": ...}."""
    if not photos:
        return {"ok": False, "reason": "no_photos"}
    lines = script["lines"]
    if audio:
        env = envelope(exe, audio)
    else:
        env = [0.0] * int((seconds_without_voice or SILENT_SECONDS) * FPS)
    if not audio:
        weights = [max(1, len(l["caption"])) for l in lines]
        total = sum(weights)
        bounds, acc = [0], 0
        for w in weights[:-1]:
            acc += w
            bounds.append(int(len(env) * acc / total))
        bounds.append(len(env))
    else:
        bounds = cut_points(env, [l["spoken"] for l in lines])
    painter = Painter(photos, script, reviews, store, price)
    total_frames = len(env) + FPS  # one quiet second at the end
    tmp = out + ".part.mp4"
    args = [exe, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
            "-r", str(FPS), "-i", "-"]
    if audio:
        args += ["-i", audio, "-af", "apad=pad_dur=1.2"]
    else:
        args += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
    args += ["-t", f"{total_frames / FPS:.2f}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", tmp]
    xf = int(0.3 * FPS)
    try:
        proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for fi in range(total_frames):
            s = next((k for k in range(len(lines)) if bounds[k] <= fi < bounds[k + 1]), len(lines) - 1)
            span = max(1, bounds[s + 1] - bounds[s]) if s + 1 < len(bounds) else FPS
            u = min((fi - bounds[s]) / span, 1.0)
            prev = (s - 1, (fi - bounds[s]) / xf) if s > 0 and fi - bounds[s] < xf else None
            a = env[fi] if fi < len(env) else 0.0
            proc.stdin.write(painter.frame(s, u, prev, a, fi / FPS).tobytes())
        proc.stdin.close()
        code = proc.wait(timeout=TIMEOUT_S)
        if code != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
            return {"ok": False, "reason": "ffmpeg_error"}
        os.replace(tmp, out)
        return {"ok": True, "seconds": round(total_frames / FPS, 1)}
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": "timeout"}
    except Exception as error:
        return {"ok": False, "reason": f"error:{type(error).__name__}"}
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def store_name(url: str) -> str:
    host = re.sub(r"^https?://(www\.)?", "", str(url or "")).split("/")[0].lower()
    for key, name in (("meesho", "Meesho"), ("amazon", "Amazon"), ("amzn", "Amazon"), ("flipkart", "Flipkart"),
                      ("fkrt", "Flipkart"), ("ajio", "AJIO"), ("myntra", "Myntra"), ("nykaa", "Nykaa")):
        if key in host:
            return name
    return "ASKODOX"
