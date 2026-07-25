# Offline and performance architecture

## Read strategy and cache policy

PODX remains a local/mock application. Offline-capable repositories read the local cache first, use the replaceable mock remote source on a miss, then merge and refresh the cache. A failed remote read falls back to a useful cached value and marks it stale. `cacheFirst`, future-facing `networkFirst`, `staleWhileRevalidate`, `localOnly`, and `noCache` policies keep domain code independent from a persistence vendor. Expiry is configured per data family; stale records are displayed rather than discarded.

## Synchronization lifecycle

Mutations are applied optimistically, then represented by an idempotent queue key and one of create, update, delete, archive, or restore. Items move through pending, syncing, synced, failed, waiting-for-connection, conflict, or cancelled. Startup, resume, restored connectivity, refresh, and explicit Sync Now may invoke the foreground-only engine; its run guard prevents overlap. Failures remain visible and retryable. No background executor or real transport is used.

Buyer watchlist actions and seller price/stock edits can therefore update immediately while offline. Connectivity restoration processes the queued buyer action. A configured mock seller conflict pauses the price action until the user chooses a resolution, after which it can be requeued. Never remove an unsynced action silently.

## Conflicts and data-loss prevention

Resolvers support keep-local, keep-remote, latest timestamp, field merge, user choice, and admin review. Both values and timestamps remain available until resolution. Closed product requests and concurrently edited shop profiles should default to explicit review. Migration or cache corruption must not clear data automatically. Reset and clear-all actions require explicit user intent; the default clear-all operation preserves authentication and preferences.

## Migrations and storage

Local data has an explicit schema version, ordered migration steps, logs, a backup seam, and a failure result. The safe v1→v2 example normalizes the recent-search list without deleting it. The in-memory implementation can later be replaced behind the same contracts by Drift, SQLite, Isar, Hive, SharedPreferences, or secure storage.

## Pagination, search, images, and Riverpod

The reusable paginator loads bounded pages, uses stable source order, prevents duplicate identities, exposes retry/end states, and blocks concurrent loads. Search builds a token index outside widgets, debounces work, cancels obsolete generations, enforces two characters, removes duplicates, and limits results. Image cache keys include requested dimensions and leave seams for responsive CDN/WebP/AVIF delivery.

Services use focused Riverpod providers with singleton lifetimes, while connectivity is a stream and UI consumers watch only the state they need. Production screens should continue using lazy builders, stable keys, `const` widgets, and derived providers rather than a monolithic app state.

## Backend and production monitoring

To add a backend, implement the remote repository contracts and preserve cache → remote → merge semantics. Attach revision/ETag metadata, authenticated idempotency keys, transactional queue persistence, exponential backoff, and server-clock reconciliation. A durable database must encrypt sensitive fields and migrate through tested, reversible steps. Replace local metrics with a consent-aware monitoring adapter, sample traces, redact personal data, budget startup/search latency, size images server-side, and test memory on low-end devices.

## Mock flow coverage

* Buyer offline: cached indexed search → optimistic watchlist mutation → queue → connection restored → successful mock sync.
* Seller offline: optimistic price mutation → queue → configured mock conflict → visible local/remote comparison → chosen resolution → retry.
* Admin: stable, duplicate-free bounded pages with lazy load, refresh, retry, empty, and end-of-list states.
