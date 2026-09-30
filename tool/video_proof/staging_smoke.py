"""Staging smoke test (GitHub Actions, open network): proves the STAGING
backend runs this branch -- not just that it answers /health -- and that
production was left alone. Read-only except the staging video funnel.

  1. /health on staging answers as ASKODOX.
  2. A real video ask (EN + TE) returns this branch's video rows: reference
     (yt_/wv_), platform, disclosure, embed only where YouTube allows it.
  3. Ask ASKODOX about the top video: the branch's honest explanation.
  4. "where can I get it here?" is a search (branch rule), never shop names.
  5. Production still answers and does NOT return branch-only video fields.
"""
import json
import os
import sys
import time

import httpx

from cases import PRODUCTION, discover_body

STAGING = sys.argv[1].rstrip("/")
assert STAGING.startswith("https://") and STAGING != PRODUCTION, "staging URL must be https and not production"
http = httpx.Client(timeout=60, headers={"User-Agent": "ASKODOX-staging-smoke/1.0"})
report = {"staging": STAGING, "checks": []}


def check(name, ok, detail):
    report["checks"].append({"check": name, "ok": bool(ok), "detail": detail})
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")


def post(base, path, body):
    for _ in range(3):
        r = http.post(f"{base}{path}", json=body)
        if r.status_code == 429:
            time.sleep(20)
            continue
        return r
    return r


health = http.get(f"{STAGING}/health").json()
check("staging /health", str(health.get("app", "")).lower().startswith(("askodox", "podx")) or health.get("status") == "ok",
      {k: health.get(k) for k in ("app", "status", "version") if k in health})

top = None
for label, lang, text, subject in (("en", "en", "Samsung 43 inch TV review videos", "samsung 43 inch tv"),
                                   ("te", "te", "శామ్‌సంగ్ 43 అంగుళాల టీవీ రివ్యూ వీడియో", "samsung 43 inch tv")):
    r = post(STAGING, "/deals/discover", discover_body(text, subject, "product", "buy", lang))
    body = r.json() if r.status_code == 200 else {}
    videos = [m for m in body.get("matches", []) if m.get("match_source") == "video"]
    branch_rows = [v for v in videos if str(v.get("video_id", "")).startswith(("yt_", "wv_")) and v.get("disclosure")]
    check(f"video ask ({label}) returns this branch's video rows", branch_rows,
          {"status": r.status_code, "videos": len(videos), "videos_status": body.get("source_status", {}).get("videos"),
           "top": [{k: v.get(k) for k in ("video_id", "title", "platform", "embeddable", "embed_url", "disclosure")}
                   for v in branch_rows[:2]]})
    top = top or (branch_rows[0] if branch_rows else None)
    time.sleep(3)

if top:
    r = post(STAGING, f"/api/videos/{top['video_id']}/explain", {"question": top["title"], "language": "en"})
    ex = r.json() if r.status_code == 200 else {}
    check("Ask ASKODOX about the video (branch explain)", r.status_code == 200 and ex.get("relationship_label"),
          {"status": r.status_code, "answer": str(ex.get("answer", ""))[:200], "label": ex.get("relationship_label")})
    time.sleep(2)

r = post(STAGING, "/api/in-app/assistant", {"message": "Is it worth buying, and where can I get it here?",
                                            "locale": "en", "history": [
                                                {"role": "user", "text": "Samsung 43 inch TV review videos"}],
                                            "location": "Vijayawada"})
ai = r.json() if r.status_code == 200 else {}
shops = [s for s in ("Poorvika", "Reliance", "Croma", "Lot Mobile", "Bajaj") if s in str(ai.get("reply", ""))]
check("'where can I get it here' is a search, no shop names from memory",
      ai.get("transactional") is True and not shops and ai.get("source") != "fallback",
      {"status": r.status_code, "action": ai.get("action"), "transactional": ai.get("transactional"),
       "reply": str(ai.get("reply", ""))[:200], "source": ai.get("source"), "shops_named": shops})

ready = http.get(f"{STAGING}/readiness").json()
integrations = ready.get("integrations") or {}
live = sorted(p for p, st in integrations.items() if st == "LIVE")
check("staging integrations are in safe states (nothing LIVE without real credentials; WhatsApp off on staging)",
      ready.get("environment") == "staging" and integrations and not live
      and integrations.get("whatsapp_cloud") in ("NEEDS_CONFIGURATION", "DISABLED", "MOCK"),
      {"environment": ready.get("environment"), "integrations": integrations, "live": live})

# Every API the app's services call exists on staging (a 4xx for an empty
# request is fine; 404/5xx means the app would break).
for method, path, body in (("POST", "/api/in-app/voice/transcribe", None), ("POST", "/api/in-app/voice/speak", {}),
                           ("POST", "/vision/analyze", {}), ("POST", "/vision/analyze-video", {}),
                           ("POST", "/api/in-app/support/escalate", {}), ("POST", "/api/attachments/analyze", None)):
    r = http.request(method, f"{STAGING}{path}", json=body) if body is not None else http.request(method, f"{STAGING}{path}")
    check(f"app route {method} {path} is served", r.status_code != 404 and r.status_code < 500, {"status": r.status_code})
place = http.get(f"{STAGING}/api/discover/place", params={"latitude": 16.5062, "longitude": 80.648})
pj = place.json() if place.status_code == 200 else {}
check("place naming (GET /api/discover/place) answers on staging", place.status_code == 200,
      {"status": place.status_code, "resolved": pj.get("resolved"), "name": pj.get("name") or pj.get("locality")})

# The custom domain and the Railway domain are the same staging service.
alt = os.environ.get("ALT_STAGING_URL", "").rstrip("/")
if alt and alt != STAGING:
    a, b = http.get(f"{STAGING}/health").json(), http.get(f"{alt}/health").json()
    ra, rb = http.get(f"{STAGING}/readiness").json(), http.get(f"{alt}/readiness").json()
    check(f"{STAGING} and {alt} are the same staging service",
          a.get("commit") and a.get("commit") == b.get("commit") and ra.get("environment") == rb.get("environment") == "staging",
          {"commit": [a.get("commit"), b.get("commit")], "environment": [ra.get("environment"), rb.get("environment")]})
root = http.get(f"{STAGING}/").json()
check("root answers as ASKODOX", root.get("app") == "ASKODOX", root)

prod = http.get(f"{PRODUCTION}/health")
check("production still answers (untouched)", prod.status_code == 200, {"status": prod.status_code})
r = post(PRODUCTION, "/deals/discover", discover_body("Samsung 43 inch TV review videos", "samsung 43 inch tv",
                                                      "product", "buy", "en"))
pv = [m for m in (r.json().get("matches", []) if r.status_code == 200 else []) if m.get("match_source") == "video"]
check("production still runs main (no branch-only video fields)",
      not any(str(v.get("video_id", "")).startswith(("yt_", "wv_")) for v in pv),
      {"status": r.status_code, "videos": len(pv)})

print(json.dumps(report, ensure_ascii=False, indent=1))
failed = [c["check"] for c in report["checks"] if not c["ok"]]
assert not failed, f"failed: {failed}"
