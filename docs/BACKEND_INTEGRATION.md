# PODX backend integration guide

## Current architecture

Sprint 8 keeps PODX in **mock mode**. Domain/presentation code depends on contracts; Riverpod providers in `lib/core/providers/backend_providers.dart` select mock implementations. Provider SDK objects must never enter domain or presentation code. DTO and local mappings live in the data layer.

Configuration is represented by `AppConfig`. Copy `.env.example` to a git-ignored local file and inject parsed values at application startup. CI/deployment secret stores—not source control—must hold future URLs, keys, OAuth identifiers, and credentials. Configuration validation intentionally rejects an incomplete remote setup and mock production mode.

## Adding a provider

1. Create a separate data adapter package/folder (for example `data/supabase`, `data/firebase`, `data/rest`, or `data/graphql`).
2. Implement authentication and the repository/data-source interfaces. Convert SDK/database records to provider-neutral DTOs, then domain models.
3. Override the relevant Riverpod providers at the root `ProviderScope`; do not change UI code.
4. Add contract tests that run against the adapter and preserve pagination/error semantics.

For **Supabase**, initialize its client only in the Supabase adapter and connect Auth, Postgres/RPC, Storage, and PostGIS queries there. For **Firebase**, keep Auth, Firestore, Cloud Storage, and GeoFlutterFire/geohash behavior inside Firebase adapters. A REST adapter should use `ApiClient`; a GraphQL adapter should translate operations and cursor pagination to the same contracts.

## Authentication and sessions

Connect mobile OTP, email, social identity, refresh, logout, and deletion through `AuthenticationService`. Persist only the minimum refresh/session material through a platform secure `TokenVault`; the in-memory/local mock store is **not secure storage**. Restore sessions through `SessionManager`, validate expiry, and let server responses remain authoritative. Never log OTPs or tokens.

## Storage and location

Implement `FileStorage` for product images, shop photos, verification documents, request images, and complaint evidence. Enforce type, size, malware/content checks, ownership, short-lived upload authorization, and access rules on the server. Connect geospatial queries through `LocationQueryDataSource`; server-side radius filtering and pagination must be authoritative.

## Security responsibilities

Client validation is only a usability feature. The backend must authenticate every protected request; authorize roles and resource ownership; validate and sanitize input; enforce rate limits; validate files; protect secrets; encrypt sensitive data; provide deletion/retention controls; and maintain tamper-resistant seller/admin audit logs. Use least-privilege database/storage rules and test denial paths. Never trust a client-supplied role.

## Migration checklist

- Select environment/provider without committing secrets.
- Replace providers incrementally, retaining mocks for tests and demos.
- Map network/database errors to `ApiFailure` and preserve English/Telugu UI messaging.
- Implement cursor pagination for catalog, nearby shops, listings, alerts, requests, and moderation.
- Implement an observable durable sync queue and conflict policy before background sync.
- Add emulator/staging integration tests, security-rule tests, monitoring, backups, and incident procedures before production.
