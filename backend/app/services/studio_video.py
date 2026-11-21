"""ASKODOX Studio round 2 (owner 2026-11-21): shoot tips -> staff phone video -> ASKODOX auto edit -> publish
checklist -> captions per platform.

* Shoot tips come from ONE table keyed by the product kind (clothes, jewellery, footwear ...) -- data, not per-product
  code. Meesho rule shown every time: the real product must be seen in OUR OWN video.
* The edit keeps the staff video as the main picture (Meesho pays only for own videos): ASKODOX on top, the price +
  pack tag ("PAIR ₹249" / "₹249 EACH" / "COMBO ₹499"), an optional presenter circle (our own models, female / male),
  the voice, and an end card "More on the ASKODOX app". Picture text is Latin only (owner rule: Facebook / Instagram
  auto-dubbing) -- the Telugu is in the voice.
* Voice: fixed lines (intro / outro) are recorded once per voice and language; product lines are new. Every line is
  cached by its exact text, so the same line is never paid for twice (a price change re-records only the price line).
* Store rules live in ``STORE_RULES`` (rows, Meesho first; other stores get rows later). Publish stops and names
  what is missing.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import os
import re
import subprocess
from typing import Any, Dict, List, Optional, Tuple

W, H, FPS = 720, 1280, 30
END_SECONDS = 2.5
MAX_SECONDS = 61.0
ASSETS = os.path.join(os.path.dirname(os.path.dirname(__file__)), "assets")
PRESENTERS = {"female": "07_woman_30.jpg", "male": "08_man_30.jpg"}

# ----------------------------------------------------------------- shoot tips --
KINDS: List[Tuple[str, Tuple[str, ...]]] = [
    ("jewellery", ("anklet", "payal", "ring", "earring", "necklace", "chain", "bangle", "bracelet", "jewel", "pattilu",
                   "పట్టీ", "గాజు", "కమ్మ", "నెక్లెస్", "jhumka", "mangalsutra")),
    ("footwear", ("shoe", "sandal", "slipper", "chappal", "heels", "footwear", "sneaker", "చెప్పు")),
    ("beauty", ("lipstick", "cream", "serum", "face", "makeup", "kajal", "nail", "shampoo", "oil", "perfume", "beauty")),
    ("kitchen", ("kitchen", "pan", "kadai", "cooker", "bottle", "glass", "plate", "container", "knife", "tawa", "bowl",
                 "spoon", "jar")),
    ("home", ("bedsheet", "curtain", "cushion", "mat", "decor", "lamp", "towel", "organizer", "holder", "rack",
              "frame", "pillow")),
    ("gadgets", ("earbud", "earphone", "charger", "cable", "speaker", "watch", "mobile", "phone", "led", "light",
                 "gadget", "power bank", "trimmer")),
    ("bags", ("bag", "purse", "wallet", "backpack", "handbag", "pouch")),
    ("kids", ("kids", "baby", "toy", "boys", "girls", "infant")),
    ("clothes", ("saree", "blouse", "kurti", "kurta", "dress", "shirt", "t-shirt", "top", "jeans", "pant", "legging",
                 "nighty", "lehenga", "dupatta", "panty", "bra", "innerwear", "suit", "jacket", "hoodie", "చీర", "బ్లౌజ్")),
]
TIPS: Dict[str, List[str]] = {
    "clothes": ["వేసుకుని చూపించండి: ముందు, వెనక, పక్కకి తిరిగి", "Fabric ని దగ్గరగా (close-up) చూపించండి",
                "Size label / tag కెమెరాకి చూపించండి", "కిటికీ వెలుతురులో షూట్ చేయండి, ఫ్లాష్ వద్దు"],
    "jewellery": ["చేతికి / కాలికి పెట్టుకుని నెమ్మదిగా తిప్పండి", "తెల్ల / నల్ల బ్యాక్‌గ్రౌండ్ మీద మెరుపు చూపించండి",
                  "జత అయితే రెండూ కలిపి చూపించండి", "Size / పొడవు రూలర్ పక్కన పెట్టి చూపించండి"],
    "footwear": ["కాళ్లకు వేసుకుని నడిచి చూపించండి", "Sole (అడుగు భాగం) దగ్గరగా చూపించండి",
                 "Size నంబర్ కెమెరాకి చూపించండి", "రెండు చెప్పులూ పక్కపక్కన పెట్టి చూపించండి"],
    "beauty": ["వాడే ముందు / వాడిన తర్వాత చూపించండి (నిజమైనదే)", "Pack మీద పేరు, expiry తేదీ చూపించండి",
               "చేతి మీద రాసి texture / రంగు చూపించండి", "మందుల్లాంటి హామీలు చెప్పకండి"],
    "kitchen": ["వాడుతూ చూపించండి (నీళ్లు పోయడం, వండడం)", "Size కోసం చేతిలో పట్టుకుని చూపించండి",
                "Pack లో ఎన్ని వచ్చాయో అన్నీ వరుసగా పెట్టి చూపించండి", "Material / మూత దగ్గరగా చూపించండి"],
    "home": ["ఇంట్లో అసలు చోటులో పెట్టి చూపించండి", "ముందు / తర్వాత గది చూపించండి", "Size కోసం చేతితో పోల్చండి",
             "రంగు నిజంగా కనిపించేలా పగటి వెలుతురులో షూట్ చేయండి"],
    "gadgets": ["Box తెరిచి లోపల ఉన్నవన్నీ చూపించండి", "ఆన్ చేసి పనిచేస్తూ చూపించండి", "Ports / బటన్లు దగ్గరగా చూపించండి",
                "బ్యాటరీ / సౌండ్ లాంటి హామీలు మీరు చూసినవి మాత్రమే"],
    "bags": ["లోపల అరలు తెరిచి చూపించండి", "భుజానికి / చేతికి వేసుకుని చూపించండి", "Zip / హ్యాండిల్ దగ్గరగా",
             "Size కోసం phone / bottle లోపల పెట్టి చూపించండి"],
    "kids": ["పిల్లల ముఖం చూపించకండి -- చేతులు / బొమ్మ మాత్రమే", "Pack లో ఉన్నవన్నీ చూపించండి", "Age label చూపించండి",
             "చిన్న ముక్కలు ఉంటే జాగ్రత్త చెప్పండి"],
    "other": ["ప్రోడక్ట్‌ని అన్ని వైపుల నుంచి చూపించండి", "వాడుతూ చూపించండి", "Pack / label దగ్గరగా చూపించండి",
              "పగటి వెలుతురులో, నిలువుగా షూట్ చేయండి"],
}
COMMON_TIPS = ["ఫోన్ నిలువుగా పట్టుకోండి, 15-60 సెకన్లు", "మొదటి 2 సెకన్లలోనే ప్రోడక్ట్ కనిపించాలి",
               "మీ సొంత వీడియోలో నిజమైన ప్రోడక్ట్ కనిపించాలి -- Meesho నియమం (store ఫోటోలు మాత్రమే అయితే payout రాదు)"]


def product_kind(title: str, category: str = "") -> str:
    text = f" {title} {category} ".lower()
    for kind, words in KINDS:
        if any(w in text for w in words):
            return kind
    return "other"


def shoot_tips(row: Dict[str, Any]) -> Dict[str, Any]:
    kind = product_kind(str(row.get("title") or ""))
    return {"kind": kind, "tips": TIPS[kind], "common": COMMON_TIPS}


# --------------------------------------------------------------- store rules --
# Each rule: id, label (te), how it is checked: "auto" (from the record) or "tick" (staff confirms; "price" = today).
STORE_RULES: Dict[str, List[Dict[str, str]]] = {
    "Meesho": [
        {"id": "own_video", "label": "సొంత వీడియో (మనం షూట్ చేసింది)", "check": "auto"},
        {"id": "same_product", "label": "చూపిన ప్రోడక్ట్ = లింక్ ప్రోడక్ట్ (రంగు మాత్రమే మారొచ్చు)", "check": "tick"},
        {"id": "price_today", "label": "ఈరోజు Meesho యాప్‌లో ధర చెక్ చేశాను", "check": "price"},
        {"id": "pack_words", "label": "Combo / ఒక్కోటి ధర మాట వీడియోలో ఉంది", "check": "auto"},
        {"id": "meeshoapp_tag", "label": "Caption లో @meeshoapp", "check": "auto"},
        {"id": "affiliate_tag", "label": "Caption లో #Affiliate", "check": "auto"},
        {"id": "affiliate_link", "label": "Affiliate లింక్ పెట్టాం", "check": "auto"},
    ],
}
DEFAULT_RULES = [
    {"id": "own_video", "label": "సొంత వీడియో (మనం షూట్ చేసింది)", "check": "auto"},
    {"id": "price_today", "label": "ఈరోజు store యాప్‌లో ధర చెక్ చేశాను", "check": "price"},
    {"id": "affiliate_tag", "label": "Caption లో #Affiliate", "check": "auto"},
    {"id": "affiliate_link", "label": "Affiliate లింక్ పెట్టాం", "check": "auto"},
]


def rules_for(store: str) -> List[Dict[str, str]]:
    return STORE_RULES.get(store, DEFAULT_RULES)


def checklist(row: Dict[str, Any], today: str) -> Dict[str, Any]:
    checks = row.get("checks") or {}
    auto = {
        "own_video": bool(row.get("video_file")),
        "pack_words": bool(price_tag(row)) and row.get("edit_status") == "READY",
        "meeshoapp_tag": True, "affiliate_tag": True,  # our captions always carry them
        "affiliate_link": bool(row.get("affiliate_link")),
    }
    items = []
    for rule in rules_for(str(row.get("store") or "")):
        if rule["check"] == "auto":
            ok = auto.get(rule["id"], False)
        elif rule["check"] == "price":
            ok = bool(row.get("show_price_paise")) and checks.get("price_checked_on") == today
        else:
            ok = bool(checks.get(rule["id"]))
        items.append({**rule, "ok": ok})
    if row.get("edit_status") != "READY":
        items.append({"id": "edited", "label": "ASKODOX ఎడిట్ పూర్తి (ధర మారితే మళ్లీ)", "check": "auto", "ok": False})
    missing = [i for i in items if not i["ok"]]
    return {"items": items, "missing": [i["label"] for i in missing], "ready": not missing}


# ------------------------------------------------------------- script + tags --
def money(paise: int) -> str:
    rupees = paise / 100
    return f"₹{rupees:,.0f}" if rupees == int(rupees) else f"₹{rupees:,.2f}"


def price_tag(row: Dict[str, Any]) -> str:
    """Picture tag: Latin + ₹ only."""
    paise = int(row.get("show_price_paise") or 0)
    if not paise:
        return ""
    pack, count = row.get("pack"), int(row.get("pack_count") or 1)
    if pack == "pair":
        return f"PAIR {money(paise)}"
    if pack == "combo":
        return f"COMBO OF {count} {money(paise)}" if count > 1 else f"COMBO {money(paise)}"
    return f"{money(paise)} EACH" if count > 1 else money(paise)


FIXED = {
    "te": {"intro": "ASKODOX లో ఈరోజు ఈ ప్రోడక్ట్ చూడండి.", "outro": "లింక్ కింద ఉంది. ASKODOX యాప్‌లో ఇంకా చూడండి."},
    "hi": {"intro": "ASKODOX पर आज यह प्रोडक्ट देखिए.", "outro": "लिंक नीचे है. ASKODOX ऐप में और देखिए."},
    "en": {"intro": "Check out this product on ASKODOX today.", "outro": "The link is below. See more on the ASKODOX app."},
}


def product_line(row: Dict[str, Any], language: str) -> str:
    """The price + pack sentence (owner: "జత కలిపి ₹X" / "ఒక్కోటి ₹X")."""
    paise = int(row.get("show_price_paise") or 0)
    if not paise:
        return ""
    p, pack = money(paise), row.get("pack")
    words = {
        "te": {"pair": f"జత కలిపి {p} మాత్రమే.", "combo": f"Combo మొత్తం కలిపి {p}.", "single": f"ధర {p} మాత్రమే."},
        "hi": {"pair": f"जोड़ी सिर्फ़ {p} में.", "combo": f"पूरा combo {p} में.", "single": f"कीमत सिर्फ़ {p}."},
        "en": {"pair": f"Just {p} for the pair.", "combo": f"The whole combo for {p}.", "single": f"Just {p}."},
    }[language if language in FIXED else "te"]
    if pack == "single" and int(row.get("pack_count") or 1) > 1:
        return {"te": f"ఒక్కోటి {p}.", "hi": f"हर एक {p}.", "en": f"{p} each."}[language if language in FIXED else "te"]
    return words.get(str(pack), words["single"])


def script(row: Dict[str, Any], options: Dict[str, Any]) -> List[Dict[str, str]]:
    """Lines in order: fixed intro, staff's own line (optional, editable), price line, fixed outro."""
    lang = options.get("language") if options.get("language") in FIXED else "te"
    lines = [{"kind": "fixed", "text": FIXED[lang]["intro"]}]
    own = re.sub(r"\s+", " ", str(options.get("line") or "")).strip()[:200]
    if own:
        lines.append({"kind": "own", "text": own})
    price = product_line(row, lang)
    if price:
        lines.append({"kind": "price", "text": price})
    lines.append({"kind": "fixed", "text": FIXED[lang]["outro"]})
    return lines


