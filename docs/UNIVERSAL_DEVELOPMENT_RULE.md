# ASKODOX — Permanent Universal Development Rule

**Status:** Mandatory architecture and implementation policy for all future changes.

## Core principle
Build every feature, bug fix, workflow, API integration, UI component, decision rule, matching algorithm and test as a **universal, context-aware, reusable, configurable capability** across every applicable domain, category, role, language and conversation. Never implement a solution only for the example currently under discussion.

**Universal First → Context-Aware → Reusable → Configurable → Tested Across Categories.**

## Assistant contract
ASKODOX is a universal Personal AI Advisor, Decision Partner, Buying Guide and Local Commerce Connector — not a shopping-only assistant or a directory of cards.

Understand → Enquire only when necessary → Reason → Advise Once → Respect Decision → Guide Continuously → Match & Discover when relevant → Result Board when useful → Connect with consent.

These are adaptive internal capabilities, not mandatory visible steps or a rigid questionnaire. Answer directly when appropriate. Never force commerce or a Result Board into non-commerce conversations. Never let cards replace reasoning or obscure chat.

## Implementation guardrails
- Use shared intent/context/reasoning and configurable category adapters, not category-specific hardcoding or keyword-triggered shop cards.
- One example (e.g., 100 sq.ft. vitrified tiles, ₹10k–₹20k) is a **regression test**, never a restriction of scope.
- Reuse existing services and contracts. Avoid duplicate pipelines.
- Respect user decisions; do not repeat advice after informed choice unless requested, materially changed circumstances or critical safety information.
- Keep conversation and relevant Result Board on the same screen. Support hidden/loading/expanded/minimized/restored/pinned/stale/archived states without clipping content.
- Differentiate estimates from verified inventory, prices, location, ratings and availability.
- Apply privacy, consent, localization, accessibility and failure handling across roles and categories.
- Tests must cover multiple unrelated domains, including non-commerce, products, services, business, finance, personal decisions, media attachments, Telugu/English, and Android layouts. No false claims of live/device validation.

## Definition of done
Every PR must explicitly report: (1) universal applicability, (2) configurable extension points, (3) cross-category tests, (4) regressions prevented, (5) any intentional domain-specific exceptions with justification, (6) remaining limitations. Reject a fix that only makes the demonstrated example pass.

This policy must be included in future developer/Claude implementation prompts and code review acceptance criteria.
