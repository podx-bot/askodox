# ASKODOX — Brain implementation plan (Brain Phase Zero audit, 2026-11-10)

Principle: ONE brain, extended. Additive, behind the flag `brain.v2` (default OFF), every stage a separate PR,
nothing merged or deployed without the owner's "1". The existing assistant keeps working with the flag off.

## Target shape (adapted to this repository)

```
POST /api/in-app/assistant
  -> orchestrator (new, thin): safety pre-check -> lessons + memory + knowledge pick -> router picks FAST / DEEP / RESEARCH
  -> decide()  (existing; ONE call) now also returns, when brain.v2 is on:
        signals      {emotion_hint, pattern_hint, evidence: "none|some|clear", surface: bool}   (never stored)
        perspective  one short "another way to see it" (only when surface is true)
        decision     optional options table for real decisions
        sources      from live lookup, with verified flag
        certainty    "verified | likely | unsure"
  -> verifier (new): honesty guard (existing) + field validation + psychology safety rules
  -> brain_runs row (mode, modules, model, tokens, latency, cost; no text)
```

## Stages

| Stage | Content | User-visible change | Paid API | Size |
|---|---|---|---|---|
| A. Foundation | full backend suite in CI; fix the order-dependent tests; security fixes 1-4; prompt-injection fence; explicit Gemini timeout; turn id; `brain_runs`; logging config | none | none | small-medium |
| B. Evaluation first | benchmark set (about 80 cases: normal, Telugu-mixed, ambiguous, psychology, business, finance / legal, medical safety, scam, adversarial, "must NOT show an insight"); runner that scores the CURRENT brain = the baseline; Brain Benchmark page | none | benchmark runs cost a few rupees each | medium |
| C. Model registry + router | `model_registry` resource seeded from today's env; FAST / DEEP / RESEARCH rules; daily cost ceiling; prompt versions | none until DEEP is enabled | DEEP model = owner decision | medium |
| D. Psychology + emotion + behaviour | `psychology_knowledge` resource (first 40-60 well-evidenced entries, each with references and limits, staff-reviewed); `signals` + `perspective` in the same call; thresholds; distress reply in main chat; user switch | "ఇలా కూడా ఆలోచించవచ్చు..." only when useful | none extra (same call, slightly longer prompt) | large |
| E. Research + decision output | sources / verified / certainty fields; decision table | sources and certainty under a reply; comparison table | none extra | medium |
| F. App | reply widget shows perspective, sources, certainty, decision table; Memory screen switch | yes | none | medium |
| G. Admin | Brain Dashboard (modules used, cost, latency, insight rate, wrong-answer rate), prompt version history + rollback, flags | staff only | none | medium |
| H. Rollout | staging -> shadow mode (new brain runs silently on a sample, compared by the benchmark scorer) -> owner phone test -> flag on | — | shadow doubles cost on the sampled turns only | small |

Stage B before D is deliberate: without a baseline nobody can show the new Brain is better.

## Cost (ESTIMATES -- real numbers come from the usage meter in production)
Assumed: FAST model `gemini-3.6-flash` at the meter's price ($0.75 in / $3.75 out per million tokens), a chat
turn of roughly 3,500 tokens in and 400 out.
- Today: about $0.004 per chat turn (about ₹0.35); an advice turn about double.
- Brain fields in the same call (stages D, E): about +600 tokens in (rules + picked knowledge) and +150 out
  -> roughly +25-30% per turn (about ₹0.10 more).
- A separate psychology call per message (NOT recommended): about +100% per turn.
- DEEP mode on a stronger model: about 5-15x a FAST turn for that turn. If 5-10% of turns escalate, the average
  cost rises by roughly 25-150% depending on the model chosen -> this is why a ceiling and a dashboard come first.
- Exact-question cache for non-personal answers lowers cost; the saving is unknown until measured.

## Owner decisions needed (nothing paid is switched on before these)
1. DEEP model: stay on Gemini (a stronger Gemini model), use OpenAI `gpt-5` (key already configured), or add
   Claude (new account / key; matches the 2026-10-30 intent). Recommendation: start with what is already paid for,
   compare on the benchmark, then decide.
2. Daily AI spend ceiling in rupees for the Brain (above it: FAST only).
3. Psychology knowledge: reviewed by whom before going LIVE (owner / a qualified reviewer)? Entries are written
   from published research with references; unreviewed entries stay DRAFT and are never used.
4. Off-volume backup location (bucket) for the scheduled backup.

## Not planned (with reasons)
- Postgres / Redis / vector database now: not needed for these stages; high migration risk.
- Twelve separately-called agents: cost and latency without a quality gain for ordinary turns.
- Storing emotional or psychological inferences, or showing them to staff: refused (privacy).
- Automatic prompt / routing changes in production: always a person's approval.

## Rollback
Flag `brain.v2` off = today's behaviour. New tables are additive and unused when off. Prompt versions roll back
to the previous LIVE version from the Command Center. App fields are optional; older app builds ignore them.

## Acceptance (per stage)
Full backend suite green in CI; Flutter CI green; benchmark not worse than baseline on correctness, safety,
Telugu quality; zero "unsupported inference" failures in the psychology safety cases; cost per turn and latency
shown on the dashboard; a real-phone check by the owner before the flag goes on in production.
