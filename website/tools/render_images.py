#!/usr/bin/env python3
"""Regenerate the raster brand images in static/img (dev-only; needs Playwright).

The website itself never needs this at runtime: the PNGs are committed.
Run after changing the logo or brand colours:
    python3 tools/render_images.py
"""
from __future__ import annotations

import asyncio
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
FONTS = ROOT / "static" / "fonts"
OUT = ROOT / "static" / "img"

import base64


def _font(name: str) -> str:
    return "data:font/woff2;base64," + base64.b64encode((FONTS / name).read_bytes()).decode()


FONT_CSS = f"""
@font-face {{ font-family: B; src: url('{_font("bricolage-grotesque-latin-wght-normal.woff2")}'); font-weight: 200 800; }}
@font-face {{ font-family: A; src: url('{_font("atkinson-hyperlegible-next-latin-wght-normal.woff2")}'); font-weight: 200 800; }}
* {{ margin: 0; box-sizing: border-box; }}
"""

MARK = """<svg viewBox="0 0 64 64" style="width:100%;height:100%"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#B48CFF"/><stop offset=".55" stop-color="#603EFF"/><stop offset="1" stop-color="#2F7BFF"/></linearGradient></defs>
<circle cx="31" cy="34" r="17" fill="none" stroke="url(#g)" stroke-width="8"/><circle cx="44" cy="20" r="6" fill="#39C8FF"/></svg>"""

ORB = """<div style="position:relative;width:{s}px;height:{s}px;border-radius:50%;
background:radial-gradient(circle at 34% 28%,#fff 0%,#B48CFF 14%,#8A5CF6 36%,#603EFF 62%,#1c1aa8 100%);
box-shadow:0 0 {g}px rgba(96,62,255,.65), inset -10px -14px 30px rgba(5,6,10,.45), inset 6px 8px 22px rgba(255,255,255,.35);
display:flex;align-items:center;justify-content:center;gap:{gap}px;padding-bottom:{pb}px">
<span style="width:{ew}px;height:{eh}px;background:#fff;border-radius:50%"></span><span style="width:{ew}px;height:{eh}px;background:#fff;border-radius:50%"></span></div>"""


def icon_html(size: int, radius: int) -> str:
    return f"""<html><head><style>{FONT_CSS} body{{width:{size}px;height:{size}px;background:transparent}}</style></head>
<body><div style="width:{size}px;height:{size}px;border-radius:{radius}px;background:#070816;display:flex;align-items:center;justify-content:center">
<div style="width:{int(size*.78)}px;height:{int(size*.78)}px">{MARK}</div></div></body></html>"""


OG = f"""<html><head><style>{FONT_CSS}
body{{width:1200px;height:630px;background:radial-gradient(900px 500px at 50% -10%,rgba(96,62,255,.55),transparent 60%),radial-gradient(500px 400px at 95% 60%,rgba(57,200,255,.18),transparent 60%),#070816;
color:#fff;font-family:A;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}}
h1{{font-family:B;font-weight:800;font-size:150px;line-height:.9;background:linear-gradient(180deg,#fff 30%,#CFC2FF);-webkit-background-clip:text;color:transparent;margin-top:28px}}
p{{font-family:B;font-size:46px;font-weight:500;margin-top:18px}}
.ask{{margin-top:44px;width:760px;height:76px;border-radius:999px;border:2px solid #30375F;background:#11142A;display:flex;align-items:center;padding:0 12px 0 34px;font-size:28px;color:#9a9cc4;justify-content:space-between}}
.go{{width:56px;height:56px;border-radius:50%;background:linear-gradient(120deg,#B48CFF,#603EFF 60%,#2F7BFF)}}
</style></head><body>
{ORB.format(s=120, g=80, gap=20, pb=5, ew=11, eh=19)}
<h1>ASKODOX</h1><p>Here to Help You Grow.</p>
<div class="ask"><span>What can ASKODOX help you with today?</span><span class="go"></span></div>
</body></html>"""

LOGO = f"""<html><head><style>{FONT_CSS} body{{width:512px;height:512px;background:transparent}}</style></head><body>
<div style="width:512px;height:512px;border-radius:112px;background:#070816;display:flex;align-items:center;justify-content:center"><div style="width:400px;height:400px">{MARK}</div></div></body></html>"""


async def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        jobs = [
            ("og-askodox.png", OG, 1200, 630, False),
            ("askodox-logo-512.png", LOGO, 512, 512, True),
            ("icon-512.png", icon_html(512, 0), 512, 512, False),
            ("icon-192.png", icon_html(192, 0), 192, 192, False),
            ("apple-touch-icon.png", icon_html(180, 0), 180, 180, False),
            ("favicon-32.png", icon_html(32, 7), 32, 32, True),
        ]
        for name, html, w, h, transparent in jobs:
            pg = await b.new_page(viewport={"width": w, "height": h})
            await pg.set_content(html, wait_until="load")
            await pg.evaluate("document.fonts.ready")
            await pg.wait_for_timeout(300)
            await pg.screenshot(path=str(OUT / name), omit_background=transparent)
            await pg.close()
        await b.close()
    print("written:", ", ".join(sorted(x.name for x in OUT.glob("*.png"))))


if __name__ == "__main__":
    asyncio.run(main())