def voice_key(text: str, gender: str) -> str:
    return hashlib.sha256(f"{gender}|{text}".encode()).hexdigest()[:40]


def voice_files(container: Any, store: Any, lines: List[Dict[str, str]], gender: str, folder: str) -> Tuple[List[str], Dict[str, int]]:
    """One audio file per line, from the cache when that exact line was recorded before (never paid twice)."""
    from app.services import product_video as pv

    paths, stats = [], {"cached": 0, "new": 0, "failed": 0}
    for line in lines:
        key = voice_key(line["text"], gender)
        hit = store.voice_cached(key)
        if hit and os.path.exists(hit["path"]):
            paths.append(hit["path"])
            stats["cached"] += 1
            continue
        audio, provider = pv.synthesize(container, line["text"], gender)
        if not audio:
            stats["failed"] += 1
            continue
        path = os.path.join(folder, f"studio-voice-{key}.audio")
        with open(path, "wb") as handle:
            handle.write(audio)
        store.voice_store(key, path, provider, line["text"])
        paths.append(path)
        stats["new"] += 1
    return paths, stats


def captions(row: Dict[str, Any]) -> Dict[str, Any]:
    """Studio spec 7: Instagram / Facebook / YouTube with @meeshoapp (Meesho) + #Affiliate + the affiliate link
    (Instagram: comment LINK -- caption links are not clickable); WhatsApp: Meesho Share & Earn link ONLY."""
    title = str(row.get("title") or "")[:90]
    price = money(int(row["show_price_paise"])) if row.get("show_price_paise") else ""
    tag = price_tag(row)
    meesho = str(row.get("store") or "") == "Meesho"
    tags = ("@meeshoapp " if meesho else "") + "#Affiliate #ASKODOX #ASKODOXPicks"
    link = row.get("affiliate_link") or ""
    disclosure = "Affiliate link: మీరు కొంటే మాకు కమీషన్ వస్తుంది, మీకు ధర మారదు."
    head = f"✨ {title}" + (f" -- {tag}" if tag else "")
    fb = "\n".join([head, "", f"👉 కొనండి: {link}" if link else "", "", disclosure, tags]).replace("\n\n\n", "\n\n")
    ig = "\n".join([head, "", "లింక్ కావాలా? కింద \"LINK\" అని comment చేయండి 👇", "", disclosure, tags])
    yt = "\n".join([head, "", f"👉 {link}" if link else "", "", disclosure, tags])
    share = row.get("share_earn_link") or ""
    if meesho:
        wa = f"✨ {title}" + (f" -- {price}" if price else "") + (f"\n👉 {share}" if share else
                                                                   "\n(Meesho Share & Earn లింక్ ఇక్కడ పెట్టండి)")
    else:
        wa = f"✨ {title}" + (f" -- {price}" if price else "") + (f"\n👉 {link}" if link else "")
    return {"instagram": {"text": ig, "dm_link": link}, "facebook": {"text": fb},
            "youtube": {"title": f"{title[:80]} #shorts", "text": yt}, "whatsapp": {"text": wa}}


