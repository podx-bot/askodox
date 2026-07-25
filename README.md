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

## Architecture

- `config`: router, themes, and localization resources.
- `core`: app-wide providers and foundational utilities.
- `features`: isolated feature modules split into data, domain, application, and
  presentation layers where applicable.
- `models`: immutable shared domain models.
- `services`: integrations such as APIs, storage, and notifications.
- `shared`: reusable presentation components.

The demo home repository is deliberately replaceable through
`homeRepositoryProvider`, keeping UI and data sources decoupled.
