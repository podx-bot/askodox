"""Step 2 (GitHub Actions): THIS BRANCH's backend, in-process, on the real
video rows production returned (replayed as the web video search answer),
with real network for YouTube oEmbed. For each case:

  search (EN / TE text) -> enriched videos (reference, platform, embed only
  where YouTube allows, thumbnail, channel, disclosure, linked product /
  service) -> Ask ASKODOX (branch /api/videos/{id}/explain, EN or TE) ->
  the REAL production AI answer to exactly what the app sends (question +
  grounding), then a follow-up turn with history (continuity) -> the next
  step's REAL local / online / deal options (from production) -> attribution
  events and the video funnel in the branch's Command Center.

Nothing touches production data: production is only read (search and the
public assistant endpoint). The branch database is a temporary file.
"""
import json
import os
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out").resolve()
os.environ.setdefault("PODX_DATABASE_PATH", str(Path(tempfile.mkdtemp()) / "proof.db"))
os.environ.setdefault("ADMIN_SEED_KEY", "video-proof-" + os.urandom(6).hex())
sys.path.insert(0, str(HERE.parents[1] / "backend"))
sys.path.insert(0, str(HERE))

import httpx  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from cases import CASES, PRODUCTION, discover_body  # noqa: E402

capture = json.loads((OUT / "production_capture.json").read_text())

from server import app, container  # noqa: E402
from app.services.session_tokens import issue_token  # noqa: E402
from app.services.universal_ai_assistant_service import UniversalAIAssistantService as AI  # noqa: E402


class ReplayWebVideos:
    """The web video search answer production gave for this subject."""
    configured = True

    def __init__(self):
        self.by_subject = {}

    def __call__(self, query, limit):
        return []  # online pages come from production's next-step search

    def videos(self, query, limit):
        subject = query.removesuffix(" review").removesuffix(" explained").strip().lower()
        return self.by_subject.get(subject, [])


replay = ReplayWebVideos()
for label, language, text, subject, category, intent, step in CASES:
    rows = []
    for v in capture[label]["videos"]:
        rows.append({"title": v.get("title"), "url": v.get("destination_url"), "snippet": v.get("subtitle") or "",
                     "thumbnail": v.get("image_url"), "creator": v.get("source_name"), "duration": v.get("duration")})
    replay.by_subject.setdefault(subject.lower(), rows)
container.brave_web_search_provider = replay
client = TestClient(app)
owner = {"X-ASKODOX-Admin-Key": os.environ["ADMIN_SEED_KEY"]}
buyer = {"Authorization": f"Bearer {issue_token('app-video-proof-buyer', container.settings.session_token_secret)}"}
http = httpx.Client(timeout=60)

GROUNDING_RULE = ('Answer ONLY from the facts listed for each option. If a fact (price, rating, reviews, condition, '
                  'stock, specifications, distance, seller verification) is "not provided", say it is not provided '
                  'by the source -- never guess it, never say customers generally rate it well. Offer to ask the '
                  'seller for seller-only facts.')


def option_context(m):
    parts = [m["title"]]
    if m.get("subtitle"):
        parts.append(m["subtitle"])
    parts += ["price: not provided", "distance: not provided", "stock/availability: not provided",
              "rating/reviews: not provided"]
    if m.get("source_name"):
        parts.append(f"source: {m['source_name']}")
    return "; ".join(parts)


def production_ai(message, locale, history):
    for attempt in range(3):
        try:
            r = http.post(f"{PRODUCTION}/api/in-app/assistant",
                          json={"message": message, "locale": locale, "history": history, "location": "Vijayawada"})
        except httpx.HTTPError as error:
            return {"reply": "", "source": f"unreachable:{type(error).__name__}"}
        if r.status_code == 429:
            time.sleep(20)
            continue
        r.raise_for_status()
        return r.json()
    return {"reply": "", "source": "rate_limited"}


