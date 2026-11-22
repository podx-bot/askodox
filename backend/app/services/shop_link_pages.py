"""HTML of the public shop link (``/s/<slug>``): the shop page with its menu form, the "send on WhatsApp" page after
an order, the "order in the app" page, and the not-found page. No JavaScript: the menu is a plain form, taps on
call / UPI are counted with the link ``ping`` attribute. Telugu first, short English under it."""
from __future__ import annotations

import html
from typing import Any, Dict, List

from app.services.shop_links import _WEIGHED, _rupees

esc = html.escape


def _head(title: str, color: str) -> str:
    return (
        '<!doctype html><html lang="te"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f'<meta name="theme-color" content="{color}"><title>{esc(title)}</title><style>'
        'body{margin:0;font-family:system-ui,-apple-system,"Noto Sans Telugu",sans-serif;background:#f4f5f7;color:#1f2430}'
        '.w{max-width:480px;margin:0 auto;background:#fff;min-height:100vh;padding-bottom:120px}'
        f'.top{{background:{color};color:#fff;padding:18px 16px 16px}}'
        '.top h1{margin:0;font-size:24px;line-height:1.25}.top .k{opacity:.9;font-size:13.5px;margin-top:3px}'
        '.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}'
        '.chip{background:rgba(255,255,255,.18);border-radius:999px;padding:4px 10px;font-size:12.5px}'
        '.banner{display:flex;align-items:center;gap:10px;background:#0f172a;color:#fff;padding:9px 12px;font-size:13px}'
        '.banner b{flex:1}.banner a{background:#fff;color:#0f172a;border-radius:999px;padding:6px 12px;'
        'text-decoration:none;font-weight:800;font-size:12.5px}'
        '.acts{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;padding:14px 12px 4px}'
        '.act{display:flex;flex-direction:column;align-items:center;gap:6px;text-decoration:none;color:#1f2430;'
        'font-size:12.5px;font-weight:700}'
        f'.act i{{width:54px;height:54px;border-radius:50%;background:{color}14;color:{color};display:flex;'
        'align-items:center;justify-content:center;font-style:normal;font-size:24px}'
        '.offer{margin:10px 12px 0;background:#fff7ed;border:1px solid #fed7aa;color:#9a3412;border-radius:12px;'
        'padding:10px 12px;font-weight:700;font-size:14px}'
        '.about{margin:10px 14px 0;font-size:14px;color:#4b5563}'
        '.closed{margin:10px 12px 0;background:#fef2f2;border:1px solid #fecaca;color:#991b1b;border-radius:12px;'
        'padding:10px 12px;font-weight:700;font-size:14px}'
        'h2{font-size:17px;margin:18px 14px 6px}h3{font-size:13px;color:#6b7280;margin:14px 14px 4px;'
        'text-transform:uppercase;letter-spacing:.04em}'
        '.it{display:flex;align-items:center;gap:10px;padding:10px 14px;border-bottom:1px solid #f0f1f4}'
        '.it .n{flex:1;font-size:15px;font-weight:650}.it .n small{display:block;color:#6b7280;font-weight:500;font-size:12.5px}'
        '.it .p{font-weight:800;font-size:15px;white-space:nowrap}'
        '.it input{width:58px;font-size:16px;padding:8px 6px;border:1.5px solid #d1d5db;border-radius:10px;text-align:center}'
        '.out{color:#9ca3af;font-size:12.5px;font-weight:700}'
        '.dot{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:5px;vertical-align:1px}'
        '.tag{background:#fef3c7;color:#92400e;border-radius:6px;font-size:11px;padding:1px 6px;margin-left:6px}'
        '.who{padding:8px 14px}.who input,.who textarea{width:100%;box-sizing:border-box;font-size:15px;padding:10px;'
        'border:1.5px solid #d1d5db;border-radius:10px;margin-top:6px;font-family:inherit}'
        '.bar{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid #e5e7eb;padding:10px 12px 14px}'
        '.bar .in{max-width:456px;margin:0 auto;display:flex;gap:8px}'
        '.btn{flex:1;display:block;border:0;border-radius:16px;padding:15px 10px;font-size:16px;font-weight:800;'
        'text-align:center;text-decoration:none;cursor:pointer;font-family:inherit}'
        '.wa{background:#15803d;color:#fff}'
        f'.app{{background:{color};color:#fff}}.ghost{{background:#eef2f7;color:#1f2430}}'
        '.card{margin:14px 12px;border:1px solid #e5e7eb;border-radius:16px;padding:14px}'
        '.card p{margin:6px 0;font-size:14px;color:#4b5563}'
        '.row{display:flex;justify-content:space-between;padding:4px 0;font-size:15px}'
        '.tot{border-top:1px dashed #d1d5db;margin-top:6px;padding-top:8px;font-weight:900;font-size:17px}'
        '.step{display:flex;gap:10px;align-items:flex-start;margin:10px 0;font-size:14.5px}'
        f'.step b{{background:{color};color:#fff;border-radius:50%;min-width:26px;height:26px;display:flex;'
        'align-items:center;justify-content:center;font-size:13px}'
        '.foot{text-align:center;color:#6b7280;font-size:12.5px;padding:18px 14px}'
        '.foot a{color:#1d4ed8;font-weight:700}'
        '.note{color:#6b7280;font-size:12.5px;margin:6px 14px}'
        '.err{margin:10px 12px 0;background:#fffbeb;border:1px solid #fde68a;border-radius:12px;padding:10px 12px;'
        'font-size:14px;font-weight:700;color:#92400e}'
        '</style></head><body><div class="w">'
    )


