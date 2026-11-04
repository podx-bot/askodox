"""ASKODOX Creations v2: a STORY reel, not a slideshow (owner 2026-11-04).

"Just photos one after another -- who buys from that? No words, no story.
Search its reviews, talk about the product like a person, one voice; make it
in Telugu and it should come in every language."

Pipeline (each step honest about what it knows):

1. ``gather_reviews`` -- what people say about the product, from the ONE web
   search chain (Serper / Brave). Only page titles + snippets + hosts are
   kept; nothing is invented when the search returns nothing.
2. ``write_script`` -- the AI writes 4-7 spoken scenes in the asked language
   (hook -> what it is -> key points -> what reviews say -> price + where to
   buy). Facts ONLY from the item record, the photos' facts and the review
   snippets; reviews are attributed ("online reviews ప్రకారం"), never given
   star ratings or counts that the snippets do not state; the price is the
   item's own price or none.
3. ``translate_script`` -- the same scenes in another language (spoken style,
   numbers and the price unchanged).
4. ``render`` -- one 720x1280 MP4: per scene a photo with slow zoom / pan for
   exactly as long as its voice line, a big on-screen caption, the ASKODOX
   logo; the last scene carries the title + price card. Voice = the caller's
   TTS per scene (ElevenLabs), silence when TTS is unavailable.

Never raises: every public function returns a value / {"ok": False, ...}.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
from typing import Any, Callable, Optional

from app.services import reel_maker as rm
from app.services import video_watermark as wm

LANGUAGES = {"te": "Telugu", "en": "English", "hi": "Hindi", "ta": "Tamil", "kn": "Kannada", "ml": "Malayalam"}
MIN_SCENES, MAX_SCENES = 3, 7
MIN_SCENE_S, MAX_SCENE_S = 2.5, 9.0
TIMEOUT_S = 600


# ----------------------------------------------------------------- reviews --

def gather_reviews(search: Any, title: str, brand: str = "", limit: int = 6) -> list[dict[str, str]]:
    """Real review snippets for the product (title, snippet, host, url)."""
    if search is None or not (title or "").strip():
        return []
    query = f"{brand} {title} review".strip() if brand and brand.lower() not in title.lower() else f"{title} review"
    try:
        rows = search(query, limit) or []
    except Exception:
        return []
    out = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        snippet = str(row.get("description") or row.get("snippet") or "").strip()
        url = str(row.get("url") or row.get("link") or "").strip()
        if not snippet or not url.startswith("https://"):
            continue
        host = re.sub(r"^www\.", "", url.split("/")[2]) if url.count("/") >= 2 else ""
        out.append({"title": str(row.get("title") or "")[:160], "snippet": snippet[:400], "host": host, "url": url})
    return out[:limit]


# ------------------------------------------------------------------ script --

SCRIPT_RULES = (
    "You write the voice-over for a 20-40 second vertical product video for ASKODOX, spoken by ONE friendly "
    "person talking to a customer, like a trusted local shop owner -- not an advert voice, no shouting. "
    "Return ONLY JSON: {\"scenes\": [{\"say\": \"what the voice says (1-2 short sentences)\", "
    "\"caption\": \"3-7 words shown big on screen\"}]} with 4-6 scenes in this order: a hook that names the "
    "customer's need; what the product is; 2-3 real points from the facts; what reviews say (ONLY if review "
    "snippets are given -- say they are online reviews, summarise honestly incl. common complaints, never give "
    "a star rating, percentage or count that the snippets do not state); price and where to buy (\"ASKODOX లో "
    "చూడండి\" / \"see it on ASKODOX\"). "
    "Use ONLY the facts below. Never invent features, materials, sizes, offers, discounts, guarantees, health or "
    "safety claims. The price is ONLY the given price; with no price, do not mention a number. Natural spoken "
    "{language} (Telugu: everyday Telugu, common English product words are fine). No hashtags, no emojis."
)


def _json(text: str) -> Optional[dict]:
    m = re.search(r"\{.*\}", text or "", re.S)
    if not m:
        return None
    try:
        data = json.loads(m.group(0))
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def _clean_scenes(data: Optional[dict]) -> list[dict[str, str]]:
    scenes = []
    for s in (data or {}).get("scenes") or []:
        if not isinstance(s, dict):
            continue
        say = " ".join(str(s.get("say") or "").split())[:320]
        caption = " ".join(str(s.get("caption") or "").split())[:60]
        if say:
            scenes.append({"say": say, "caption": caption or say[:40]})
    return scenes[:MAX_SCENES]


def write_script(write: Callable[[str], str], item: dict[str, Any], *, language: str = "te",
                 photo_facts: list[str] | None = None, reviews: list[dict[str, str]] | None = None
                 ) -> dict[str, Any]:
    """{"ok", "scenes": [...], "language", "sources": [review urls]} -- never raises."""
    facts = {k: item.get(k) for k in ("title", "brand", "category", "description", "price", "mrp", "seller",
                                      "offer_text") if item.get(k) not in (None, "", [])}
    price = rm.price_text(item.get("price"), str(item.get("currency") or "INR"))
    if price:
        facts["price"] = price
    lines = [SCRIPT_RULES.replace("{language}", LANGUAGES.get(language, "Telugu")),
             "PRODUCT FACTS (JSON): " + json.dumps(facts, ensure_ascii=False)]
    if photo_facts:
        lines.append("WHAT THE PHOTOS SHOW: " + " | ".join(photo_facts)[:1200])
    if reviews:
        lines.append("ONLINE REVIEW SNIPPETS (from " + ", ".join(sorted({r["host"] for r in reviews})) + "): "
                     + " || ".join(r["snippet"] for r in reviews)[:2400])
    else:
        lines.append("NO REVIEWS FOUND: do not talk about reviews at all.")
    try:
        scenes = _clean_scenes(_json(write("\n\n".join(lines))))
    except Exception:
        scenes = []
    if len(scenes) < MIN_SCENES:
        return {"ok": False, "reason": "script_failed", "scenes": [], "language": language}
    return {"ok": True, "scenes": scenes, "language": language, "sources": [r["url"] for r in reviews or []]}


def custom_script(text: str, language: str = "te") -> dict[str, Any]:
    """Staff's own narration: one scene per sentence (max 7)."""
    parts = [p.strip() for p in re.split(r"(?<=[.!?।])\s+|\n+", text or "") if p.strip()]
    scenes = [{"say": p[:320], "caption": p[:40]} for p in parts][:MAX_SCENES]
    return {"ok": bool(scenes), "scenes": scenes, "language": language, "sources": [], "custom": True}


