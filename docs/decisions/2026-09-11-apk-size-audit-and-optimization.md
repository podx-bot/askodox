# ASKODOX APK Size Audit and Optimization

Status: SAVED FOR LATER — DO NOT BLOCK CURRENT POINT 1 WORK
Date: 2026-09-11

## Context
Recent ASKODOX APK sizes have appeared in different ranges during development (roughly 40 MB, 60+ MB, and at times around 110 MB depending on build type/artifact). This note records the verified current findings so the topic is not lost and does not need to be re-explained later.

## Verified findings
- Recent official signed release assets observed in GitHub are approximately 64 MB (about 61 MiB), not 110 MB.
- The Android live workflow currently builds a single universal APK using `flutter build apk --release`.
- The workflow does not currently use `--split-per-abi` for release APKs.
- The current Android release Gradle configuration does not explicitly enable code/resource shrinking via `minifyEnabled` / `shrinkResources`.
- Bundled Flutter assets are currently small; `pubspec.yaml` declares only `assets/mock/catalog.json`.
- Therefore the larger APK size is more likely driven by universal native binaries/runtime/plugin packaging and build configuration than by a large set of bundled images/assets.
- A 110 MB artifact is likely a debug/universal/local artifact or another non-comparable build, and should not be treated as the current official release size without direct artifact verification.

## Future optimization plan
When APK-size optimization is resumed, audit and implement in this order without removing user-facing features merely to reduce size:
1. Produce an Android App Bundle (AAB) for Play distribution.
2. Produce split-per-ABI APKs for direct-install/update distribution where appropriate.
3. Enable and validate release code shrinking/minification where safe.
4. Enable and validate Android resource shrinking where safe.
5. Generate Flutter/Android size analysis and identify the largest native libraries/packages.
6. Check duplicate/unused assets, fonts, native libraries, and debug symbols.
7. Compare debug APK, universal release APK, split APKs, AAB estimated download size, and installed size separately.
8. Keep application ID and signing certificate compatible with the in-app updater.
9. Run installation/update/regression tests after every size optimization so no feature, language, voice, vision, document, map, or update flow is broken.

## Decision
APK-size work is intentionally deferred for now. Keep this record in GitHub as the canonical saved note. Resume only when current higher-priority implementation work reaches the appropriate release/performance stage.

## Source-of-truth relationship
This decision record is linked to the ASKODOX Master Architecture / Execution Tracker process. GitHub is the canonical persistent engineering source; ChatGPT conversational memory or Drive should not be the only storage for this requirement.
