# ASKODOX Verification Gate

This document is a mandatory product gate for every user-facing ASKODOX feature.

## Core rule
A requirement is NOT complete because it was discussed, documented, coded, or built.

A feature is complete only after this chain passes:

Requirement -> Code -> Build -> Actual Screen -> Behaviour Test -> PASS -> VERIFIED/LOCKED

## Status vocabulary
- PLANNED: agreed direction, not implemented yet.
- IN PROGRESS: code/design work is actively being changed.
- READY FOR TEST: implementation/build exists but the actual user experience is not yet verified.
- VERIFIED/LOCKED: actual app behaviour/visuals were tested and match the requirement.

Do not call a feature complete before VERIFIED/LOCKED.

## Universal Decision Brain acceptance rule
ASKODOX must not behave primarily like a scripted FAQ, rigid chatbot, static form, or generic e-commerce filter.

Expected reasoning loop:
Understand -> Remember -> Think -> Clarify only when necessary -> Find/Match -> Compare -> Recommend -> Explain why -> Help complete the action -> Learn from outcome

Acceptance requirements:
1. Same question does not always force the same fixed answer.
2. User context, previous conversation, location, budget, urgency, preferences and constraints are reused when known.
3. ASKODOX must not ask again for information already known.
4. Clarifying questions are asked only when the missing detail materially changes the recommendation.
5. The response should normally identify a best-fit recommendation, explain why, and offer meaningful alternatives when useful.
6. Universal structured deal/job/service/location data may exist internally, but the user experience must remain natural and conversational.
7. User retains final choice and control.

## Mandatory live scenarios
The following scenarios must be tested in the actual app, not only as unit tests:

### Product decision
Input example: `₹15,000లో మంచి phone కావాలి`
PASS only if ASKODOX uses known context, asks only useful missing preference(s), compares suitable options, and recommends a best fit with reasoning instead of dumping a generic list.

### Nearby/local need
Input example: `I want to buy chicken nearby`
PASS only if ASKODOX understands location intent and relevant constraints, uses location safely, and finds/recommends suitable nearby options rather than only opening a static category.

### Jobs/services
PASS only if ASKODOX understands the person's need, role, location, urgency and constraints, then helps find or match useful opportunities/providers with reasoning.

### Language
PASS only if ASKODOX can understand the user's current language and reply naturally in that language without forcing a fixed India-only language set. Language can change mid-conversation without losing context.

### Location
PASS only if location is treated as global context, not India-only logic. Nearby search, distance, routing/pickup/delivery and local matching should use a provider abstraction so map providers can be changed or combined.

## Visual verification
Any user-facing visual requirement is not verified by code inspection alone.

For UI changes verify:
- actual installed/current build
- correct ASKODOX branding
- no unintended PODX user-visible text
- no overlapping/double-pane layout
- readable input/output in light and dark modes where supported
- intended logo/icons/colors/animations when part of the requirement
- loading states do not appear stuck without useful feedback

If the actual screen does not match the agreed requirement, status returns to IN PROGRESS.

## Online/offline commerce rule
- Local/offline payments do not need to pass through ASKODOX by default; buyer and seller can transact directly.
- ASKODOX's role is to understand, compare, recommend, connect and help complete the need.
- Online options can use eligible affiliate/deep links where appropriate.
- The user's best-fit choice takes priority over affiliate commission.

## Global product rule
ASKODOX is an international universal assistant. Local commerce is one execution layer, not the product boundary.

Architecture must avoid hard-coding a single country, language, currency, map provider, marketplace or payment gateway as the universal assumption.

## Change discipline
When a fix fails twice, change the method instead of repeating the same path.

Every future user-facing feature should reference this gate during implementation and testing.
