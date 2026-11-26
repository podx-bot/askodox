---
name: askodox-chat-speed
description: Use when the ASKODOX owner says chat / voice answers are slow, after any change to the brain, prompts, models or reply voice, and after each merge that touches chat -- reads the production timing lines and reports where the seconds go.
---

# ASKODOX chat speed check

The owner's target: the first words of an answer in 1-2 s and the voice starting with them. Every fix so far came
from the deploy log, never from guessing. This skill keeps a speed fix from being undone.

## 1. Read the timing lines (Railway, project lavish-perfection, service podx-ai-connect, production)
Filter the deploy log for the last test window:
`"BRAIN TIMING" OR "CLAUDE STREAM" OR "VOICE TRANSCRIPTION" OR "VOICE SPEAK"`

- `ASKODOX BRAIN TIMING: path= action= level= search= plan_ms= grounding_ms= route_ms= first_ms= total_ms=`
  - `path=routed_early` = the fast reply was used; `routed` = planner said search or hard, routing ran again.
  - `plan_ms` planner call, `grounding_ms` planner + live search, `first_ms` = first words on screen (server side).
- `ASKODOX CLAUDE STREAM model= first_token_ms= total_ms= in_tokens= cache_read= cache_write=`
  - `cache_read` > 0 = the fixed instructions came from the cache. `cache_write` ~8k on every turn = cache lost.
- `VOICE TRANSCRIPTION PATH ... request_ms=` speech -> text.
- `ASKODOX VOICE SPEAK ... chars= ms= cache=` one voice part (first part should be <= 90 chars, ~0.6-1 s).

Add them up for one question: transcribe + first_ms + first VOICE SPEAK ms = what the owner waits.

## 2. Rules that must stay (each one was a measured slowdown)
1. Chat calls send `thinking` off: Haiku `{"type": "disabled"}`, Sonnet `{"type": "between_tools"}`
   (`UniversalAIAssistantService._quick_thinking`). Without it the 5.5 models think first: Haiku first word 5-7 s.
2. Fixed instructions are cached for 1 hour (`_content`, `"ttl": "1h"`); the 5-minute default made every first
   question after a pause re-read ~8k tokens.
3. Hard turns route AND write their guide / advice on the reasoning model, never the strongest (`_decision_json`,
   `anthropic_hard_model`): routing took ~10 s; a "SIP or FD" advice answer waited 17.4 s for its first word (38 s
   in all, probe 2026-11-26) because the strongest model always thinks first. Staff override: ANTHROPIC_HARD_MODEL.
4. The early route (`_EarlyRoute`) runs next to the planner; only search / hard drops it.
5. First spoken part <= 90 chars with a comma cut (`askodoxFirstSpeechMax`, `askodoxSpeechChunks`).
6. Short plain replies are a chat bubble, not an answer card (`answer_card.build`).
7. Talk mode: echo gap 700 ms, 10 s no-speech pause (`askodoxTalkEchoGap`, `askodoxTalkNoSpeechTimeout`).

`backend/tests/test_chat_thinking_off.py`, `test_chat_planner.py`, `test_chat_answer_streaming.py` and
`test/services/voice_endpointing_test.dart` guard these; never "fix" a red test by removing the rule.

## 2b. Measuring without the owner's phone
The session cannot reach production directly. Push a throwaway `diag/chat-speed-probe-*` branch with a workflow that
POSTs questions to `/api/in-app/assistant/stream` (no sign-in) and prints first-word / total seconds, then read the
timing lines for that window. Never merge such a branch.

## 3. Report to the owner (Telugu, short)
Per question: how many seconds to first words and to voice, which step was the biggest, and the next fix.
Say plainly when nothing was measured on a phone.
