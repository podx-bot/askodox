"""Collection video: 2-5 Staff Workspace items in one 9:16 reel (owner 2026-11-21, like Meesho's "TOP FINDS" posts).

* ASKODOX brand on top, the staff's theme title under it ("TOP WINTER FINDS"), our own frame -- never a store's logo
  or sale artwork.
* Each item gets its own segment: its photos zooming / drifting slowly, its name and its price tag.
* The voice reads a fixed, honest script built only from the item records (name + price) -- no claims, no reviews,
  no first person. ElevenLabs -> Sarvam (``product_video.synthesize``); no voice = music-free captions-only video.
* Owner rule (Studio spec): no Telugu sentences burned into the picture (Facebook / Instagram auto-dubbing) -- the
  picture carries English names, numbers and ₹ only; the Telugu is in the voice.

Nothing is published here; the caller stores the video for staff review.
"""
from __future__ import annotations

import math
import os
import re
import subprocess
from typing import Any, Dict, List, Optional

from app.services import product_video as pv

W, H, FPS = pv.W, pv.H, pv.FPS
PY, PH = 270, 790  # picture area
GOLD = (255, 196, 61)
NAVY, VIOLET, PINK = pv.NAVY, pv.VIOLET, pv.PINK
MIN_ITEMS, MAX_ITEMS = 2, 5
DEFAULT_THEME = "TOP FINDS"
_INDIC = re.compile(r"[ऀ-෿]")  # Devanagari .. Sinhala: every Indian script


def clean_theme(theme: str) -> str:
    """The theme title shown in the picture: Latin letters / numbers / ₹ only, upper case, <= 28 chars."""
    text = re.sub(r"\s+", " ", str(theme or "")).strip()
    if not text or _INDIC.search(text):
        return DEFAULT_THEME
    text = re.sub(r"[^A-Za-z0-9₹&+'!%:. -]", "", text).strip()[:28]
    return text.upper() or DEFAULT_THEME


def picture_name(title: str) -> str:
    """The item name for the picture: Latin only (Indic words dropped), <= 48 chars."""
    words = [w for w in str(title or "").split() if not _INDIC.search(w)]
    text = re.sub(r"\s+", " ", " ".join(words)).strip(" ,-|")
    return (text[:46] + "…") if len(text) > 48 else (text or "ASKODOX Pick")


def script(items: List[Dict[str, Any]], prices: List[str], language: str = "te") -> List[Dict[str, str]]:
    """Fixed lines: intro, one per item (name + price only), outro. kind = intro / item / outro."""
    intro = {"te": "ASKODOX లో ఈరోజు టాప్ ఫైండ్స్ చూడండి.", "hi": "ASKODOX पर आज के टॉप फाइंड्स देखिए.",
             "en": "Here are today's top finds on ASKODOX."}
    outro = {"te": "లింక్‌లు కింద, ప్రొఫైల్‌లో ఉన్నాయి. ASKODOX లో ఇంకా చూడండి.",
             "hi": "लिंक नीचे और प्रोफ़ाइल में हैं. ASKODOX पर और देखिए.",
             "en": "Links are below and in our profile. See more on ASKODOX."}
    lang = language if language in intro else "te"
    lines = [{"kind": "intro", "spoken": intro[lang]}]
    for k, (item, price) in enumerate(zip(items, prices)):
        name = re.sub(r"\s+", " ", str(item.get("title") or "")).strip()[:70] or "this product"
        if price:
            spoken = {"te": f"నంబర్ {k + 1}. {name}. ధర {price} మాత్రమే.",
                      "hi": f"नंबर {k + 1}. {name}. कीमत सिर्फ़ {price}.",
                      "en": f"Number {k + 1}. {name}. Just {price}."}[lang]
        else:
            spoken = {"te": f"నంబర్ {k + 1}. {name}.", "hi": f"नंबर {k + 1}. {name}.",
                      "en": f"Number {k + 1}. {name}."}[lang]
        lines.append({"kind": "item", "spoken": spoken, "index": str(k)})
    lines.append({"kind": "outro", "spoken": outro[lang]})
    return lines


