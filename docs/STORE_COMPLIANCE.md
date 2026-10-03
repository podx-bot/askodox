# Store compliance module

States used everywhere (never collapsed):
**CODE READY → LOCAL TEST VERIFIED → SIDELOAD TEST VERIFIED → PLAY CONSOLE DECLARATION READY → PLAY STORE REVIEW
REQUIRED → STORE APPROVED.** Only Google / Apple review can set STORE APPROVED.

## APK evidence (CI workflow `APK audit`)
`tool/apk_audit/audit.py` dumps identity, label, signing, SDK levels, every permission and component of real signed
APKs and diffs builds. Run it for every phone-test build.

## Google Play Protect finding for build 1272 (2026-09-30)
| Fact (from the audit) | 944 (prod) | 1271 | 1272 |
|---|---|---|---|
| label | ASKODOX | ASKODOX | ASKODOX |
| application class | android.app.Application | android.app.Application | android.app.Application |
| signing certificate | same | same | same |
| permissions | 8 | 11 | 11 (identical to 1271) |
| accessibility service | no | no | **yes** (only difference) |

1272's only change against 1271 (which installed) is the AccessibilityService. Google Play Protect's enhanced fraud
protection blocks apps installed from internet-sideloading sources (browsers, messaging apps, file managers) that
request BIND_ACCESSIBILITY_SERVICE (among a small set of sensitive permissions); the reported warning ("can request access to sensitive data") is consistent with
that programme. Conclusion: **the accessibility service is the evidenced cause**; sideload reputation of a new build may contribute
and cannot be measured from here. The label was correct in the APK; "android.app.Application" was the generic
Application class used by every build — builds from 1273 use `com.askodox.askodox.AskodoxApplication`. Whether that
changes the text Play Protect prints is **not verified**.

Response (no bypass): sideloaded phone-test builds do **not** declare the service; it is added only for
Play-distributed builds after the Play accessibility declaration (`include_screen_guide`). Play Protect is never
disabled or worked around, and users are never told to disable it.

## Android checklist
- [x] Label/identity: ASKODOX, `com.askodox.askodox`, named Application class
- [x] Same signing key and package across builds (CI verifies against the production APK)
- [x] targetSdk follows Flutter stable (36 in 1272); review yearly Play target-SDK deadline
- [x] Permissions minimised: removed FOREGROUND_SERVICE_LOCATION (plugin-added, unused)
- [ ] Play build: remove REQUEST_INSTALL_PACKAGES (sideload in-app updater only; Play restricts it)
- [ ] Play build: SYSTEM_ALERT_WINDOW + specialUse FGS for the optional bubble need a Play declaration or removal
- [x] Accessibility: prominent disclosure + affirmative consent before Android settings; not isAccessibilityTool
- [ ] Play Console: Permissions declaration, Data safety, privacy policy URL, demo video (drafts in
      `docs/ANDROID_ACCESSIBILITY_DECLARATION.md`) — **PLAY STORE REVIEW REQUIRED**
- [x] Kill switches per companion capability (`docs/SCREEN_GUIDE_PRIVACY.md`)

## Permission register (1273 default build)
| Permission | Why | Type |
|---|---|---|
| INTERNET | backend | normal |
| RECORD_AUDIO | voice in chat | dangerous (runtime) |
| ACCESS_FINE / COARSE_LOCATION | nearby results, foreground only | dangerous (runtime) |
| POST_NOTIFICATIONS | request updates | dangerous (runtime, 13+) |
| SYSTEM_ALERT_WINDOW | optional floating bubble | special (user-granted) |
| FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE | keeps the optional bubble alive | normal / declared use |
| REQUEST_INSTALL_PACKAGES | sideload in-app updater (not for Play) | special |
| DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION | androidx internal, signature | signature |

## AI / data-processing disclosures
Chat, voice (Sarvam), vision and Screen Guide steps are processed by ASKODOX servers and their AI providers; the privacy
policy and Data safety form must name the categories and that data is not sold or used for advertising.

## Global language / country readiness
- Language is the user's locale (BCP-47) end to end in the Screen Guide; server rule texts exist for English and
  Telugu, the AI answers in any language it supports, TTS uses `Locale.forLanguageTag`. Other app areas still carry
  English/Telugu/Hindi/Odia strings; adding a language = adding ARB strings (no code change).
- Country settings (currency, units, date formats, service availability, compliance rules) must come from a
  per-country configuration (`ASKODOX_SEARCH_COUNTRY` exists today for discovery). No legal requirement is hard-coded
  or invented; unknown countries fall back to safe defaults with the feature off.

## Apple
See `docs/IOS_COMPANION_READINESS.md` (no Accessibility-service equivalent; reduced in-app fallback).
