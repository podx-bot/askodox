# ASKODOX / PODX AI CONNECT — Project Memory

Last reconciled: 2026-10-07
Canonical repository: podx-bot/askodox
Source of truth: current GitHub `main`. This document is living context, not a substitute for code inspection.

## Purpose
This file preserves product decisions, owner instructions, verified development state and next-step context so ChatGPT, Claude, Kimi and coding agents do not restart or repeat old work. Read `AGENTS.md` first.

## Product identity
ASKODOX is a universal AI/local-commerce assistant and companion, not an ecommerce-only app. It connects buyers, sellers, service providers and survey participants and should extend universally to products, used/refurbished/surplus, local businesses, services, jobs, travel, insurance/BFSI, affiliate/online fallback and future categories.

Core positioning: direct connection and local commerce. The platform should not unnecessarily become merchant-of-record. Preserve user/seller control of their business, customers and payments.

## Non-negotiable experience
- One primary conversational experience; results/cards belong with the conversation rather than a separate ecommerce UX.
- Text, voice, attachments/vision, location, matching, results and actions must share conversation context.
- Dynamic/category-specific questions are allowed, but architecture must remain universal and category-agnostic.
- Results must wait until the Decision Brain says enough required information is known.
- Same-topic refinements update the active need/results; unrelated new topics retire stale results.
- Seller/provider contact details are shared only after explicit acceptance of the relevant request/deal.
- Prefer nearby/local matches; when unavailable/thin, provide honest online/affiliate fallback.
- Telugu, Tenglish and English are priority conversation/voice modes; language behavior should be automatic unless the user explicitly chooses a preference.
- Sensitive OTP/card/Aadhaar/PAN screens should disable assistant/avatar/mic capture and restore safely afterward.
- Camera / Photos / Files should attach inside chat and reuse the universal reasoning pipeline.
- Videos should play in-app where supported; do not turn the app into a separate video/ecommerce experience.
- Admin/Command Center should centralize operations, analytics, configuration, staff permissions and system health.

## Result Board target
Universal Result Board states:
1. Expanded automatically when useful fresh results arrive.
2. User can minimize to a persistent compact pill such as `7 Results • ₹20k phones ▲`.
3. Tap restores the board.
4. Same-topic refinements update/reopen the deck when appropriate.
5. A genuinely unrelated new topic retires/hides the old deck.
6. A selected result may stay pinned as a compact conversation-context item.
This behavior must work across every result domain, not be hard-coded to phones/products.

## Voice/provider policy
Do not permanently choose a primary provider from assumptions. Compare providers using the same real-phone Telugu/Tenglish/English tests for recognition accuracy, latency, TTS quality, reliability and cost. Sarvam is currently integrated. ElevenLabs may be evaluated under the same test matrix; primary/secondary/fallback order should be evidence-driven.

## Verified GitHub baseline
As of reconciliation, current main is `0d039f2a942f94b04c12b18393324567f7951361`, merge of PR #164: `fix: universal conversation intelligence and result lifecycle`.
PR #164 is already merged. Never re-push/re-merge the old conversation-intelligence patch solely because an older audit says it is missing.
Android APK CI for this main merge completed successfully.
APK 1306 is the current real-phone test baseline.

## Audit reconciliation — 2026-10-07
Kimi audited an older main state (`4353fe0`), so findings that said the conversation-intelligence branch was not merged became stale after PR #164.
Claude cross-audited current main and production logs. Important evidence:
- During the APK 1306 test window, Sarvam STT/TTS calls returned HTTP 402 according to the Claude audit. Re-check provider account/production logs before changing voice architecture.
- Earlier long Telugu speech reportedly worked, so do not change segmentation/timeouts merely because the older Kimi audit hypothesized they were the root cause.
- Claude identified a fallback conversion defect: MP4 piped to ffmpeg stdin can yield a tiny/header-only WAV that is treated as success, allowing a downstream model to transcribe silence. This requires code verification/fix/tests.
- Claude reproduced a PR #164 relation-layer problem with Telugu/Indic tokenization/cross-script subject comparison. This can misclassify refinements as new topics and retire/restart the result deck. Fix with Unicode/Indic-aware logic and regression tests.
- Result Board expand/minimize/pill/restore/pin behavior is still missing.
- Header language represents UI preference and can diverge from actual conversation language; language state needs reconciliation.
- Provider health based only on key presence is insufficient; credit/quota/402/429 health should become visible to staff.
Treat these as audit evidence to verify against current code/logs before modification, not permission to blindly edit production.

