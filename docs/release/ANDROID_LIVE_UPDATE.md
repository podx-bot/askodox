# ASKODOX Android live build and update path

The Android workflow generates the native Android host project in CI, verifies Flutter analysis/tests, builds a live REST-connected APK, and can publish a signed prerelease APK for testers.

## Required repository configuration

Set the public repository variable `API_BASE_URL` to the production Railway HTTPS backend URL. Optionally set `ANDROID_ORG` to the already-approved Android organization/package prefix. If it is not set, CI uses Flutter's `com.example` default.

For update-safe signed releases, configure these GitHub Actions secrets outside the repository:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never commit a keystore or signing password.

## Update behavior

A normal Android update works only when the new APK has the same application ID and is signed by the same certificate as the installed APK. The workflow always creates a debug artifact for diagnostics. It creates the stable signed release APK only when all release-signing secrets are present.

For a tester-friendly link, run **Android Live Build** manually with **publish_release=true**. When release signing is configured, the workflow creates a GitHub prerelease containing the signed APK and checksum. A tester can open that APK link on the phone and Android will offer an update instead of a fresh install when identity/signing match.

The build number is taken from the GitHub Actions run number, so each CI build receives a monotonically increasing Android version code within this workflow.