def translate_script(write: Callable[[str], str], script: dict[str, Any], language: str) -> dict[str, Any]:
    """The same scenes spoken naturally in ``language`` (prices / numbers / brand names unchanged)."""
    prompt = ("Translate this product video voice-over into natural spoken "
              f"{LANGUAGES.get(language, language)} for the same friendly speaker. Keep the scene count and order, "
              "keep prices, numbers, brand and product names exactly, keep 'ASKODOX'. Do not add facts. Return ONLY "
              "JSON {\"scenes\": [{\"say\": ..., \"caption\": ...}]}.\n\n"
              + json.dumps({"scenes": script.get("scenes") or []}, ensure_ascii=False))
    try:
        scenes = _clean_scenes(_json(write(prompt)))
    except Exception:
        scenes = []
    if len(scenes) != len(script.get("scenes") or []):
        return {"ok": False, "reason": "translate_failed", "scenes": [], "language": language}
    return {**script, "scenes": scenes, "language": language, "ok": True}


# ------------------------------------------------------------------ render --

def audio_seconds(exe: str, path: str) -> Optional[float]:
    try:
        probe = subprocess.run([exe, "-hide_banner", "-i", path], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", probe.stderr or "")
    if not m:
        return None
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))


def estimate_seconds(text: str) -> float:
    """Silent fallback: a calm reading pace."""
    return max(MIN_SCENE_S, min(MAX_SCENE_S, len((text or "").split()) * 0.45 + 0.8))


def caption_png(caption: str, out: str, *, last: Optional[tuple[str, str]] = None) -> str:
    """Full-frame overlay: big caption in a dark rounded box (lower third), the
    logo top-right; the last scene also carries the title + price band."""
    from PIL import Image, ImageDraw

    if last:
        rm.card_png(last[0], last[1], out)
        img = Image.open(out).convert("RGBA")
        box_bottom = rm.H - 360
    else:
        img = Image.new("RGBA", (rm.W, rm.H), (0, 0, 0, 0))
        if os.path.exists(wm.LOGO):
            mark = Image.open(wm.LOGO).convert("RGBA")
            side = 110
            mark = mark.resize((side, int(mark.height * side / mark.width)))
            img.alpha_composite(mark, (rm.W - side - 28, 40))
        box_bottom = rm.H - 170
    text = (caption or "").strip()
    if text:
        draw = ImageDraw.Draw(img)
        font = rm._font(text, 54)
        lines = rm._wrap(draw, text, font, rm.W - 120, lines=3)
        line_h = 70
        box_h = line_h * len(lines) + 44
        top = box_bottom - box_h
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rounded_rectangle([40, top, rm.W - 40, box_bottom], radius=28, fill=(0, 0, 0, 165))
        img.alpha_composite(layer)
        draw = ImageDraw.Draw(img)
        y = top + 22
        for line in lines:
            width = draw.textlength(line, font=font)
            draw.text(((rm.W - width) / 2, y), line, font=font, fill=(255, 255, 255, 255))
            y += line_h
    img.save(out)
    return out