## Real-phone APK 1306 evidence
Owner observed:
- Home renders; no blank/black-screen blocker.
- Conversation/context feels improved across phone search → gaming/camera → refurbished → processor → exchange → Samsung S23.
- Long voice recording can continue but recognition/understanding was poor during the affected test window.
- Language can be inconsistent (e.g. EN header while Telugu conversation/replies).
- Results remain visible, but board interaction semantics are incomplete.
- Generic/unverified trade-in estimates need better qualification questions/evidence.
- Generic `OK` after results should be interpreted as a contextual next-step, not a new unrelated need.

## Current priority order
P0A. Check/restore Sarvam credit/service health, then retest the SAME APK 1306 before judging voice quality.
P0B. Verify/fix MP4→WAV fallback so near-empty audio is rejected and failure is honest; add tests.
P0C. Fix Indic/Telugu conversation-relation regression and deck retirement/restart behavior; add backend + Flutter regression tests.
P1. Establish one conversation-language source of truth across STT, replies and header.
P1. Implement universal Result Board expanded/minimized/pill/restore/refine/retire/pin behavior on existing result state.
P1. Add provider credit/quota/error health visibility and alerts.
P2. Real-phone evidence matrix for Camera/Photos/Files, vision, video, location/maps, Screen Guide, privacy overlay and contact-consent.
P2. Include shown result sources in follow-up context where missing; incrementally extract ResultBoard/Composer from the large home screen without a rewrite.
P3. Push client, affiliate credentials/providers, mobility/delivery completion, diagnostics gating and carefully verified repo/config hygiene.

## Do not change without evidence
- Decision Brain / search-ready gate.
- Sarvam endpointing/segmentation/timeouts solely on the old timeout hypothesis.
- Android MediaRecorder/MainActivity bridge.
- webhook/video layers merely because filenames look duplicative.
- OASAT wiring without tracing actual backend use.
- signing/package/release identity.
- Result Contract v2.
- Production/DNS/secrets without explicit owner approval.

## Development/testing rule
For every significant change:
- start from current main;
- trace UI → state → API → backend → provider/data → response → UI;
- add focused regression tests;
- run relevant backend/Flutter/analyze/CI gates;
- produce a signed monotonically versioned APK when a device build is needed;
- verify device-dependent behavior on a real Android phone;
- update this memory only after facts are verified.

## Memory maintenance
After each meaningful merge, append/update:
- current main SHA and PR;
- APK/build tested;
- verified completed behavior;
- open regressions;
- decisions that changed;
- next exact priority.
Do not store secrets or personal credentials here.