class CollectionPainter:
    def __init__(self, groups: List[List[Any]], items: List[Dict[str, Any]], prices: List[str], theme: str) -> None:
        from PIL import Image, ImageDraw

        self.Image, self.ImageDraw = Image, ImageDraw
        self.groups = [[self._fit(p.convert("RGB")) for p in g[:3]] for g in groups]
        self.names = [picture_name(i.get("title")) for i in items]
        self.prices, self.theme = prices, clean_theme(theme)
        self.collage = self._collage()

    @staticmethod
    def _fit(img: Any) -> Any:
        """A photo on a canvas of the picture area's shape (soft sides) so every zoom box stays inside."""
        from PIL import Image, ImageFilter

        aspect = W / PH
        if img.width / img.height > aspect:
            cw, ch = img.width, int(img.width / aspect)
        else:
            cw, ch = int(img.height * aspect), img.height
        back = pv._cover(img, cw, ch).filter(ImageFilter.GaussianBlur(24)).point(lambda v: int(v * 0.6 + 90))
        back = back.resize((cw, ch))
        back.paste(img, ((cw - img.width) // 2, (ch - img.height) // 2))
        return back

    def _collage(self) -> Any:
        img = self.Image.new("RGB", (W, PH), (250, 246, 255))
        firsts = [g[0] for g in self.groups if g][:4]
        cols = 2 if len(firsts) > 1 else 1
        rows = math.ceil(len(firsts) / cols)
        cw, ch = W // cols, PH // rows
        for k, ph in enumerate(firsts):
            last_alone = k == len(firsts) - 1 and len(firsts) % cols == 1 and cols > 1
            w = W - 8 if last_alone else cw - 8
            img.paste(pv._cover(ph, w, ch - 8), (4 if last_alone else (k % cols) * cw + 4, (k // cols) * ch + 4))
        return img

    def _shot(self, g: int, u: float) -> Any:
        photos = self.groups[g] or [self.collage]
        n = len(photos)
        k = min(int(u * n), n - 1)
        v = u * n - k  # progress inside this photo
        img = photos[k]
        z = 1.0 + 0.18 * pv._ease(v) if k % 2 == 0 else 1.18 - 0.12 * pv._ease(v)
        bw, bh = img.width / z, img.height / z
        cx = img.width / 2 + (0.25 if k % 2 else -0.25) * img.width * (1 - 1 / z) * (v - 0.5)
        cy = img.height / 2 - 0.2 * img.height * (1 - 1 / z) * (v - 0.5)
        box = (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)
        return img.crop(tuple(int(x) for x in box)).resize((W - 40, PH), self.Image.BILINEAR)

    def _pill(self, d: Any, text: str, cx: float, y: int, size: int, fill, bg) -> None:
        f = pv._font(text, size)
        w = d.textlength(text, font=f)
        d.rounded_rectangle([cx - w / 2 - 24, y, cx + w / 2 + 24, y + size + 26], radius=(size + 26) // 2, fill=bg)
        d.text((cx - w / 2, y + 8), text, font=f, fill=fill)

    def frame(self, kind: str, index: int, u: float, t: float) -> Any:
        img = self.Image.new("RGB", (W, H), NAVY)
        d = self.ImageDraw.Draw(img, "RGBA")
        for y in range(0, H, 8):  # soft violet glow towards the bottom
            d.rectangle([0, y, W, y + 8], fill=(*VIOLET, int(70 * y / H)))
        # brand on top + theme title
        self._pill(d, "ASKODOX", W / 2, 26, 44, NAVY, (255, 255, 255, 245))
        self._pill(d, self.theme, W / 2, 128, 38, NAVY, (*GOLD, 255))
        # picture with a twinkling gold frame
        pic = self.collage if kind != "item" else self._shot(index, u)
        if pic.size != (W - 40, PH):
            pic = pic.resize((W - 40, PH), self.Image.BILINEAR)
        glow = 4 + int(3 * (1 + math.sin(t * 5)))
        d.rounded_rectangle([20 - glow, PY - glow, W - 20 + glow, PY + PH + glow], radius=26, fill=(*GOLD, 200))
        img.paste(pic, (20, PY))
        d = self.ImageDraw.Draw(img, "RGBA")
        for k in range(14):  # little lights on the frame
            x = 20 + (W - 40) * k / 13
            on = (k + int(t * 4)) % 2 == 0
            for y in (PY - 2, PY + PH + 2):
                d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(255, 255, 255, 240 if on else 110))
        if kind == "item":
            price = self.prices[index]
            if price:
                f = pv._font(price, 44)
                w = d.textlength(price, font=f)
                x0, y0 = W - 40 - w - 44, PY + PH - 190
                d.rounded_rectangle([x0, y0, x0 + w + 44, y0 + 76], radius=16, fill=(255, 255, 255, 250))
                d.polygon([(x0 - 18, y0 + 38), (x0 + 2, y0 + 10), (x0 + 2, y0 + 66)], fill=(255, 255, 255, 250))
                d.text((x0 + 22, y0 + 10), price, font=f, fill=PINK)
            self._pill(d, f"#{index + 1}", 86, PY + 22, 34, (255, 255, 255), (*PINK, 240))
            name = self.names[index]
            f = pv._font(name, 34)
            lines = pv._wrap(d, name, f, W - 120)[:2]
            top = PY + PH + 30
            d.rounded_rectangle([40, top, W - 40, top + len(lines) * 46 + 26], radius=24, fill=(*VIOLET, 245))
            for k, line in enumerate(lines):
                lw = d.textlength(line, font=f)
                d.text(((W - lw) / 2, top + 12 + k * 46), line, font=f, fill=(255, 255, 255))
        elif kind == "intro":
            pulse = 1 + 0.05 * math.sin(t * 6)
            self._pill(d, f"{len(self.names)} PICKS FOR YOU", W / 2, PY + PH + 34, int(40 * pulse), NAVY, (*GOLD, 255))
        else:
            pulse = 1 + 0.05 * math.sin(t * 6)
            self._pill(d, "LINKS BELOW", W / 2, PY + PH + 26, int(40 * pulse), (255, 255, 255), (*PINK, 255))
        self._pill(d, "askodox.com/shop", W / 2, H - 70, 26, NAVY, (255, 255, 255, 235))
        return img


def render(groups: List[List[Any]], items: List[Dict[str, Any]], prices: List[str], theme: str,
           lines: List[Dict[str, str]], audio: Optional[str], out: str, *, exe: str) -> Dict[str, Any]:
    """Write the MP4. {"ok": True, "seconds": n} or {"ok": False, "reason": ...}."""
    if not any(groups):
        return {"ok": False, "reason": "no_photos"}
    if audio:
        env = pv.envelope(exe, audio)
        bounds = pv.cut_points(env, [l["spoken"] for l in lines])
    else:
        seconds = [1.5 if l["kind"] == "intro" else 2.0 if l["kind"] == "outro" else 4.0 for l in lines]
        env = [0.0] * int(sum(seconds) * FPS)
        bounds, acc = [0], 0.0
        for s in seconds:
            acc += s
            bounds.append(int(acc * FPS))
        bounds[-1] = len(env)
    painter = CollectionPainter(groups, items, prices, theme)
    total_frames = len(env) + FPS
    tmp = out + ".part.mp4"
    args = [exe, "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
            "-r", str(FPS), "-i", "-"]
    args += ["-i", audio, "-af", "apad=pad_dur=1.2"] if audio else ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
    args += ["-t", f"{total_frames / FPS:.2f}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
             "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", tmp]
    try:
        proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for fi in range(total_frames):
            s = next((k for k in range(len(lines)) if bounds[k] <= fi < bounds[k + 1]), len(lines) - 1)
            span = max(1, bounds[s + 1] - bounds[s])
            u = min((fi - bounds[s]) / span, 1.0)
            line = lines[s]
            proc.stdin.write(painter.frame(line["kind"], int(line.get("index") or 0), u, fi / FPS).tobytes())
        proc.stdin.close()
        code = proc.wait(timeout=pv.TIMEOUT_S)
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
