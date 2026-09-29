"""Step 1 (GitHub Actions, open network): real video rows from PRODUCTION's
live web video search (Brave, key held by Railway) for every case, plus the
real local / online / deal options for the case's next step. Read-only public
endpoint, spaced well under its rate limit. Nothing is written anywhere."""
import json
import sys
import time
from pathlib import Path

import httpx

from cases import CASES, PRODUCTION, discover_body

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
OUT.mkdir(parents=True, exist_ok=True)
client = httpx.Client(timeout=60, headers={"User-Agent": "ASKODOX-video-proof/1.0"})


def discover(text, subject, category, intent, language):
    for attempt in range(3):
        r = client.post(f"{PRODUCTION}/deals/discover", json=discover_body(text, subject, category, intent, language))
        if r.status_code == 429:
            time.sleep(20)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("rate limited")


NEXT_ASK = {"find_local": "{s} near me", "deals": "{s} offers", "local_service": "{s} service near me",
            "reviews": "{s} reviews", "used": "used {s}"}
captured = {}
for label, language, text, subject, category, intent, step in CASES:
    # Production's own "wants videos" detector reads English words, so the
    # source query carries "review video"; the branch run uses the real text.
    # Production (main) never searches videos for SERVICE needs (this branch
    # changes that), so service cases take their real video rows from a
    # product-category source query for the same subject; the branch run
    # then treats them as the service need.
    source_category, source_intent = ("product", "buy") if category == "service" else (category, intent)
    source = discover(f"{subject} review video", subject, source_category, source_intent, "en")
    videos = [m for m in source["matches"] if m.get("match_source") == "video"]
    time.sleep(3)
    ask = NEXT_ASK[step].format(s=subject)
    follow = discover(ask, subject if step != "used" else f"used {subject}", category, intent, language)
    time.sleep(3)
    captured[label] = {
        "videos": videos, "video_status": source.get("source_status", {}).get("videos"),
        "next_step": step, "next_ask": ask, "next_matches": follow["matches"][:12],
        "next_segments": follow.get("segments"), "next_status": follow.get("source_status"),
    }
    print(f"{label:15s} videos={len(videos):2d} status={captured[label]['video_status']} "
          f"next='{ask}' options={len(follow['matches'])} segments={follow.get('segments')}")
(OUT / "production_capture.json").write_text(json.dumps(captured, ensure_ascii=False, indent=1))
total = sum(len(c["videos"]) for c in captured.values())
print("TOTAL REAL VIDEOS FROM PRODUCTION:", total)
assert total > 0, "production returned no videos -- check Brave / the videos flag"
