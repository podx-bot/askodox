# iOS companion readiness

Status: **design only** (no iOS build exists in this repository today).

iOS has **no equivalent of Android's AccessibilityService** for third-party apps: an app cannot read or highlight
another app's user interface. ASKODOX will not attempt any workaround.

## Capabilities and the Apple-approved way to offer them
| Android capability | iOS approach | Notes |
|---|---|---|
| Read other apps' labels during a guide | **Not available** | No public API; not attempted |
| Highlight a control in another app | **Not available** | Replace with in-ASKODOX step cards and screenshots/illustrations |
| Floating bubble over other apps | **Not available** | Use widgets / Live Activities / notifications to return to ASKODOX |
| User-shared context | Share sheet / screenshot the user chooses to send (Share Extension) | Explicit per-item consent; Privacy Shield runs on the image text before upload |
| Screen recording guidance | ReplayKit broadcast extension exists but is high review risk; **not planned** for v1 | Would need its own disclosure and review |
| Voice guidance | AVSpeechSynthesizer / server TTS | Language from the user's locale |
| Quick actions | App Intents / Shortcuts / Siri for ASKODOX's **own** actions | Never acts inside other apps |

**Reduced-capability fallback:** the user describes the goal (or shares a screenshot on purpose), ASKODOX gives a
numbered step list with explanations; the user follows it in the other app and returns to ASKODOX for the next step.

## Before an iOS build
- App Privacy ("nutrition label") answers mirroring the Android Data safety mapping
- Purpose strings (microphone, location, photos) only for features that use them
- Sign in with Apple if other third-party sign-ins are offered
- No private APIs; review notes describing the guide as in-app guidance only
- Only Apple review can establish **STORE APPROVED**.
