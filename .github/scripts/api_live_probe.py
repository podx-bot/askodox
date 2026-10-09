"""Live API probe for ASKODOX (stdlib only, no secrets).

STAGING (own database + its own provider keys) gets the functional probes:
real AI conversation, search, voice, attachments, places, error handling,
auth refusals and the admin sign-in lockout. PRODUCTION gets read-only GETs
and requests WITHOUT credentials only (expected refusals) -- nothing there is
written, nothing is sent to customers, no payment is made.

Output: one `PROBE {...}` JSON line per check (status codes, counts, latency,
short reply snippets) and a summary. Credentials are never used or printed.
"""
from __future__ import annotations

import base64
import json
import struct
import time
import urllib.error
import urllib.request
import uuid
import zlib

STAGING = "https://staging.askodox.com"
PRODUCTION = "https://podx-ai-connect-production-3279.up.railway.app"
UA = {"User-Agent": "ASKODOX-api-probe"}
VIJAYAWADA = (16.5062, 80.6480)
RESULTS: list[dict] = []


def call(base, method, path, body=None, headers=None, raw=None, ctype="application/json", timeout=120):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    hdrs = {**UA, **(headers or {})}
    if data is not None:
        hdrs.setdefault("Content-Type", ctype)
    req = urllib.request.Request(base + path, data=data, headers=hdrs, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload, code, rh = r.read(), r.status, dict(r.headers)
    except urllib.error.HTTPError as e:
        payload, code, rh = e.read(), e.code, dict(e.headers or {})
    except Exception as e:  # timeout / connection
        return 0, {"error": type(e).__name__}, {}, int((time.monotonic() - started) * 1000)
    ms = int((time.monotonic() - started) * 1000)
    try:
        parsed = json.loads(payload) if payload and payload[:1] in (b"{", b"[") else payload
    except Exception:
        parsed = payload
    return code, parsed, rh, ms


def record(env, area, name, ok, http, ms, **evidence):
    status = "PASS" if ok is True else ("FAIL" if ok is False else str(ok))
    row = {"env": env, "area": area, "name": name, "status": status, "http": http, "ms": ms, **evidence}
    RESULTS.append(row)
    print("PROBE " + json.dumps(row, ensure_ascii=False), flush=True)


def snippet(text, n=160):
    return " ".join(str(text or "").split())[:n]


def png_bytes(w=48, h=48, rgb=(220, 30, 30)):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def pdf_bytes(text):
    stream = f"BT /F1 18 Tf 50 750 Td ({text}) Tj ET".encode()
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
            b"/Resources << /Font << /F1 5 0 R >> >> >>",
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    out, offs = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % o for o in offs)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    return out


def multipart(fields, files):
    boundary = "----askodox" + uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    for k, (fname, ctype, data) in files.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"; filename="{fname}"\r\n'
                     f'Content-Type: {ctype}\r\n\r\n'.encode() + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def sections_of(data):
    secs = data.get("sections") if isinstance(data, dict) else None
    out = {}
    for sec in (secs if isinstance(secs, list) else []):
        if isinstance(sec, dict):
            out[str(sec.get("kind"))] = {"count": sec.get("count", len(sec.get("item_ids") or [])),
                                         "status": sec.get("status"), "empty_reason": sec.get("empty_reason")}
    return out


def card_overview(rows):
    rows = [r for r in rows if isinstance(r, dict)]
    sources = {}
    for r in rows:
        sources[str(r.get("source") or r.get("segment") or "?")] = sources.get(str(r.get("source") or r.get("segment") or "?"), 0) + 1
    return {"sources": sources, "first_keys": sorted(rows[0])[:40] if rows else [],
            "titles": [snippet(r.get("title"), 60) for r in rows[:3]]}


def card_quality(rows):
    rows = [r for r in rows if isinstance(r, dict)]
    def has(*keys):
        return sum(1 for r in rows if any(r.get(k) or (r.get("metadata") or {}).get(k) for k in keys))
    return {"cards": len(rows), "with_title": has("title"), "with_price": has("price", "price_value", "offer_price"),
            "with_image": has("image_url", "image", "thumbnail_url", "thumbnail"),
            "with_link": has("url", "link", "source_url", "product_url", "website", "open_url", "maps_url",
                             "action_url", "video_url", "watch_url", "apply_url"),
            "price_unverified": sum(1 for r in rows if r.get("price_verified") is False)}