def _foot(page: Dict[str, Any]) -> str:
    return (
        '<div class="foot">డబ్బు నేరుగా షాప్‌కే వెళ్తుంది — ASKODOX పట్టుకోదు.<br>'
        f'<a href="/s/{esc(page["slug"])}/go/join">మీ షాప్‌కి కూడా ఇలాంటి ఉచిత లింక్ →</a><br>'
        'ASKODOX · askodox.com</div>'
    )


def _stars(rating: Dict[str, Any]) -> str:
    avg = rating.get("average")
    count = int(rating.get("count") or 0)
    return f"★ {avg} ({count})" if avg else ""


def _food_dot(kind: str) -> str:
    color = {"veg": "#16a34a", "nonveg": "#b91c1c", "non_veg": "#b91c1c", "egg": "#d97706"}.get(kind or "")
    return f'<span class="dot" style="background:{color}"></span>' if color else ""


def _menu_rows(page: Dict[str, Any]) -> str:
    show_prices = bool(page["settings"].get("show_prices", True))
    can_order = bool(page.get("can_order"))
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for item in page["items"]:
        groups.setdefault(str(item.get("menu_group") or ""), []).append(item)
    out = []
    for group, items in groups.items():
        if group and len(groups) > 1:
            out.append(f"<h3>{esc(group)}</h3>")
        for item in items:
            unit = str(item.get("unit") or "")
            per = f" / {esc(unit)}" if unit and unit not in ("pcs", "plate", "service") else ""
            price = f'<span class="p">{_rupees(int(item.get("price_paise") or 0))}{per}</span>' if show_prices else ""
            te = item.get("name_te") or ""
            sub = f"<small>{esc(te)}</small>" if te and te != item.get("name") else ""
            tag = '<span class="tag">ఆఫర్</span>' if item.get("offer") else ""
            if not item.get("available", True):
                right = '<span class="out">ఈ రోజు అయిపోయింది</span>'
            elif can_order:
                step = "0.25" if unit in _WEIGHED else "1"
                right = (f'<input type="number" name="q_{esc(str(item.get("id")), quote=True)}" min="0" max="50" '
                         f'step="{step}" inputmode="decimal" placeholder="0" aria-label="{esc(str(item.get("name")), quote=True)}">')
            else:
                right = ""
            out.append(f'<div class="it"><div class="n">{_food_dot(str(item.get("food_type") or ""))}'
                       f'{esc(str(item.get("name")))}{tag}{sub}</div>{price}{right}</div>')
    return "".join(out)


