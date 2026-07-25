# Platform release guide

## Identity checklist
App name is PODX. Approvers must supply Android application ID, iOS bundle ID, privacy/terms URLs, support email/site, final icon and splash assets. The current semantic version/build is read from `pubspec.yaml`. Never place credentials, keystores, certificates, passwords, or real legal URLs in Git.

## Android closed beta
Generate/review the native runner, approve application ID, minimum/target SDK and every permission. Generate a signing key outside the repository, protect it in the release secret store, configure Gradle through injected secrets, and back it up under dual control. Increment version code/name, run tests and `flutter build appbundle --release`, verify the signed artifact, then upload to Play internal testing before closed beta. Complete Data Safety, privacy-policy, store screenshots, content rating, audience, tester and release-note sections. Validate account deletion and subscription disclosures.

## iOS/TestFlight
Approve the bundle identifier, certificates, provisioning profile, team, version/build, entitlements, and each usage-description string. Store private keys only in the signing service/keychain. Archive through reviewed CI/Xcode, inspect privacy manifests and App Privacy answers, upload to TestFlight, add screenshots and review notes, and explain mock/demo access. Verify in-app account deletion and subscription disclosures before review.

## Web
Development: `flutter run -d chrome`. Production candidate: `flutter build web --release --base-href /`. Set base href to the deployment subpath when needed. Configure the host to rewrite unknown application paths to `index.html` while serving real static assets directly. Apply HTTPS, CSP/security headers after compatibility testing, immutable long cache headers only to fingerprinted assets, and short/no-cache headers to `index.html`. Inject non-secret environment configuration at build time and expose approved Privacy/Terms links. Test Chrome, Firefox, Safari, Edge, keyboard navigation, narrow mobile, tablet, and desktop widths.

These rules are provider-neutral and apply to Firebase Hosting, Cloudflare Pages, Netlify, Vercel, or a custom server. Provider syntax belongs in deployment infrastructure after a provider is selected; this sprint does not deploy automatically.