def integration_states(d):
    out = {}
    def walk(node, depth=0):
        if depth > 3:
            return
        if isinstance(node, list):
            for r in node:
                if isinstance(r, dict) and (r.get("state") or r.get("status")):
                    name = r.get("key") or r.get("name") or r.get("id") or r.get("integration") or r.get("label")
                    out[str(name)] = r.get("state") or r.get("status")
                else:
                    walk(r, depth + 1)
        elif isinstance(node, dict):
            for k, v in node.items():
                if isinstance(v, dict) and isinstance(v.get("state") or v.get("status"), str):
                    out[str(k)] = v.get("state") or v.get("status")
                else:
                    walk(v, depth + 1)
    walk(d)
    return out


def assistant(base, message, locale="en", history=None, **extra):
    body = {"message": message, "locale": locale, "history": history or [], "location": "Vijayawada", **extra}
    return call(base, "POST", "/api/in-app/assistant", body)


def staging():
    env = "staging"
    import os
    want = os.environ.get("WANT", "")[:7]
    for _ in range(40):  # staging redeploys on every push to its branch
        code, d, _, _ = call(STAGING, "GET", "/health", timeout=30)
        live = str((d or {}).get("commit", "")) if isinstance(d, dict) else ""
        print("DEPLOYED_COMMIT:", live[:12], "(want", want + ")", flush=True)
        if not want or live.startswith(want):
            break
        time.sleep(30)
    code, d, _, ms = call(STAGING, "GET", "/health")
    record(env, "platform", "GET /health", code == 200, code, ms, commit=str((d or {}).get("commit", ""))[:12]
           if isinstance(d, dict) else "")
    code, d, _, ms = call(STAGING, "GET", "/health/integrations")
    record(env, "integrations", "GET /health/integrations", code == 200, code, ms, states=integration_states(d))
    code, d, _, ms = call(STAGING, "GET", "/health/search")
    record(env, "search", "GET /health/search", code == 200, code, ms,
           brave=(d or {}).get("state") or (d or {}).get("brave") if isinstance(d, dict) else None,
           fallbacks=(d or {}).get("fallbacks") if isinstance(d, dict) else None,
           keys=sorted(d)[:12] if isinstance(d, dict) else None)
    code, d, _, ms = call(STAGING, "GET", "/health/maps")
    record(env, "location", "GET /health/maps", code == 200 and bool((d or {}).get("all_ok")), code, ms,
           all_ok=(d or {}).get("all_ok") if isinstance(d, dict) else None,
           apis={k: (v.get("ok") if isinstance(v, dict) else v) for k, v in ((d or {}).get("apis") or {}).items()}
           if isinstance(d, dict) else None)
    code, d, _, ms = call(STAGING, "GET", "/debug/voice-readiness")
    record(env, "voice", "GET /debug/voice-readiness", code == 200, code, ms,
           checks=(d or {}).get("checks") if isinstance(d, dict) else None)
    code, d, _, ms = call(STAGING, "GET", "/api/flags")
    flags = (d or {}).get("flags") if isinstance(d, dict) else None
    record(env, "flags", "GET /api/flags", code == 200 and isinstance(flags, dict), code, ms,
           flag_count=len(flags or {}), off=[k for k, v in (flags or {}).items() if v is False][:15])

    # ---- conversation / reasoning -------------------------------------------
    hist, turns = [], ["I want an AC", "Budget 40000 rupees, split AC", "Room is 150 sq ft, any brand is fine"]
    for i, t in enumerate(turns, 1):
        code, d, _, ms = assistant(STAGING, t, history=hist)
        d = d if isinstance(d, dict) else {}
        expect = (d.get("search_ready") is False and bool(d.get("next_question"))) if i == 1 else \
            (d.get("search_ready") is True) if i == 3 else (code == 200)
        record(env, "conversation", f"AC continuity turn {i}", code == 200 and expect, code, ms,
               mode=d.get("mode"), search_ready=d.get("search_ready"), next_q=snippet(d.get("next_question"), 90),
               subject=d.get("search_subject"), source=d.get("source"), reply=snippet(d.get("reply")))
        hist += [{"role": "user", "text": t}, {"role": "assistant", "text": d.get("reply") or ""}]
    code, d, _, ms = assistant(STAGING, "నాకు ఒక ఐరన్ బీరువా కావాలి", locale="te")
    reply = (d or {}).get("reply", "") if isinstance(d, dict) else ""
    telugu = sum(1 for ch in reply if "ఀ" <= ch <= "౿")
    record(env, "conversation", "Telugu request -> Telugu reply", code == 200 and telugu > 10, code, ms,
           telugu_chars=telugu, reply=snippet(reply, 120))
    q = "Should I buy a 1.5 ton or 2 ton AC for a 180 sq ft room on the top floor?"
    code, d, _, ms = assistant(STAGING, q)
    d = d if isinstance(d, dict) else {}
    tags = any(t in (d.get("reply") or "") for t in ("[ok]", "[caution]", "[risk]"))
    record(env, "conversation", "Advice mode, no search; old-app request has no raw tags",
           code == 200 and d.get("mode") == "advice" and not d.get("search_ready") and not tags, code, ms,
           mode=d.get("mode"), search_ready=d.get("search_ready"), raw_tags=tags)
    code, d, _, ms = assistant(STAGING, q, capabilities=["meaning_tags"])
    d = d if isinstance(d, dict) else {}
    record(env, "conversation", "APK 1314 capability: meaning tags allowed", code == 200, code, ms,
           tags_present=any(t in (d.get("reply") or "") for t in ("[ok]", "[caution]", "[risk]")))
    h2 = []
    for t in ("I want a Maruti Swift under 7 lakh in Vijayawada", "Actually show Tata instead of Maruti"):
        code, d, _, ms = assistant(STAGING, t, history=h2)
        h2 += [{"role": "user", "text": t}, {"role": "assistant", "text": (d or {}).get("reply", "") if isinstance(d, dict) else ""}]
    facts = json.dumps(((d or {}).get("state") or {}).get("facts") or {}, ensure_ascii=False).lower() if isinstance(d, dict) else ""
    record(env, "conversation", "Context: brand change Maruti -> Tata", code == 200 and "tata" in facts, code, ms,
           facts=snippet(facts, 200), subject=(d or {}).get("search_subject") if isinstance(d, dict) else None)

    # ---- universal search ----------------------------------------------------
    lat, lon = VIJAYAWADA
    def discover(text, subject, **extra):
        body = {"user_id": "guest", "raw_text": text, "intent": "buy", "subject": subject, "category": "general",
                "location": {"label": "Vijayawada", "latitude": lat, "longitude": lon, "radius_km": 10},
                "party_a": {"side": "demand"}, "party_b": {"side": "supply"}, "trace": {"query": text}, **extra}
        return call(STAGING, "POST", "/deals/discover", body)
    for name, text, subject, want in [
        ("Product search: 1.5 ton split AC", "1.5 ton split AC under 40000", "1.5 ton split AC", None),
        ("Videos: phone review videos", "Samsung Galaxy S24 review videos", "Samsung Galaxy S24 review videos", "videos"),
        ("Jobs: delivery boy jobs", "delivery boy jobs in Vijayawada", "delivery boy jobs", "jobs"),
        ("Service nearby: AC repair", "AC repair near me", "AC repair", "local"),
    ]:
        code, d, _, ms = discover(text, subject)
        d = d if isinstance(d, dict) else {}
        secs = sections_of(d)
        rows = d.get("matches") or []
        ok = code == 200 and (len(rows) > 0 if want is None else (secs.get(want) or {}).get("count", 0) > 0)
        ans = d.get("answer") if isinstance(d.get("answer"), dict) else {}
        record(env, "search", name, ok, code, ms, sections=secs, quality=card_quality(rows),
               overview=card_overview(rows), answer={k: ans.get(k) for k in ("count", "checked", "unavailable",
                                                                             "may_claim_results")})
    code, d, _, ms = call(STAGING, "POST", "/deals/discover", {
        "user_id": "guest", "raw_text": "AC repair near me", "intent": "buy", "subject": "AC repair",
        "category": "general", "party_a": {"side": "demand"}, "party_b": {"side": "supply"},
        "trace": {"query": "AC repair near me"}})
    secs = sections_of(d if isinstance(d, dict) else {})
    record(env, "search", "Nearby without location -> honest needs_location, no country-wide search",
           code == 200, code, ms, sections=secs)

    # ---- places / location ---------------------------------------------------
    code, d, _, ms = call(STAGING, "GET", f"/api/discover/place?latitude={lat}&longitude={lon}")
    record(env, "location", "Reverse geocode (current place name)", code == 200, code, ms,
           label=snippet((d or {}).get("label") or (d or {}).get("name") if isinstance(d, dict) else "", 80))
    code, d, _, ms = call(STAGING, "GET", f"/api/discover/places?q=AC%20repair&latitude={lat}&longitude={lon}")
    items = (d or {}).get("places") or (d or {}).get("items") or [] if isinstance(d, dict) else []
    record(env, "location", "Nearby places search", code == 200 and len(items) > 0, code, ms, places=len(items))
    code, d, _, ms = call(STAGING, "GET", f"/api/discover/junction?latitude={lat}&longitude={lon}")
    record(env, "location", "Nearest junction", code == 200, code, ms,
           junction=snippet((d or {}).get("name") or (d or {}).get("status") if isinstance(d, dict) else "", 80))
    code, d, _, ms = call(STAGING, "GET", "/api/taxonomy/resolve?q=AC%20repair")
    record(env, "search", "Taxonomy resolve", code == 200, code, ms,
           path=(d or {}).get("path") if isinstance(d, dict) else None)

    # ---- voice: Sarvam TTS -> STT round trip -----------------------------------
    for lang, text in (("te", "నమస్కారం, మీకు ఏ సహాయం కావాలి?"), ("en", "Hello, how can I help you today?")):
        code, audio, rh, ms = call(STAGING, "POST", "/api/in-app/voice/speak", {"text": text, "voice": "automatic"})
        got = code == 200 and isinstance(audio, (bytes, bytearray)) and len(audio) > 1000
        record(env, "voice", f"Sarvam TTS ({lang})", got, code, ms, bytes=len(audio) if got else 0,
               mime=rh.get("Content-Type") or rh.get("content-type"),
               language=rh.get("X-ASKODOX-TTS-Language") or rh.get("x-askodox-tts-language"),
               detail=None if got else snippet(audio if isinstance(audio, (str, dict)) else "", 120))
        if got:
            mime = (rh.get("Content-Type") or rh.get("content-type") or "audio/ogg").split(";")[0]
            ext = {"audio/ogg": "ogg", "audio/mpeg": "mp3", "audio/wav": "wav", "audio/x-wav": "wav"}.get(mime, "ogg")
            body, ctype = multipart({"locale": lang}, {"audio": (f"probe.{ext}", mime, bytes(audio))})
            code, d, _, ms = call(STAGING, "POST", "/api/in-app/voice/transcribe", raw=body, ctype=ctype)
            d = d if isinstance(d, dict) else {}
            transcript = str(d.get("text") or d.get("transcript") or "")
            record(env, "voice", f"Sarvam STT round trip ({lang})", code == 200 and len(transcript) > 3, code, ms,
                   transcript=snippet(transcript, 80), language=d.get("language") or d.get("language_code"),
                   provider=d.get("provider") or d.get("path"))

    # ---- attachments / vision / documents -------------------------------------
    for name, fname, mime, data, text in (
        ("Image (vision)", "red.png", "image/png", png_bytes(), "What colour is this?"),
        ("Document (PDF)", "invoice.pdf", "application/pdf", pdf_bytes("Invoice 1042 Total Rs 1500 Paid"), "What is the total?"),
    ):
        code, d, _, ms = call(STAGING, "POST", "/api/attachments/analyze", {
            "file_base64": base64.b64encode(data).decode(), "filename": fname, "mime_type": mime,
            "user_text": text, "language": "en"})
        d = d if isinstance(d, dict) else {}
        facts = d.get("facts") if isinstance(d.get("facts"), dict) else {}
        und = d.get("understanding")
        record(env, "attachments", name, code == 200 and d.get("status") not in ("failed", "error"), code, ms,
               status=d.get("status"), fact_keys=sorted(facts)[:15],
               understanding=snippet(json.dumps(und, ensure_ascii=False) if not isinstance(und, str) else und, 220))

    # ---- errors / validation ---------------------------------------------------
    for name, method, path, body, raw, ctype, want in (
        ("Assistant empty message -> 422", "POST", "/api/in-app/assistant", {"message": ""}, None, None, (422,)),
        ("TTS text too long -> 422", "POST", "/api/in-app/voice/speak", {"text": "x" * 2600}, None, None, (422,)),
        ("Attachment invalid base64 -> 4xx", "POST", "/api/attachments/analyze", {"file_base64": "!!!"}, None, None, (400, 415, 422)),
        ("Unknown route -> 404", "GET", "/api/does-not-exist", None, None, None, (404,)),
        ("Payment webhook with bad signature -> refused", "POST", "/api/payments/webhook/razorpay",
         {"event": "payment.captured"}, None, None, (400, 401, 403, 404, 422)),
    ):
        code, d, _, ms = call(STAGING, method, path, body)
        record(env, "errors", name, code in want, code, ms)
    body, ctype = multipart({"locale": "en"}, {"audio": ("empty.m4a", "audio/mp4", b"")})
    code, d, _, ms = call(STAGING, "POST", "/api/in-app/voice/transcribe", raw=body, ctype=ctype)
    record(env, "errors", "Empty audio -> 400", code == 400, code, ms)

    # ---- authorization ---------------------------------------------------------
    bogus = {"Authorization": "Bearer not-a-real-token"}
    for name, method, path, hdr, want in (
        ("Profile memory without sign-in", "GET", "/api/me/memory", None, (401,)),
        ("Profile memory with forged token", "GET", "/api/me/memory", bogus, (401,)),
        ("Provider leads without sign-in", "GET", "/deals/leads", None, (401,)),
        ("Orders without sign-in", "GET", "/api/orders/mine", None, (401,)),
        ("My Creations without sign-in", "GET", "/api/business/creations", None, (401,)),
        ("Notification settings without sign-in", "GET", "/api/me/notification-settings", None, (401,)),
        ("Admin health without key", "GET", "/admin/cc/health", None, (401,)),
        ("Admin release gate without key", "GET", "/admin/cc/release-gate", None, (401,)),
        ("Admin API billing without key", "GET", "/admin/cc/api-billing", None, (401,)),
        ("Admin audit log without key", "GET", "/admin/cc/audit", None, (401,)),
        ("Backup export without key", "POST", "/admin/cc/backup/export", None, (401,)),
    ):
        code, d, _, ms = call(STAGING, method, path, {"passphrase": "x" * 20} if method == "POST" else None, hdr)
        record(env, "auth", name, code in want, code, ms)
    codes = []
    for _ in range(11):
        code, *_ = call(STAGING, "GET", "/admin/cc/health", headers={"X-ASKODOX-Admin-Key": "wrong-" + uuid.uuid4().hex})
        codes.append(code)
    record(env, "rate_limit", "Admin sign-in lockout after 10 wrong keys", codes[-1] == 429 and set(codes[:10]) == {401},
           codes[-1], 0, sequence=codes)
    code, page, _, ms = call(STAGING, "GET", "/admin/backup")
    record(env, "backup", "Backup page served, holds no data", code == 200 and b"passphrase" in (page if isinstance(page, bytes) else b""),
           code, ms)
    code, page, _, ms = call(STAGING, "GET", "/chat")
    record(env, "web", "Web chat page", code == 200, code, ms)


