# PODX

PODX is a Material 3 local-commerce application for Android, iOS, and the web. It
uses feature-first Clean Architecture, Riverpod state management, GoRouter
navigation, responsive navigation rails/bars, system-aware light/dark themes, and
English/Telugu localization.

## Getting started

1. Install Flutter 3.x (Dart 3.2 or newer).
2. Run `flutter pub get`.
3. Generate localization sources with `flutter gen-l10n`.
4. Run `flutter run -d chrome`, `flutter run -d android`, or `flutter run -d ios`.

If native runner folders are not already present in your checkout, generate the
standard host projects without replacing `lib` using:

```sh
flutter create --platforms=android,ios,web .
```

## ASKODOX Android signing

Stable ASKODOX Android builds use repository Actions secrets for the release
keystore, keystore password, key alias, and key password. The signing material
must never be committed to the repository. Main-branch CI uses these secrets to
produce the stable signed update APK and publish the in-app update channel.

## Architecture

- `config`: router, themes, and localization resources.
- `core`: app-wide providers and foundational utilities.
- `features`: isolated feature modules split into data, domain, application, and
  presentation layers where applicable.
- `models`: immutable shared domain models.
- `services`: integrations such as APIs, storage, and notifications.
- `shared`: reusable presentation components.

The catalog repository is deliberately replaceable through
`catalogRepositoryProvider`, keeping UI and bundled data sources decoupled.

## Product catalog

The Sprint 2 catalog is backed entirely by `assets/mock/catalog.json`. Its
repository parses the bundled categories, subcategories, brands, and products;
Riverpod providers expose search and filters without any network dependency.
Search results link to responsive product details, while missing or unavailable
products offer request, image-upload, and notification mock interactions.

## Sprint 15 beta workflow

PODX remains a controlled, mock-first beta. Copy `.env.example` only for local
configuration; never commit a populated environment file. Development uses the
mock repository implementations. Staging/production must replace them behind the
existing repository interfaces, and production configuration rejects a mock
backend. Compile-time/environment configuration must contain identifiers and
public endpoints only—not credentials.

Before submitting a change:

```sh
flutter clean
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
flutter build web
```

The architecture is feature-first: domain models/repository contracts are kept
independent from mock data, Riverpod providers connect application state, and
GoRouter owns guarded navigation. Local persistence/cache and the sync queue are
mock/offline foundations, not cloud durability. A real backend should implement
existing repository contracts, enforce permissions on the server, add migrations
and integration tests, and preserve current UI/provider APIs.

Release and QA references:

- [Technical audit](docs/SPRINT15_TECHNICAL_AUDIT.md)
- [Route inventory](docs/ROUTE_INVENTORY.md)
- [Localization and test report](docs/LOCALIZATION_AND_TEST_REPORT.md)
- [Performance summary](docs/PERFORMANCE_SUMMARY.md)
- [Beta readiness report](docs/release/BETA_READINESS_REPORT.md)
- [Platform release guide](docs/release/PLATFORM_RELEASE_GUIDE.md)
- [Beta release notes](docs/release/RELEASE_NOTES_BETA.md)
- [User guides](docs/user/USER_GUIDES.md)

Beta testers can use **Profile → Beta feedback**. Submissions stay in memory and
are never transmitted. The debug-only viewer is under Developer settings.