def shop_html(page: Dict[str, Any], error: str = "") -> str:
    slug = esc(page["slug"])
    s = page["settings"]
    chips = [esc(page["kind_te"])]
    stars = _stars(page["rating"])
    if stars:
        chips.append(stars)
    if page.get("followers"):
        chips.append(f'{int(page["followers"])} మంది follow')
    if page["status"] == "open":
        chips.append("ఇప్పుడు తెరిచి ఉంది")
    parts = [_head(page["name"], page["color"]),
             '<div class="banner"><b>ASKODOX యాప్‌లో ఈ షాప్ — ఆర్డర్ లైవ్, బిల్లులు ఫోన్‌లోనే</b>'
             f'<a href="/s/{slug}/go/app">యాప్</a></div>',
             f'<div class="top"><h1>{esc(page["name"])}</h1><div class="k">{esc(page["address"])}</div>'
             f'<div class="chips">{"".join(f"<span class=chip>{c}</span>" for c in chips)}'
             f'<a class="chip" style="color:#fff;text-decoration:none" href="/s/{slug}/go/follow">+ Follow</a></div></div>']
    acts = []
    if page.get("phone"):
        acts.append(f'<a class="act" href="tel:+91{esc(page["phone"])}" ping="/s/{slug}/c/call"><i>📞</i>కాల్</a>')
    if s.get("show_map") and page.get("address"):
        acts.append(f'<a class="act" href="/s/{slug}/go/map"><i>📍</i>దారి</a>')
    if page.get("whatsapp"):
        acts.append(f'<a class="act" href="/s/{slug}/go/wa"><i>💬</i>WhatsApp</a>')
    if page.get("upi_link"):
        acts.append(f'<a class="act" href="{esc(page["upi_link"], quote=True)}" ping="/s/{slug}/c/pay"><i>₹</i>UPI కట్టు</a>')
    if acts:
        parts.append(f'<div class="acts">{"".join(acts)}</div>')
    if page["status"] != "open":
        parts.append('<div class="closed">ఈ షాప్ ఇప్పుడు ఆర్డర్లు తీసుకోవడం లేదు · Not taking orders now</div>')
    if s.get("offer"):
        parts.append(f'<div class="offer">🎁 {esc(s["offer"])}</div>')
    if s.get("about"):
        parts.append(f'<div class="about">{esc(s["about"])}</div>')
    if error:
        parts.append(f'<div class="err">{esc(error)}</div>')
    if page.get("upi_id"):
        parts.append(f'<p class="note">UPI ID: <b>{esc(page["upi_id"])}</b> — మొత్తం మీ UPI యాప్‌లో రాయండి.</p>')
    if page["items"]:
        parts.append(f'<form method="get" action="/s/{slug}/order"><h2>మెనూ · Menu</h2>{_menu_rows(page)}')
        if page.get("can_order"):
            parts.append('<div class="who"><input name="name" maxlength="40" placeholder="మీ పేరు (ఐచ్ఛికం)">'
                         '<textarea name="note" maxlength="160" rows="2" placeholder="గమనిక: పార్సిల్ / డెలివరీ / సమయం"></textarea>'
                         '<p class="note">ధర సుమారు — ఆఫర్ / పన్ను షాప్ బిల్లులో.</p></div>'
                         '<div class="bar"><div class="in">'
                         '<button class="btn wa" name="via" value="wa">WhatsApp లో ఆర్డర్</button>'
                         '<button class="btn app" name="via" value="app">యాప్‌లో ఆర్డర్</button></div></div>')
        parts.append("</form>")
    parts.append(_foot(page))
    parts.append("</div></body></html>")
    return "".join(parts)


def _summary(page: Dict[str, Any], order: Dict[str, Any]) -> str:
    show_prices = bool(page["settings"].get("show_prices", True))
    rows = []
    for line in order["lines"]:
        unit = f' {esc(line["unit"])}' if line["unit"] in _WEIGHED else ""
        price = _rupees(line["amount_paise"]) if show_prices else ""
        rows.append(f'<div class="row"><span>{line["qty"]:g}{unit} × {esc(str(line["name"]))}</span><span>{price}</span></div>')
    total = (f'<div class="row tot"><span>మొత్తం సుమారు</span><span>{_rupees(order["total_paise"])}</span></div>'
             if show_prices else "")
    return f'<div class="card">{"".join(rows)}{total}</div>'


