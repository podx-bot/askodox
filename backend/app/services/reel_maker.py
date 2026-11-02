"""ASKODOX Creations: a short product reel from an item's own photos.

Input = the item's photos that were uploaded to ASKODOX (never an arbitrary
URL), its title and its stated price; optional spoken audio (already
synthesized by the caller). Output = a 720x1280 MP4: each photo with a slow
zoom, the title + price card at the bottom, the ASKODOX logo top-right,
the voice (or silence) as audio.

Truth rules: the card shows only what the item record states -- no invented
price, discount or claim; a missing price is simply not shown. No music is
added (no licensed library is bundled). Telugu titles render with Noto Sans
Telugu (Pillow + raqm); fonts are SIL OFL (assets/fonts/OFL.txt).
"""
from __future__ import annotations

import os
import re
import subprocess
from typing import Any, Callable, Optional

from app.services import video_watermark as wm

ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
FONT_LATIN = os.path.join(ASSETS, "fonts", "NotoSans-Bold.ttf")
FONT_TELUGU = os.path.join(ASSETS, "fonts", "NotoSansTelugu-Bold.ttf")
W, H, FPS = 720, 1280, 25
DEFAULT_SECONDS = 30
MIN_PER_PHOTO = 2.0
MAX_PHOTOS = 10
TIMEOUT_S = 420
_TELUGU = re.compile(r"[ఀ-౿]")


def price_text(price: Any, currency: str = "INR") -> str:
    """The item's own price, formatted; empty when the record has none."""
    try:
        value = float(price)
    except (TypeError, ValueError):
        return ""
    if value <= 0:
        return ""
    amount = f"{value:,.0f}" if value == int(value) else f"{value:,.2f}"
    return f"₹{amount}" if (currency or "INR").upper() == "INR" else f"{currency.upper()} {amount}"


def _font(text: str, size: int):
    from PIL import ImageFont

    path = FONT_TELUGU if _TELUGU.search(text or "") else FONT_LATIN
    try:
        return ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)
    except Exception:
        return ImageFont.truetype(path, size)


def _wrap(draw: Any, text: str, font: Any, width: int, lines: int = 2) -> list[str]:
    words, out, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            out.append(line)
            line = word
            if len(out) == lines:
                break
    if line and len(out) < lines:
        out.append(line)
    if len(out) == lines and " ".join(out) != text.strip():
        out[-1] = out[-1].rstrip(".,") + "…"
    return out


def card_png(title: str, price: str, out: str, logo: str = wm.LOGO) -> str:
    """Transparent full-frame overlay: dark band with title + price at the
    bottom, ASKODOX logo top-right."""
    from PIL import Image, ImageDraw

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    band_top = H - 330
    band = Image.new("RGBA", (W, H - band_top), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(band.height):  # soft gradient so photos stay visible above
        bd.line([(0, y), (W, y)], fill=(0, 0, 0, int(40 + 170 * y / band.height)))
    img.alpha_composite(band, (0, band_top))
    draw = ImageDraw.Draw(img)
    title_font = _font(title, 46)
    y = band_top + 60
    for line in _wrap(draw, title.strip(), title_font, W - 80):
        draw.text((40, y), line, font=title_font, fill=(255, 255, 255, 255))
        y += 62
    if price:
        draw.text((40, y + 14), price, font=_font(price, 72), fill=(255, 214, 102, 255))
    if os.path.exists(logo):
        mark = Image.open(logo).convert("RGBA")
        side = 110
        mark = mark.resize((side, int(mark.height * side / mark.width)))
        img.alpha_composite(mark, (W - side - 28, 40))
    img.save(out)
    return out


def command(exe: str, photos: list[str], card: str, out: str, seconds: float,
            audio: Optional[str] = None) -> list[str]:
    n = len(photos)
    per = max(MIN_PER_PHOTO, seconds / n)
    total = per * n
    frames = int(round(per * FPS))
    args = [exe, "-hide_banner", "-loglevel", "error", "-y"]
    for photo in photos:
        args += ["-i", photo]
    args += ["-loop", "1", "-i", card]
    if audio:
        args += ["-i", audio]
    else:
        args += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
    parts = []
    for i in range(n):
        parts.append(f"[{i}:v]scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},setsar=1,"
                     f"zoompan=z='min(zoom+0.0007,1.08)':d={frames}:s={W}x{H}:fps={FPS}[p{i}]")
    parts.append("".join(f"[p{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[slides]")
    parts.append(f"[{n}:v]format=rgba[card]")
    parts.append("[slides][card]overlay=0:0:shortest=1,format=yuv420p[v]")
    parts.append(f"[{n + 1}:a]apad,atrim=0:{total:.2f}[a]")
    args += ["-filter_complex", ";".join(parts), "-map", "[v]", "-map", "[a]", "-t", f"{total:.2f}",
             "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-r", str(FPS),
             "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out]
    return args


def make_reel(photos: list[str], title: str, price: str, out: str, *, seconds: float = DEFAULT_SECONDS,
              audio: Optional[str] = None, exe: Optional[str] = None,
              run: Callable[..., Any] = subprocess.run) -> dict[str, Any]:
    """Write the reel to ``out``. Returns {"ok": True, "seconds": n} or
    {"ok": False, "reason": ...}; never raises."""
    photos = [p for p in photos if p and os.path.exists(p)][:MAX_PHOTOS]
    if not photos:
        return {"ok": False, "reason": "no_photos"}
    if not (title or "").strip():
        return {"ok": False, "reason": "no_title"}
    exe = exe or wm.ffmpeg_exe()
    if not exe:
        return {"ok": False, "reason": "ffmpeg_missing"}
    card = out + ".card.png"
    tmp = out + ".part.mp4"
    try:
        card_png(title, price, card)
        result = run(command(exe, photos, card, tmp, seconds, audio), capture_output=True, text=True,
                     timeout=TIMEOUT_S)
        if getattr(result, "returncode", 1) != 0 or not os.path.exists(tmp) or os.path.getsize(tmp) == 0:
            return {"ok": False, "reason": "ffmpeg_error"}
        os.replace(tmp, out)
        return {"ok": True, "seconds": round(max(MIN_PER_PHOTO, seconds / len(photos)) * len(photos), 1)}
    except subprocess.TimeoutExpired:
        return {"ok": False, "reason": "timeout"}
    except Exception:
        return {"ok": False, "reason": "error"}
    finally:
        for path in (card, tmp):
            try:
                os.remove(path)
            except OSError:
                pass
