# Localization and test report

## Localization
Generated Flutter localization is configured for English (`app_en.arb`) and Telugu (`app_te.arb`) with English as the source locale. Both catalogs should be compared in CI after every ARB edit using `flutter gen-l10n`. Core navigation, catalog, seller, monetization, analytics, and privacy vocabulary is represented, but legacy screens still contain hard-coded English. This is a known beta limitation, not falsely reported as full coverage. Currency/date/distance call sites should continue migrating to shared `intl` formatters. Manual QA must cover 200% text scaling and long Telugu strings.

## Test inventory
At audit time there are 22 test files: core architecture/offline/performance/security/environment, buyer, location, seller, search, watchlist, admin, analytics, monetization, communication, feedback, localization, and application smoke tests. New tests validate environment fail-closed behavior and local feedback state/reset. No tests are intentionally skipped in source. Known untested areas include real services, native permission flows, complete device E2E journeys, browser history/deep links, and store release artifacts.

Exact pass counts cannot be asserted because Flutter is unavailable in the audit container. CI must publish machine-generated test and coverage results rather than copying estimates into this document.
