# Sprint 13 performance audit

## Risks found

* The previous sync service had no overlap guard, retry lifecycle, offline state, or conflict retention.
* Pagination used the rendered item count as its cursor and could duplicate or skip records when source identities repeated.
* Search and mock repositories have screens that can filter complete collections; large demo sets may block the UI.
* Router creation watches the complete authentication session and several screens still contain dense, eager demo lists.
* Images do not yet consistently specify decoded dimensions, and analytics is retained in memory.

## Improvements made

* Added bounded, duplicate-safe pagination with a stable cursor and concurrent-load prevention.
* Added indexed, debounced, cancellable local search and bounded suggestions outside widgets.
* Added focused Riverpod service providers, cache metrics, explicit TTLs, offline fallback, startup phases, and a single-run sync engine.
* Added non-blocking connectivity UI, lazy list screens, cache/image abstractions, migration/storage controls, and development-only metrics.

## Remaining limitations

The app deliberately uses process-memory mocks, so data does not survive a process restart. No isolate is used for index construction, image bytes are not decoded by the mock cache, and measured memory/rebuild values remain placeholders. Existing feature screens can adopt the new repository adapters incrementally without changing Sprint 1–12 behavior.

## Production recommendations

Profile release builds on representative low-end devices. Persist the queue transactionally, build large indexes in an isolate, cap analytics, size/decode images to layout bounds, add request deduplication and backpressure, use server revisions for conflicts, and monitor p50/p95 startup, screen, repository, search, sync, memory, and cache-hit metrics with privacy-safe sampling.