# ------------------------------------------------------------------- ffmpeg --
def probe(exe: str, src: str) -> Dict[str, Any]:
    """{"seconds", "width", "height", "audio"} read from ffmpeg's banner."""
    try:
        out = subprocess.run([exe, "-hide_banner", "-i", src], capture_output=True, text=True, timeout=30).stderr
    except Exception:
        return {}
    info: Dict[str, Any] = {"audio": "Audio:" in out}
    m = re.search(r"Duration:\s*(\d+):(\d+):([\d.]+)", out)
    if m:
        info["seconds"] = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))
    for line in out.splitlines():
        if "Video:" in line:
            v = re.search(r"\b(\d{2,5})x(\d{2,5})\b", line)
            if v:
                info["width"], info["height"] = int(v.group(1)), int(v.group(2))
            rot = re.search(r"rotate\s*:\s*(-?\d+)", out) or re.search(r"rotation of (-?\d+)", out)
            if rot and abs(int(rot.group(1))) in (90, 270) and "width" in info:
                info["width"], info["height"] = info["height"], info["width"]
            break
    return info


def _overlay_png(row: Dict[str, Any], options: Dict[str, Any], path: str) -> None:
    from PIL import Image, ImageDraw

    from app.services import product_video as pv

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = pv._font("ASKODOX", 40)
    w = d.textlength("ASKODOX", font=f)
    d.rounded_rectangle([W / 2 - w / 2 - 22, 30, W / 2 + w / 2 + 22, 98], radius=34, fill=(255, 255, 255, 235))
    d.text((W / 2 - w / 2, 40), "ASKODOX", font=f, fill=pv.NAVY)
    tag = price_tag(row)
    if tag:
        f2 = pv._font(tag, 44)
        tw = d.textlength(tag, font=f2)
        x0, y0 = W - 36 - tw - 44, H - 330
        d.rounded_rectangle([x0, y0, x0 + tw + 44, y0 + 78], radius=18, fill=(255, 255, 255, 245))
        d.polygon([(x0 - 18, y0 + 39), (x0 + 2, y0 + 10), (x0 + 2, y0 + 68)], fill=(255, 255, 255, 245))
        d.text((x0 + 22, y0 + 12), tag, font=f2, fill=pv.PINK)
    if options.get("presenter") in PRESENTERS:
        try:
            full = Image.open(os.path.join(ASSETS, "presenters", PRESENTERS[options["presenter"]])).convert("RGB")
            size, side = 190, int(full.width * 0.5)  # head and shoulders: a square from the top of the full figure
            left = (full.width - side) // 2
            face = full.crop((left, int(full.height * 0.04), left + side, int(full.height * 0.04) + side)).resize((size, size))
            mask = Image.new("L", (size, size), 0)
            ImageDraw.Draw(mask).ellipse([0, 0, size, size], fill=255)
            d.ellipse([28, H - 250 - 6, 28 + size + 12, H - 250 + size + 6], fill=(255, 255, 255, 240))
            img.paste(face, (34, H - 250), mask)
        except Exception:
            pass
    img.save(path)