## Branch in review (NOT merged): feature/universal-result-board-admin-affiliate
Built on main 2e7dba2 (PR #166). Pending independent review before merge:
- Relation/routing/comparison: content-token relation engine (thin refinements,
  acks, choice questions, return-to-previous, cross-script, weak single-word new
  topics reconciled with the model); FB/IG/Meta video talk stays conversation;
  location/price/status labels never comparison entities.
- Universal Result Board: expand / minimize to pill / restore / auto-retire /
  same-topic refresh / selected-result chip; "the best one" shows one result.
- Header language chip shows the reply language; header choice = explicit lock.
- Affiliate Product Hub + Meesho adapter (truthful extraction with provenance,
  drafts by default, publish permission, bulk actions, retry), Command Center page.
- Provider health from real answers (Sarvam 402 -> QUOTA_EXHAUSTED).
Device verification of all of the above is still required (next APK).


## Branch in review (NOT merged): claude/navigator-ux-p0 — PR #182 (draft), 2026-10-09
Built on main bae9c9e (PR #180). Navigator UX P0 slice:
- Result Board: ONE tab row `Result Board | Local | Online | Deals | Reviews | Videos` + Expand + Minimize
  (`result_board_tabs.dart`, `result_board_tab_row.dart`); tabs are views of the same deck; Reviews only
  rows with rating AND review count; honest empty text per tab. Lifecycle (pill/restore/archive/pin/mega) unchanged.
- Composer: exactly one `+` (Camera / Photos / Videos / Files -> existing `_pickAttachment`); no mic beside Send.
- Header: Menu sheet over existing routes (no drawer) + Screen Guide sheet (in-app flows + cross-app guide).
- CI on the branch: Flutter CI (analyze + 963 tests) PASS, Feature Registry gate PASS; backend suite 1034 passed locally.
- Already true on main before this branch (verified in code, not re-done): no second mic; MP4->WAV fallback rejects
  empty/near-empty WAV (`audio_codec_service.audio_to_wav`); PDF/DOCX/XLSX accepted by `/api/attachments/analyze`.
- NOT done in this slice: "Shopping/Washing Machine" dropdown not found on main (nothing to delete); morning-bug
  list not in repo/issues (needs owner screenshots); P1 workflows untouched; every item still needs a real phone.
- Next: real-phone test of the private APK from Android Live Build on this branch, then review/merge.
- 2026-10-09 round 2: layout assertion kept strict (tab row = one <=40px row at board top; cards <=16px below it,
  same 16px rule as before). "Shopping / Washing Machine" dropdown: searched lib/ (dropdowns, popup menus, app
  builder overlays, companion bar, notifications) -- no such widget on main or this branch; needs the owner's
  screenshot to identify (possibly an older APK or an Android notification). Morning-bug list still not available
  in repo / issues / memory. APK 1316 (run 37951204272) still matches the app code (later commits = tests/docs).
- 2026-10-10 P0 round after APK 1316 (PR #182, commit b6017cb + revert 92100e1; APK 1317 phone-test link):
  DONE (code+CI): mic until Stop (`AskodoxVoiceEndpointer.untilStop`, 2 min cap); typed + voice + attachments = one
  draft (`askodoxMergeVoiceDraft`, Send while recording finishes & sends); no repeat listings (restore never posts,
  once per deal, `askodoxListingSubjectValid`); backend model JSON `strict=False` (prod 2026-10-09: Gemini JSON with
  raw newline failed -> OpenAI fallback 429 -> no answer on "Airtel").
  OPEN DECISION: prod logs show Telugu speech (te-IN) answered in English because the explicit Settings/header
  Preferred Language was English; approved Section 2 rule says Preferred Language wins -> change reverted, owner to decide.
  NOT STARTED: Clean UI redesign, Smart Fill, Studio editing, Free/Plus/Pro subscriptions (Phases 2-5).
- 2026-10-10 round "final consolidated" (PR #182, APK 1318): DONE (code+CI) Navigator Profile (5 sections via shared
  `navigator_section.dart`), My Business grouped sections, My Listings (search, own-photo thumbnail, confirm remove,
  Ready-made catalog entry); ONE data-driven catalogue engine now carries per-template attributes (`catalogue_templates.py`
  attributes / clean_attributes; new meat_poultry, pickles, tiles_marble, electronics, services); required detail or price
  missing -> draft. NOT DONE: Smart Fill engine, Studio editing, rides fleet/negotiation, voice text<->TTS sync,
  subscriptions UI; Rides/Delivery/Services screens not yet restyled; listing API has no image upload outside catalogue.
- 2026-10-10 APK 1319: voice + text together (askodoxSpeechChunks: sentence chunks, first <=160 chars, next chunk
  prefetched; text typed in as read via askodoxRevealPrefix; one session for Stop/Pause), glued points split
  (askodoxSplitGluedPoints), 10/14 px point/paragraph gaps. Typed turns are still NOT spoken (approved rule; owner
  may want every reply spoken -- ask). Telugu question -> English reply = explicit English Preferred Language (decision pending).
