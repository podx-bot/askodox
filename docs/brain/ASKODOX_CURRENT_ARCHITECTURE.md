# ASKODOX — current architecture (Brain Phase Zero audit, 2026-11-10)

Read from the code on `main` `df93346` plus draft PR #299 (self-correction, Work Mode sound, Play fixes).
Nothing here was changed by the audit. Where a fact was not verified it says so.

## One picture

```
Flutter app (Riverpod, go_router)                     FastAPI backend (one uvicorn process, Railway)
  Main Chat (askodox_primary_home_screen.dart)          routes/in_app_assistant.py  POST /api/in-app/assistant
    -> AssistantService.decide() ---------------------->   UniversalAiAssistantService.decide()  (the ONE brain)
    <- reply, mode, state, search_ready, suggestions ...      Gemini (primary) -> OpenAI (fallback)
    -> /deals, /deals/{id}/matches (search)             result_orchestrator.py (sections) + web_search_chain.py
    -> /api/attachments/analyze                         image / video / document processors
    -> /api/in-app/voice/transcribe | speak             Sarvam STT -> Gemini; ElevenLabs -> Sarvam -> Gemini TTS
                                                        SQLite file on a Railway volume (284 tables)
Command Center (web, /admin/console)                    periodic_jobs.py (in-process thread, 6 jobs)
```

## Mobile app
- Flutter, Riverpod 2.6 (hand-written providers, no codegen), go_router 14.8 (`lib/config/router/app_router.dart`).
- Phase switch `lib/core/flags/askodox_release_phase.dart`: Phase 2 routes are only registered when
  `ASKODOX_PHASE2` is set; `askodoxPlayStoreBuild` hides the Razorpay recharge in the Play bundle.
- Main Chat is ONE screen file (7,275 lines). A turn: attachments analysed -> `decide()` (15 s timeout, last 12
  turns, location, `searched_for`, `advice_given`, `capabilities`) -> the app applies the decision (advice ledger,
  chips, app action, search gate) -> searches only when the brain says ready or the user says "show me".
- If the brain call fails the app falls back to its offline rules (no invented answer).
- Voice: native recorder -> `/api/in-app/voice/transcribe`; replies spoken through `/api/in-app/voice/speak`, device
  TTS as the last fallback. One audio lifecycle (`_speechTurn`).
- History: local snapshots + `/api/me/conversations` backup. Memory screen `/profile/memory` (consent, on/off,
  edit, delete one, delete all). Privacy centre `/privacy` (export, delete account).

## Backend
- FastAPI, `backend/server.py` is what production runs (mounts `/deals`); `app_factory.create_app()` builds the rest.
- The chat brain is `services/universal_ai_assistant_service.py`:
  - `decide()` -> one JSON decision call (`_decision_json`, temperature 0.15, no thinking budget).
  - advice mode adds one reasoning call (`_advise`).
  - live lookup (`live_lookup.py`) adds web searches and an honesty guard, not model calls.
  - prompt = inline text + constants (`DECISION_GUIDANCE_RULES`, `MEANING_TAG_RULES`, `CONVERSATION_STATE_RULES`) +
    blocks from `advice_memory`, `reply_suggestions`, `chat_actions`, `answer_corrections`. Not versioned.
- Results: `result_orchestrator.py` (Result Contract v2 sections), `web_search_chain.py` (Serper -> Brave -> Google CSE).
- Admin: Command Center (`routes/command_center.py`, console map `admin_console_nav.py`), schema resources
  (`platform_schema.py`) for staff-editable data, feature flags (`command_center_repository.py`).
- Background: one in-process runner, jobs promotions / selfheal / feeds / crm_reminders / availability / owner_alerts.

## Infrastructure
- Railway: Dockerfile, `uvicorn server:app`, ONE process, healthcheck `/health` (returns the commit).
- Production deploys from `main`; staging from a dev branch with its own variables and volume.
- Database: SQLite only (no Postgres, no Alembic). No Redis, no queue. Caches, rate limits and OTPs are in memory.
- No error-tracking service. Logging is not configured centrally (see the security audit).

## What this means for the Brain
1. There is already ONE brain with a clear seam (`decide()`); the Brain must wrap and extend it, not add a second chat path.
2. One process + SQLite + in-memory state: anything the Brain adds must work in a single process and must not need
   Redis / Postgres / a vector database to start.
3. The app already tolerates new optional response fields (older builds ignore them; new ones announce
   `capabilities`). That is the safe way to add "another perspective", sources and confidence.