def command(exe: str, scenes: list[dict[str, Any]], out: str) -> list[str]:
    """scenes: [{photo, overlay, audio|None, seconds}] -> one MP4 (video + voice)."""
    args = [exe, "-hide_banner", "-loglevel", "error", "-y"]
    parts, chain = [], ""
    for i, s in enumerate(scenes):
        d = float(s["seconds"])
        args += ["-i", s["photo"], "-loop", "1", "-t", f"{d:.2f}", "-i", s["overlay"]]
        if s.get("audio"):
            args += ["-i", s["audio"]]
        else:
            args += ["-f", "lavfi", "-t", f"{d:.2f}", "-i", "anullsrc=r=44100:cl=stereo"]
        v, o, a = 3 * i, 3 * i + 1, 3 * i + 2
        frames = int(round(d * rm.FPS))
        # Alternate a slow push-in and a gentle drift so scenes do not feel like a slideshow.
        motion = ("z='min(zoom+0.0010,1.12)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'" if i % 2 == 0 else
                  "z='1.10':x='(iw-iw/zoom)*on/" + str(max(1, frames)) + "':y='ih/2-(ih/zoom/2)'")
        parts.append(f"[{v}:v]scale={rm.W * 2}:{rm.H * 2}:force_original_aspect_ratio=increase,"
                     f"crop={rm.W * 2}:{rm.H * 2},setsar=1,zoompan={motion}:d={frames}:s={rm.W}x{rm.H}:fps={rm.FPS},"
                     f"trim=duration={d:.2f},setpts=PTS-STARTPTS[z{i}]")
        parts.append(f"[{o}:v]format=rgba[c{i}]")
        parts.append(f"[z{i}][c{i}]overlay=0:0:shortest=1,format=yuv420p[v{i}]")
        parts.append(f"[{a}:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,"
                     f"apad,atrim=0:{d:.2f},asetpts=PTS-STARTPTS[a{i}]")
        chain += f"[v{i}][a{i}]"
    parts.append(f"{chain}concat=n={len(scenes)}:v=1:a=1[v][a]")
    args += ["-filter_complex", ";".join(parts), "-map", "[v]", "-map", "[a]",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-r", str(rm.FPS),
             "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out]
    return args


def render(photos: list[str], script: dict[str, Any], title: str, price: str, out: str, *,
           voice: Optional[Callable[[str], Optional[bytes]]] = None, exe: Optional[str] = None,
           run: Callable[..., Any] = subprocess.run) -> dict[str, Any]:
    """Write the story reel to ``out``. ``voice(text) -> mp3 bytes | None``."""
    photos = [p for p in photos if p and os.path.exists(p)][:rm.MAX_PHOTOS]
    scenes_in = script.get("scenes") or []
    if not photos:
        return {"ok": False, "reason": "no_photos"}
    if not scenes_in:
        return {"ok": False, "reason": "no_script"}
    exe = exe or wm.ffmpeg_exe()
    if not exe:
        return {"ok": False, "reason": "ffmpeg_missing"}
    temp: list[str] = []
    voiced = 0
    try:
        scenes = []
        for i, scene in enumerate(scenes_in):
            audio_path, seconds = None, estimate_seconds(scene["say"])
            data = None
            if voice is not None:
                try:
                    data = voice(scene["say"])
                except Exception:
                    data = None
            if data:
                audio_path = f"{out}.s{i}.mp3"
                with open(audio_path, "wb") as handle:
                    handle.write(data)
                temp.append(audio_path)
                measured = audio_seconds(exe, audio_path)
                if measured:
                    seconds = max(MIN_SCENE_S, measured + 0.35)
                    voiced += 1
            overlay = caption_png(scene.get("caption") or "", f"{out}.c{i}.png",
                                  last=(title, price) if i == len(scenes_in) - 1 else None)
            temp.append(overlay)
            scenes.append({"photo": photos[i % len(photos)], "overlay": overlay, "audio": audio_path,
                           "seconds": round(seconds, 2)})
        tmp = out + ".part.mp4"
        temp.append(tmp)
        result = run(command(exe, scenes, tmp), capture_output=True, text=True, timeout=TIMEOUT_S)
        if getattr(result, "returncode", 1) != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
            return {"ok": False, "reason": "ffmpeg_error"}
        os.replace(tmp, out)
        return {"ok": True, "seconds": round(sum(s["seconds"] for s in scenes), 1), "scenes": len(scenes),
                "voiced_scenes": voiced}
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": "timeout"}
    except Exception:
        return {"ok": False, "reason": "error"}
    finally:
        for path in temp:
            try:
                os.remove(path)
            except OSError:
                pass
