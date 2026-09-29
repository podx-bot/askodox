"""Step 4: the human-readable proof (docs/video_proof/README.md)."""
import json
import sys
from pathlib import Path

OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "out")
RUN = sys.argv[2] if len(sys.argv) > 2 else ""
proof = json.loads((OUT / "proof.json").read_text())
renders = sorted(p.name for p in (OUT / "renders").glob("*.png")) if (OUT / "renders").exists() else []


def cut(text, n=420):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


lines = ["# Real video content proof", "",
         f"Generated {proof['generated_at']} by `.github/workflows/video-real-content-proof.yml`"
         + (f" (run {RUN})" if RUN else "") + ".", "",
         "* Video rows: **real**, from production's live web video search (Brave) -- replayed into this branch's "
         "pipeline, which adds references, YouTube oEmbed checks (live network), linking and disclosures.",
         "* AI answers: **real**, from the production assistant (`/api/in-app/assistant`) given exactly what the app "
         "sends (question + grounding from this branch's explain).",
         "* Next-step options: **real**, from production's discovery for the step's text.",
         f"* YouTube Data API: {proof['youtube_data_api']}.", "",
         "| Case | Lang | Videos | Top video | Channel | Plays in app | Disclosure | AI answer | Follow-up | Next step → options |",
         "|---|---|---|---|---|---|---|---|---|---|"]
for c in proof["cases"]:
    vids = c.get("videos") or []
    if not vids:
        lines.append(f"| {c['label']} | {c['language']} | 0 (production gave {c.get('production_video_rows')}) "
                     f"| — | — | — | — | — | — | — |")
        continue
    top = vids[0]
    ai = c.get("ai") or {}
    nxt = c.get("next") or {}
    lines.append("| {label} | {lang} | {n} | [{title}]({url}) | {ch} | {embed} | {disc} | {ai} | {fol} | {ask} → {opts} ({segs}) |".format(
        label=c["label"], lang=c["language"], n=len(vids), title=cut(top["title"], 60).replace("|", "/"),
        url=top["destination_url"], ch=cut(top.get("source_name"), 30), disc=top.get("disclosure"),
        embed="yes (official YouTube embed)" if top.get("embed_url") else f"no -> opens in {top.get('platform')}",
        ai="yes" if ai.get("reply") else f"no ({ai.get('source')})",
        fol="yes" if ai.get("follow_reply") else f"no ({ai.get('follow_source')})",
        ask=nxt.get("ask"), opts=len(nxt.get("options") or []), segs=", ".join(nxt.get("segments") or [])))
lines += ["", "## Conversations (real AI answers)", ""]
for c in proof["cases"]:
    if not c.get("ai"):
        continue
    ai, ex = c["ai"], c.get("explain") or {}
    lines += [f"### {c['label']} ({c['language']}) -- \"{c['text']}\"", "",
              f"**Video:** {c['videos'][0]['title']} -- {c['videos'][0].get('source_name') or ''} "
              f"({c['videos'][0]['destination_url']})", "",
              f"**ASKODOX explain (branch):** {cut(ex.get('answer'))}  ", f"Quoted from source: {cut(' / '.join(ex.get('from_source') or []), 300)}  ",
              f"Label: {ex.get('relationship_label')}", "",
              f"**User:** {ai['question']}", "", f"**ASKODOX AI (production):** {cut(ai.get('reply'), 900)}", "",
              f"**User (follow-up, same conversation):** {ai['follow_up']}", "",
              f"**ASKODOX AI:** {cut(ai.get('follow_reply'), 700)}", "",
              f"**Next step:** \"{c['next']['ask']}\" → " + "; ".join(
                  f"{o['title']} [{o.get('segment') or o.get('match_source')}]" for o in c["next"]["options"][:4]), ""]
lines += ["## Attribution (branch Command Center)", "",
          "Video funnel: " + ", ".join(f"{s['step']} {s['count']}" for s in proof["video_funnel"]), "",
          "Commerce funnel: " + ", ".join(f"{s['step']} {s['count']}" for s in proof["funnel"]), ""]
if renders:
    lines += ["## App renders (real rows, thumbnails and AI answers)", ""]
    lines += [f"![{r}](renders/{r})" for r in renders]
(OUT / "README.md").write_text("\n".join(lines) + "\n")
print("\n".join(lines[:40]))