def _end_png(path: str) -> None:
    from PIL import Image, ImageDraw

    from app.services import product_video as pv

    img = Image.new("RGB", (W, H), pv.NAVY)
    d = ImageDraw.Draw(img)
    for text, size, y, color in (("ASKODOX", 76, 470, (255, 255, 255)), ("More on the ASKODOX app", 38, 590, (255, 196, 61)),
                                 ("askodox.com/shop", 30, 660, (210, 214, 240))):
        f = pv._font(text, size)
        d.text(((W - d.textlength(text, font=f)) / 2, y), text, font=f, fill=color)
    img.save(path)


def render(exe: str, src: str, row: Dict[str, Any], options: Dict[str, Any], voices: List[str], out: str,
           work: str) -> Dict[str, Any]:
    """Staff video (main picture, its own sound lowered) + overlay + voice + end card -> 720x1280 MP4."""
    info = probe(exe, src)
    seconds = float(info.get("seconds") or 0)
    if seconds <= 0:
        return {"ok": False, "reason": "unreadable_video"}
    overlay, end = os.path.join(work, "overlay.png"), os.path.join(work, "end.png")
    _overlay_png(row, options, overlay)
    _end_png(end)
    voice = ""
    if voices:
        listing = os.path.join(work, "voices.txt")
        with open(listing, "w") as handle:
            handle.write("".join(f"file '{p}'\n" for p in voices))
        voice = os.path.join(work, "voice.m4a")
        joined = subprocess.run([exe, "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i",
                                 listing, "-af", "apad=pad_dur=0.25", "-c:a", "aac", "-b:a", "128k", voice],
                                capture_output=True, timeout=120)
        if joined.returncode != 0:
            voice = ""
    voice_seconds = float(probe(exe, voice).get("seconds") or 0) if voice else 0.0
    hold = max(0.0, voice_seconds + 0.6 - seconds)  # freeze the last frame when the voice is longer
    total = seconds + hold
    args = [exe, "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-i", overlay,
            "-loop", "1", "-t", f"{END_SECONDS}", "-i", end]
    base_audio = "[0:a]volume=0.25[orig];" if info.get("audio") else ""
    if voice:
        args += ["-i", voice]
    args += ["-f", "lavfi", "-t", f"{END_SECONDS}", "-i", "anullsrc=r=44100:cl=stereo"]
    silent = 4 if voice else 3
    graph = (f"[0:v]scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2:color=0x14161f,"
             f"setsar=1,fps={FPS}" + (f",tpad=stop_mode=clone:stop_duration={hold:.2f}" if hold else "") + "[v0];"
             "[v0][1:v]overlay=0:0[main];"
             f"[2:v]scale={W}:{H},setsar=1,fps={FPS},format=yuv420p[endv];")
    if info.get("audio") and voice:
        graph += (base_audio + f"[3:a]adelay=300|300[vo];[orig][vo]amix=inputs=2:duration=longest:normalize=0,"
                  f"apad,atrim=0:{total:.2f}[ma];")
    elif voice:
        graph += f"[3:a]adelay=300|300,apad,atrim=0:{total:.2f}[ma];"
    elif info.get("audio"):
        graph += f"[0:a]volume=1.0,apad,atrim=0:{total:.2f}[ma];"
    else:
        graph += f"anullsrc=r=44100:cl=stereo,atrim=0:{total:.2f}[ma];"
    graph += (f"[ma]aresample=44100,aformat=channel_layouts=stereo[mab];[{silent}:a]aresample=44100,"
              "aformat=channel_layouts=stereo[ea];[main]format=yuv420p[mv];[mv][mab][endv][ea]concat=n=2:v=1:a=1[v][a]")
    args += ["-filter_complex", graph, "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "veryfast",
             "-crf", "23", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out]
    try:
        proc = subprocess.run(args, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": "timeout"}
    if proc.returncode != 0 or not os.path.exists(out) or os.path.getsize(out) == 0:
        return {"ok": False, "reason": "ffmpeg_error", "detail": (proc.stderr or "")[-300:]}
    return {"ok": True, "seconds": round(total + END_SECONDS, 1), "voice": bool(voice)}


def today_ist() -> str:
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=5, minutes=30))).date().isoformat()
