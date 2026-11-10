# ASKODOX — Brain gap analysis (Brain Phase Zero audit, 2026-11-10)

Spec: "Hybrid Cognitive Intelligence Brain" (owner, 2026-11-10). For each part: what exists, the gap, the decision
(REUSE / EXTEND / ADD / NOT NOW).

| Spec part | Exists | Gap | Decision |
|---|---|---|---|
| Central orchestrator | `decide()` already picks mode (chat / commerce / advice / follow_up) and runs lookups | no explicit plan of which modules ran, no trace, no router | EXTEND: a thin orchestrator around `decide()` that records the plan (`brain_runs`) |
| 1 Language | good | none material | REUSE |
| 2 Psychology knowledge | none | whole module | ADD: `psychology_knowledge` resource (evidence grade A-D, references, limits, alternative explanations), staff-reviewed before LIVE |
| 3 Emotional | none | whole module; also no distress path in main chat | ADD inside the same decision call (`signals`), plus a fixed safety reply |
| 4 Behaviour | none | whole module | ADD inside the same call; possibilities only, never stored |
| 5 Memory | profile memory, backup, advice ledger, consent, delete | relevance scoring is simple; no expiry rule | EXTEND lightly (expiry + relevance by content words); no second memory system |
| 6 Research | live lookup quick / deep, honesty guard, sources footer | sources and "verified" are not shown in the app; no source-quality grade | EXTEND: send sources + verified flag as fields; app shows them |
| 7 Decision | advice mode, advisor | no structured comparison output | EXTEND: optional `decision` block (options, for / against, risk) rendered as a small table |
| 8 Reasoning | guidance rules | no deeper model for hard questions | ADD: router escalates to a DEEP model (owner approval for the paid model) |
| 9 Creative | image studio; ideas come from the same model | none material | REUSE |
| 10 Learning | chips, colours, rich replies | no knowledge-level adaptation | NOT NOW (low value vs risk of guessing a "level") |
| 11 Safety | fraud, price truth, listing quality, masking | prompt-injection guard; health / legal / finance safeguard wording; distress path | ADD (injection fence, safety rules, distress reply) |
| 12 Self-improvement | corrections loop, knowledge gaps, health, alerts (PR #299) | no benchmark, no prompt versions, no old-vs-new comparison | ADD: benchmark set + runner + prompt versions + dashboard |
| Verification engine | honesty guard, price reconcile | no check that new Brain fields are safe / well-formed | ADD: strict validation of new fields |
| Model strategy | env-configured Gemini -> OpenAI | no registry, no routing, no ceiling | ADD: `model_registry` + router + daily cost ceiling |
| Economics | meter, credits, billing estimates | no per-turn cost, no cache, no ceiling | ADD: per-turn cost in `brain_runs`, exact-question cache for non-personal answers, ceiling |
| Mobile | chat renders reply, chips, colours | perspective / sources / confidence not shown | EXTEND the existing reply widget; no new screen |
| Admin | health, incidents, billing, flags | no Brain view | ADD: Brain Dashboard + Benchmark pages in the Command Center |
| Owner extras | — | Brain Dashboard, Brain Benchmark, Safe Learning | ADD (Safe Learning is already the rule in `answer_corrections`: staff-approved, masked, never per-user data) |

## Where the spec does not fit this project (and what is done instead)
1. **Twelve module files, each a model call** would multiply cost and latency by several times. Instead: modules
   are *sections of one structured decision* (one call), with a second call only for DEEP / advice turns.
2. **Postgres, JSONB, foreign keys, Redis, vector search**: none exist. The Brain uses SQLite tables + schema
   resources; knowledge retrieval by tags / content words (the method `answer_corrections` already uses).
   Embeddings can be added later if retrieval quality proves insufficient.
3. **`/api/v1/brain/*` endpoints**: a second chat endpoint would be a duplicate chat system. The Brain stays behind
   `POST /api/in-app/assistant`; only `feedback` (exists), `status` and `preferences` are added.
4. **"Always-on psychology analysis"**: done as a lightweight part of the same call, discarded after the turn.
   Storing or logging it per user is refused (privacy rules in the security audit).
5. **Automated self-improvement**: the system proposes (benchmark results, prompt versions); a person approves.
   Nothing changes production prompts, routing or code by itself.

## Biggest risks
- Psychology wording that sounds like a diagnosis, or repeated unwanted "insights" -> strict thresholds, one
  insight at most per several turns, user switch, benchmark cases for "must NOT surface".
- Cost creep from DEEP mode -> router rules + daily ceiling + dashboard.
- Regressions in the 7,275-line chat screen -> additive optional fields only, behind a capability and a flag.
- Answer quality cannot be judged by tests alone -> benchmark needs human-graded expected points, in Telugu too.
