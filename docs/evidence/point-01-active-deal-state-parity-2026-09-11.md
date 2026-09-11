# Point 1 — Active Deal State / Multimodal Parity Evidence

Date: 2026-09-11
Status: IN PROGRESS

## Verified completed evidence

- ActiveDealContextResolver foundation commit: `82718a7a0303c8dc87a0aa33b1b2fd01ef3bf440`.
- Resolver regression tests commit: `b29a2aa83848db69fc91ca9a0f867807ef5abe9f`.
- Resolver fast smoke workflow commit: `6a22b81eb682d19f10f23a3c03d02a9eec3ae581`.
- Resolver smoke run `34622294077`: SUCCESS.
- UniversalLiveCaptureService same-context integration commit: `d5b34d639b3963dfc14b0cbeb0f2518cd03b7f8a`.
- Structured-input regression tests commit: `4f9d2754f35831a4943d6c542ddf9fb6185a2bb7`.
- Integration smoke workflow commit: `173063533429a92e8fb1cd54f216b107e7d9194d`.
- Integration smoke run `34622768360`: SUCCESS.
- Backend monorepo smoke run `34622704338`: SUCCESS for structured-input regression head `4f9d2754...`.
- Flutter CI run `34622704353` on `4f9d2754...` was CANCELLED by later push/concurrency; no code-failure conclusion should be inferred from that cancellation.

## Current authoritative behavior

Backend `UniversalLiveCaptureService.process_structured()` now checks the latest active universal demand before creating another record. When side + domain + normalized subject match the active request, non-empty incoming fields are merged into the same active demand ID using `update_active_fields()`. Existing facts are preserved and constraints are merged instead of overwritten.

Image processing already routes recognized NEED/OFFER requests through `UniversalImageService -> UniversalLiveCaptureService.process_structured()`, so same-context image evidence reaches the same backend active-demand merge path.

## Newly identified Flutter continuity gap

Flutter `UniversalDealController.start()` currently behaves differently once the active deal is complete: if `missingForMatch` is empty it captures the new text and replaces the current session. Voice input in `ProductDiscoveryController.startVoice()` sends the recognized utterance to `universalDealControllerProvider.notifier.start(spoken)`. Image/OCR discovery also calls `.start(extracted)`.

Therefore a completed active deal can still be replaced on the Flutter client when a same-request voice/image follow-up is interpreted as a fresh start. This violates the target rule that a revision of the current request must not create/replace a parallel deal state.

## Required next implementation gate

Add conservative Flutter-side context resolution before replacing a completed active deal:

1. If the current deal is incomplete, keep existing `answer()` behavior.
2. If the current deal is complete and incoming capture is the same intent/context/normalized subject, merge non-empty revision fields into the current deal and preserve already-known fields.
3. If the incoming request is clearly a different subject/intent, allow an explicit new active deal and do not keep two active sessions.
4. Voice, OCR and image-derived text must use the same rule.
5. Add regression tests for same-subject revision continuity and different-subject new-request behavior.
6. Re-run Flutter full CI and multimodal gate before calling this portion GREEN.

Point 1 remains IN PROGRESS until Flutter continuity, text/voice/image parity, duplicate-active-state enforcement and real in-app E2E are verified.