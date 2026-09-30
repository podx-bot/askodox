# Master staging upgrade — what exists, how it behaves, what it cannot do

Branch `claude/friendly-ramanujan-538sbj`, **staging only** (`staging.askodox.com`). `main`, production and PR #110
are untouched. Status words: **SUPPORTED NOW**, **PARTIALLY SUPPORTED**, **REQUIRES ANDROID PERMISSION**,
**REQUIRES MOBILE APP CHANGE**, **BLOCKED BY PLATFORM POLICY**, **REQUIRES EXTERNAL SERVICE**.

## Governance (Command Center → System)

| Item | Status | Notes |
|---|---|---|
| Granular RBAC `module:view/create/edit/approve/delete/export/manage` | SUPPORTED NOW | `manage` implies create/edit/approve/delete; `export` always explicit. Enforced server-side on every route. |
| Standard forbidden message | SUPPORTED NOW | "You do not have permission for this action. Owner/Admin approval is required." |
| 15 role presets + Owner-defined roles | SUPPORTED NOW | `PUT /admin/cc/roles/{name}` (Owner / Super Admin only). |
| No self-escalation; managers delegate only what they hold | SUPPORTED NOW | Own permissions can't be changed; RED grants by non-Owner are held for approval. |
| Permission Safety Advisor | SUPPORTED NOW | RED grants, separation-of-duties combinations, exports. |
| GREEN / ORANGE / RED + reusable approvals | SUPPORTED NOW | Named executors only; no self-approval; RED = Owner/Super Admin with confirmation; idempotent. |
| Audit log (who / role / action / target / time / result / risk / old→new) | SUPPORTED NOW | Append-only (no edit/delete route), secrets redacted, CSV export needs `audit:export`. |
| Arbitrary SQL / shell / code execution | NOT PRESENT (by design) | A test fails if such a route appears. |

## Business modules

| Item | Status | Notes |
|---|---|---|
| Support Center (AI first → ticket → staff alert → two-way reply) | SUPPORTED NOW | Public replies vs internal notes, reopen, escalate, SLA, search, masked requester. WhatsApp/SMS/e-mail remain optional feeds (REQUIRES EXTERNAL SERVICE). |
| Targeted promotions | SUPPORTED NOW (in-app) / REQUIRES EXTERNAL SERVICE (push, SMS, WhatsApp, e-mail) | Legitimate-data targeting, consent (external channels opt-in), caps, schedules, four-eyes approval, metrics. No real message leaves staging. |
| Revenue Command Center | SUPPORTED NOW | Recorded revenue only, de-duplicated, gross/net/expected/pending/confirmed/paid/refund; payment gateway still REQUIRES EXTERNAL SERVICE. |
| Event Stream + AI Insights category | SUPPORTED NOW (fixed) | Specific detected category (e.g. "Wireless earbuds") instead of PRODUCT/SERVICES. |
| Self-Healing Engine | SUPPORTED NOW | GREEN source bypass (auto only when switched on), ORANGE via approvals, RED alert-only. |
| Sponsored / external ad networks | PARTIALLY SUPPORTED | ASKODOX sponsored placements exist; external networks integration-ready only (REQUIRES EXTERNAL SERVICE). |

## AI Companion Screen Guide (Android)

| Capability | Status |
|---|---|
| Start a guide in ASKODOX with a goal (typed; Telugu/English) | SUPPORTED NOW (app) |
| Read labels of the app on screen during a guide | REQUIRES ANDROID PERMISSION (user enables "ASKODOX Screen Guide" in Accessibility settings) |
| Step-by-step instruction + highlight of the button to press | SUPPORTED NOW once the permission is on (highlight = outline only) |
| Voice (device TTS, Telugu/English) | SUPPORTED NOW (depends on the phone's TTS voices) |
| Privacy Shield pause (password fields, OTP/PIN/UPI PIN/CVV/card/bank/Aadhaar, payment/banking apps) | SUPPORTED NOW (on phone + server) |
| Explicit resume (double-tap panel / Continue) and End Guide cleanup | SUPPORTED NOW |
| Tapping / typing for the user, completing payments | NOT DONE (by design) — the user performs every step |
| Reading screens protected with FLAG_SECURE | BLOCKED BY PLATFORM POLICY (Android hides them; the guide just sees nothing) |
| Voice commands while in another app | REQUIRES MOBILE APP CHANGE (microphone foreground service not added) |
| Publishing on Google Play with this accessibility use | BLOCKED BY PLATFORM POLICY until a Play accessibility declaration is approved (the staging APK is side-loaded) |
| Screenshots / OCR | NOT USED (no screenshots are ever taken) |

Retention: the guide keeps the session (goal, last instruction) in memory only; End Guide or 30 minutes of
inactivity clears it. Only anonymous daily counts are stored (sessions, outcomes, pauses by reason, languages,
task categories, failure points, permission health).

Threat model (summary): overlay/tapjacking — the highlight window is not touchable and the panel is small, never
full-screen; accessibility misuse — reads only during a user-started guide, no gestures/actions declared or used;
capture leakage — no screenshots, labels only, editable field values never read; prompt injection — screen text is
wrapped as untrusted data, injection phrases neutralised, the model's target must be a label that is on screen, rule
fallback otherwise; PII — shield before sending, server re-check, nothing stored; cross-app leakage — ASKODOX's own
windows are ignored, session bound to the signed-in user; background capture — the service ignores events without a
session; session hijack — random session ids, bound to the user token, 30-minute expiry.
