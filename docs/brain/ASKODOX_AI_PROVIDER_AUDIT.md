# ASKODOX — AI provider audit (Brain Phase Zero audit, 2026-11-10)

Env var NAMES only; no values were read or printed. Paths are under `backend/app/`.

## Providers in use

| Use | Primary -> fallback | Default model | Timeout / retry | Health recorded |
|---|---|---|---|---|
| Chat brain (decide, advise, write_text) | Gemini -> OpenAI | `gemini-3.6-flash` (`GEMINI_TEXT_MODEL`) -> `gpt-5` (`OPENAI_TEXT_MODEL`) | Gemini: 3 tries on server errors, NO explicit timeout; OpenAI: 20 s, no retry | yes (`provider_health`) |
| Intent / extraction helpers | Gemini | `gemini-3.6-flash` | 2 attempts | no |
| Image understanding | Gemini -> older Gemini -> OpenAI | `gemini-3.6-flash` -> `gemini-3.5-flash` -> `gpt-5` | 20 s | no |
| Video study | Gemini -> older Gemini | same | bounded by `video_study.max_seconds` | no |
| Image create / edit | OpenAI | `gpt-image-2.5-sunburst` (`OPENAI_IMAGE_MODEL`) | 90 s | failure log only |
| Speech to text | Sarvam -> Gemini -> Gemini Files | `saaras:v3` | 8 s | yes |
| Text to speech | ElevenLabs -> Sarvam -> Gemini TTS -> device | `eleven_v3`, `bulbul:v3` | 8 s / 6 s | yes |
| Web search | Serper -> Brave -> Google CSE | — | 8 s each; Brave breaker + last-good store | via API billing |
| Maps | Google Geocoding / Places / Routes | — | 5 s | no |

Not present: an Anthropic (Claude) client (only two price rows in the usage meter), embeddings, reranking, a
moderation API.

## How a chat turn spends model calls
- chat / commerce / follow-up: 1 call. A second decision call only when a named product model gets live evidence.
- advice: 2 calls (decision + advice).
- live lookup: 1 search (quick) or up to 4 searches (deep); no extra model call.
- Context sent: last 12 turns (1,200 characters each), up to 12 memory lines, lessons, ledger. No overall token budget.

## Findings
1. **Model ids are env-only.** Changing a model means a Railway variable change and a redeploy; four services
   also hard-code model tuples. There is no registry and no per-task routing.
2. **No escalation.** A hard question gets the same fast model as "hello". Advice mode is the only "deeper" path
   and it uses the same model.
3. **Gemini call has no explicit timeout** (the app gives up after 15 s; the server thread may keep waiting).
4. **Brain answers are never cached** and identical repeated questions pay again.
5. **Prompts are unversioned strings.** A prompt change cannot be compared or rolled back except through git.
6. **Cost is known per feature, not per user or per turn.** `ai_usage_meter` counts tokens per day / feature /
   model; `ai_credits` counts uses per user; nothing joins them. No hard ceiling exists.
7. **An advice turn = 2 calls but 1 credit.** Fine while charging is off; the rate card must know this later.
8. Earlier owner decision (2026-10-30) said "Claude Haiku primary, Sonnet for hard tasks". The code never moved to
   Claude; chat runs on Gemini. This needs an owner decision (see the implementation plan).

## Price table in the meter (staff-editable, `ai_usage_prices`)
`gemini-3.6-flash` $0.75 in / $3.75 out per million tokens; `gpt-5` $1.25 / $10. Real per-turn cost must be read
from the meter in production (Command Center -> API Health & Billing); the audit session cannot reach production data.

## Provider adapter strategy (recommendation)
Do not write twelve new adapters. Add ONE small `model_registry` (schema resource: task -> provider, model,
timeout, max tokens, enabled) read by the existing service, with today's env values as the seed. That gives
configurable primary / fallback / specialist models and a Command Center view, without touching working call code
beyond the place where the model id is chosen.