def production():
    env = "production"
    for name, path, check in (
        ("GET /health", "/health", lambda c, d: c == 200),
        ("GET /health/integrations", "/health/integrations", lambda c, d: c == 200),
        ("GET /health/search", "/health/search", lambda c, d: c == 200),
        ("GET /api/flags", "/api/flags", lambda c, d: c == 200),
        ("Backup page", "/admin/backup", lambda c, d: c == 200),
        ("Web chat page", "/chat", lambda c, d: c == 200),
    ):
        code, d, _, ms = call(PRODUCTION, "GET", path)
        extra = {}
        if path == "/health" and isinstance(d, dict):
            extra["commit"] = str(d.get("commit", ""))[:12]
        if path == "/health/search" and isinstance(d, dict):
            extra["fallbacks"] = d.get("fallbacks")
            extra["keys"] = sorted(d)[:12]
        if path == "/health/integrations" and isinstance(d, dict):
            rows = d.get("integrations") or d.get("rows") or d.get("items")
            extra["states"] = integration_states(d)
        record(env, "readonly", name, check(code, d), code, ms, **extra)
    for name, method, path in (
        ("Profile memory without sign-in -> 401", "GET", "/api/me/memory"),
        ("Provider leads without sign-in -> 401", "GET", "/deals/leads"),
        ("Admin health without key -> 401", "GET", "/admin/cc/health"),
        ("Backup export without key -> 401", "POST", "/admin/cc/backup/export"),
    ):
        code, d, _, ms = call(PRODUCTION, method, path, {"passphrase": "x" * 20} if method == "POST" else None)
        record(env, "auth", name, code == 401, code, ms)


if __name__ == "__main__":
    for target in (staging, production):
        try:
            target()
        except Exception as exc:  # report, never hide
            record(target.__name__, "probe", "probe crashed", False, 0, 0, error=f"{type(exc).__name__}: {exc}")
    totals: dict = {}
    for r in RESULTS:
        totals.setdefault(r["env"], {}).setdefault(r["status"], 0)
        totals[r["env"]][r["status"]] += 1
    slow = [f'{r["env"]}:{r["name"]} {r["ms"]}ms' for r in RESULTS if r["ms"] > 20000]
    print("SUMMARY " + json.dumps({"totals": totals, "slow_over_20s": slow}, ensure_ascii=False))