results = []
for label, language, text, subject, category, intent, step in CASES:
    case = {"label": label, "language": language, "text": text, "subject": subject}
    found = client.post("/deals/discover", json=discover_body(text, subject, category, intent, language))
    found.raise_for_status()
    body = found.json()
    videos = [m for m in body["matches"] if m.get("match_source") == "video"]
    case["trace_key"] = body["trace_key"]
    case["videos"] = [{k: v.get(k) for k in ("video_id", "title", "source_name", "duration", "platform", "embed_url",
                                             "embeddable", "image_url", "destination_url", "disclosure", "sponsored",
                                             "products", "services")} for v in videos]
    case["production_video_rows"] = len(capture[label]["videos"])
    if not videos:
        case["result"] = "no relevant videos"
        results.append(case)
        print(f"{label:15s} NO VIDEOS (production gave {case['production_video_rows']})")
        continue
    # The real AI decision the app gets for the search message itself (the
    # app renders it and routes the search with it).
    decision = production_ai(text, language, [])
    case["search_decision"] = {k: decision.get(k) for k in ("reply", "domain", "transactional", "action",
                                                          "confidence", "source", "entities")}
    time.sleep(2)
    top = videos[0]
    # Ask ASKODOX about the top video (what the app does on "Ask").
    explain = client.post(f"/api/videos/{top['video_id']}/explain",
                          json={"question": top["title"], "language": language}).json()
    case["explain"] = explain
    facts = ["The video was NOT analyzed: only its title/description are known. Do not claim what it says."]
    facts += [f'- "{line}"' for line in explain["from_source"]]
    facts.append(f"Relationship: {explain['relationship_label']} (say this when you mention it).")
    if explain.get("creator"):
        facts.append(f"Creator: {explain['creator']} (their opinion, not a verified fact).")
    facts.append("Separate what the video says from your own explanation; never invent specs, prices or results.")
    question = ("\"%s\" గురించి చెప్పండి: ధర, దూరం, నాణ్యత, అందుబాటు, రివ్యూలు" % top["title"]) if language == "te" \
        else f'Tell me more about "{top["title"]}"'
    message = f"{question}\nOption the user is asking about: {option_context(top)}\n" + "\n".join(facts) + \
              f"\n{GROUNDING_RULE}"
    history = [{"role": "user", "text": text}]
    first = production_ai(message, language, history)
    time.sleep(2)
    follow_q = "ఇది చిన్న గదికి సరిపోతుందా?" if language == "te" else "Is it worth buying, and where can I get it here?"
    history += [{"role": "user", "text": question}, {"role": "assistant", "text": first.get("reply", "")}]
    second = production_ai(follow_q, language, history)
    time.sleep(2)
    case["ai"] = {"question": question, "reply": first.get("reply"), "source": first.get("source"),
                  "follow_up": follow_q, "follow_reply": second.get("reply"), "follow_source": second.get("source"),
                  "follow_domain": second.get("domain"), "follow_action": second.get("action")}
    if AI._asks_where_to_get(follow_q):
        # Production runs main; this branch turns "where can I get it" into a
        # real search deterministically (same rule, applied to the same text).
        case["ai"]["branch_follow"] = {"reply": AI._local_search_reply(language), "action": "find_local"}
    # Attribution: the funnel the viewer reports, tied to the same reference.
    # (video_ask was already recorded once by the explain call above.)
    for event in ("video_open", "video_watch_start" if top.get("embed_url") else "video_contact",
                  {"find_local": "video_local_search", "local_service": "video_service_click"}.get(
                      step, "video_product_click")):
        client.post("/api/track", headers=buyer, json={"event": event, "ids": {"video_id": top["video_id"],
                                                                                 "search_id": body["trace_key"]},
                                                        "category": category, "language": language})
    nxt = capture[label]
    case["next"] = {"step": step, "ask": nxt["next_ask"], "segments": nxt["next_segments"],
                    "status": nxt["next_status"],
                    "options": [{k: m.get(k) for k in ("title", "segment", "match_source", "source_name", "price",
                                                       "price_verified", "distance_km", "affiliate", "sponsored",
                                                       "destination_url", "image_url", "location_label")}
                                for m in nxt["next_matches"][:6]]}
    if case["next"]["options"]:
        first_option = nxt["next_matches"][0]
        client.post("/api/track", headers=buyer, json={"event": "click", "ids": {
            "result_id": str(first_option.get("id"))[:80], "search_id": body["trace_key"],
            "video_id": top["video_id"]}, "source": "video_next_step"})
    results.append(case)
    print(f"{label:15s} videos={len(videos)} top='{top['title'][:50]}' embed={'yes' if top.get('embed_url') else 'no'} "
          f"ai={'yes' if first.get('reply') else 'NO'} follow={'yes' if second.get('reply') else 'NO'} "
          f"next_options={len(case['next']['options'])}")

funnel = client.get("/admin/cc/platform/analytics", headers=owner).json()
events = client.get("/admin/cc/platform/events?limit=1000", headers=owner).json()["items"]
proof = {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "production": PRODUCTION,
         "cases": results, "video_funnel": funnel["video_funnel"], "funnel": funnel["funnel"],
         "event_count": len(events),
         "youtube_data_api": "needs_configuration (no YOUTUBE_API_KEY in this run)"}
(OUT / "proof.json").write_text(json.dumps(proof, ensure_ascii=False, indent=1))
print("VIDEO FUNNEL:", {s["step"]: s["count"] for s in funnel["video_funnel"]})
ok = [c for c in results if c.get("videos")]
assert ok, "no case produced real videos"
