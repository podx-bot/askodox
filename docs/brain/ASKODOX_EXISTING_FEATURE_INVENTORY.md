# ASKODOX — existing feature inventory (Brain Phase Zero audit, 2026-11-10)

Status words: BUILT (code + tests), PHONE VERIFIED (only where a real phone test is recorded), PARTIAL, ABSENT.
Almost nothing is phone verified; "BUILT" never means a real-phone pass.

## Intelligence that already exists (reuse, do not rebuild)

| Brain spec module | What exists today | Where | How it runs |
|---|---|---|---|
| Language | Reply language rule (lock > typed language > setting), Telugu / English / Hindi mixed input understood by the model; ONE next question on ambiguity | `conversation_language.dart`, `_reply_language_rule`, `next_question` | inside the one decision call |
| Context | Conversation state (`goal`, `facts`, `flexible`, `unknown_critical`), topic relation, search readiness | `CONVERSATION_STATE_RULES`, `conversation_relation.py`, `search_readiness.dart` | decision call + rules |
| Memory | Profile memory (consent, edit, delete), chat backup, one-time advice ledger | `profile_memory.py`, `conversation_backup.py`, `advice_memory.py` | injected into the prompt |
| Research | Live web lookup (quick / deep), sources footer, honesty guard, evidence conflicts, real date | `live_lookup.py`, `evidence_conflict_analyzer.py`, `runtime_time_context.py` | searches + rules |
| Decision | Advice mode (goal, gaps, numbers, risks, alternatives, recommendation), Universal Advisor questions, buying guide | `_advise`, `advisor_engine.py`, `buyer_guide_gate.py` | 2nd model call / rules |
| Reasoning | Guidance rules before results; estimates labelled; reply prices reconciled with cards | `DECISION_GUIDANCE_RULES`, `chat_result_policy.dart` | decision call + app rules |
| Safety | Fraud / scam awareness, tax and GST notes, smart tricks, price truth, listing quality, PII masking | `intelligence_gate.py`, `fraud_awareness.py`, `price_truth.py`, `pii_mask.py` | rules |
| Self-improvement | Wrong-answer button, typed corrections, staff-approved lessons into the prompt, regression list, brain-failure alert (PR #299); knowledge gaps + owner alerts; self-healing | `answer_corrections.py`, `owner_alerts.py`, `assistant_health.py` | rules + staff review |
| Learning (teaching style) | Smart Answer chips, meaning colours ([ok] / [caution] / [risk]), rich replies | `reply_suggestions.py`, `rich_reply.dart` | decision call |
| Creative | Photo studio (edit / create), reels from own photos (staff) | `openai_image_service.py`, staff workspace | separate calls |
| Multimodal | Image, video study, documents, voice in / out | `routes/attachments.py`, `video_study.py`, voice routes | separate calls |
| Cost | Usage meter (per day / feature / model), AI Credits ledger (per user), API health & billing | `ai_usage_meter.py`, `ai_credits.py`, `api_billing.py` | hooks |

## Absent today (the real gaps)
- Psychology / emotion / behaviour understanding in the main chat: ABSENT. (Talk has self-harm handling only.)
- Distress / self-harm safety path in the MAIN chat: ABSENT.
- Model router / escalation to a stronger model: ABSENT (fixed Gemini -> OpenAI fallback).
- Embeddings, vector search, semantic cache: ABSENT. Brain calls are never cached.
- Prompt versioning and rollback: ABSENT.
- A turn / response id shared by app and server: ABSENT (feedback sends the text itself).
- Automated answer-quality evaluation (benchmark set, old vs new comparison): ABSENT.
- Per-user provider cost and any hard spending ceiling: ABSENT.
- Sources, confidence and "another perspective" shown in the app: ABSENT (the server already sends `grounding`,
  `honesty`, `confidence`; the app only logs them).

## Product surface (Phase 1 build)
Chat + result board, attachments, voice, History / Explore, Profile (memory, payment methods, AI Credits, Smart
Tools, privacy, notifications), Work Mode walking game (teams, sound), onboarding / OTP, Staff Workspace link,
Command Center. Phase 2 (kept in code, not in the Phase 1 build): POS, CRM, business tools, rides, plans, KYC,
native videos, Talk, Radio, cross-app screen guide.

## Known open issues that touch the brain
- A combined short answer can be stored in two fields ("1 kg curry cut skinless").
- A brand missed in the first message can stay in the subject beside a later brand.
- Hotel / salon / healthcare follow-up questions are generic.
- No automatic check that a Flutter caller was updated when a route's auth changes.