def after_html(page: Dict[str, Any], order: Dict[str, Any]) -> str:
    """After "order on WhatsApp": the ready message, one big send button, then the app ask."""
    slug = esc(page["slug"])
    if order.get("whatsapp_url"):
        send = (f'<a class="btn wa" href="{esc(order["whatsapp_url"], quote=True)}">WhatsApp లో {esc(page["name"])}కి పంపండి</a>')
    elif page.get("phone"):
        send = f'<a class="btn wa" href="tel:+91{esc(page["phone"])}" ping="/s/{slug}/c/call">షాప్‌కి కాల్ చేసి చెప్పండి</a>'
    else:
        send = '<p class="note">ఈ షాప్ WhatsApp నంబర్ ఇవ్వలేదు — షాప్‌లో చెప్పండి.</p>'
    return "".join([
        _head(page["name"] + " · ఆర్డర్", page["color"]),
        f'<div class="top"><h1>మీ ఆర్డర్ సిద్ధం</h1><div class="k">{esc(page["name"])}</div></div>',
        _summary(page, order),
        f'<div style="padding:0 12px">{send}</div>',
        '<p class="note">WhatsApp తెరుచుకున్నాక "Send" నొక్కండి — షాప్ అక్కడే జవాబిస్తుంది.</p>',
        '<div class="card"><b>తర్వాతసారి ASKODOX యాప్‌లో ఆర్డర్ చేయండి</b>'
        '<p>ఆర్డర్ ఎక్కడుందో లైవ్‌లో · బిల్లు మీ ఫోన్‌లోనే · ఈ షాప్ ఆఫర్లు ముందే.</p>'
        f'<a class="btn app" href="/s/{slug}/go/app">ASKODOX యాప్ (ఉచితం)</a></div>',
        f'<p class="foot"><a href="/s/{slug}">← షాప్ పేజీకి</a></p>',
        _foot(page), "</div></body></html>",
    ])


def app_html(page: Dict[str, Any], order: Dict[str, Any]) -> str:
    """"Order in the app": install, find this shop, order + follow it live; WhatsApp stays one tap away."""
    slug = esc(page["slug"])
    wa = (f'<a class="btn ghost" href="{esc(order["whatsapp_url"], quote=True)}">ఇప్పుడే WhatsApp లో పంపండి</a>'
          if order.get("whatsapp_url") else "")
    return "".join([
        _head(page["name"] + " · యాప్", page["color"]),
        f'<div class="top"><h1>యాప్‌లో ఆర్డర్</h1><div class="k">{esc(page["name"])}</div></div>',
        _summary(page, order) if order["lines"] else "",
        '<div class="card">'
        '<div class="step"><b>1</b><span>ASKODOX యాప్ install చేయండి (ఉచితం)</span></div>'
        f'<div class="step"><b>2</b><span>యాప్‌లో Shopping లో <b>{esc(page["name"])}</b> అని వెతకండి</span></div>'
        '<div class="step"><b>3</b><span>ఆర్డర్ చేయండి — షాప్ ఒప్పుకున్నది, సిద్ధమైనది లైవ్‌లో కనిపిస్తుంది</span></div>'
        f'<a class="btn app" href="/s/{slug}/go/app">Play Store లో ASKODOX</a></div>',
        f'<div style="padding:0 12px">{wa}</div>',
        f'<p class="foot"><a href="/s/{slug}">← షాప్ పేజీకి</a></p>',
        _foot(page), "</div></body></html>",
    ])


def missing_html(off: bool = False) -> str:
    text = ("ఈ షాప్ లింక్ ఇప్పుడు ఆఫ్‌లో ఉంది · This shop link is turned off." if off
            else "ఈ షాప్ లింక్ లేదు · This shop link does not exist.")
    return (_head("ASKODOX", "#0B7A4B") + f'<div class="top"><h1>{text}</h1></div>'
            '<div class="foot">ASKODOX · askodox.com</div></div></body></html>')
