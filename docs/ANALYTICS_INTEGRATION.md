# PODX analytics integration guide

## Current architecture

Sprint 12 uses provider-neutral domain interfaces under `features/analytics/domain`. Riverpod exposes only those interfaces; local mock implementations hold privacy-safe events in memory and return aggregated demonstration metrics. No analytics SDK, network event pipeline, external chart API, production identifier, revenue calculation, or export is included.

Events use the past-tense `AnalyticsEventType` vocabulary (for example `productSearched` and `priceComparisonOpened`). Add a typed enum case rather than an arbitrary provider-specific name. Properties should be low-cardinality business context such as a catalog product ID, result count, category, radius band, or screen name.

## Privacy rules

Never attach names, phone/mobile numbers, addresses, email, OTP values, authentication or refresh tokens, uploaded documents/images, precise coordinates, exact home locations, free-form buyer text, or stable tracking identifiers. `MockAnalyticsService` removes known sensitive keys as defense in depth, but callers must avoid collecting them in the first place. Seller reports are aggregated; they must never allow drilling into an individual buyer. Admin financial values are conspicuously demo data.

Before production, create a schema registry, review every event with privacy/security teams, test allow-listed property names and types, check consent and deletion, verify retention limits, inspect a representative event stream for accidental PII, and validate opt-out behavior on every supported platform.

## Adding a provider later

Implement `AnalyticsService` in the data layer for Firebase Analytics, Google Analytics, Mixpanel, Amplitude, or a custom pipeline. Translate the domain enum at that boundary, enforce the same property allow-list, honor `AnalyticsPrivacySettings`, inject the implementation through `analyticsServiceProvider`, and keep vendor packages and types out of domain and presentation code. Do not send locally accumulated demo events automatically.

## Aggregation and BI

Seller engagement metrics combine non-identifying counts such as product views, searches, comparisons, watchlists, offer clicks, and requests. Conversion and demand-to-supply figures are explicitly proxies, not sales attribution. A future warehouse adapter should implement the admin, funnel, search-intelligence, report, and data-quality repositories over pre-aggregated datasets with role-based access, minimum cohort thresholds, audit logs, and suppression for small groups.

To replace a mock repository, implement the matching domain interface, map backend DTOs to immutable domain models, add loading/error/offline behavior, and override its Riverpod provider. CSV/PDF buttons remain placeholders until a reviewed local export abstraction exists.
