# ASKODOX Screen Guide — Google Play Accessibility declaration pack

Status: **PLAY CONSOLE DECLARATION READY** (drafts below). Nothing has been submitted. Only Google review can
make this **STORE APPROVED**.

## Classification

ASKODOX Screen Guide is a **non-disability** use of the AccessibilityService API (a general step-by-step helper).
`android:isAccessibilityTool` is **not** set and must not be set: ASKODOX is not primarily a tool for people with
disabilities.

## How the service is built (facts the declaration relies on)

| Item | Value |
|---|---|
| Service | `com.askodox.askodox.AskodoxScreenGuideService` |
| Declared in | Play-distributed builds only (CI `include_screen_guide=true`); sideloaded phone-test builds do not declare it |
| Event types | window state changed, window content changed |
| Capabilities | `canRetrieveWindowContent=true`; **no** gestures, no `performAction`, no key filtering, no fingerprint gestures, no text input |
| When it reads | only while the user runs a guide they started in ASKODOX; otherwise every event is ignored |
| What it reads | visible labels / content descriptions and roles of the foreground app; editable-field **values are never read** |
| On-device Privacy Shield | password fields, OTP / PIN / UPI PIN / CVV / card / bank / payment-authorisation / Aadhaar / ID words (English, Telugu, Hindi) and payment / banking apps pause the guide before anything is sent |
| Sent to ASKODOX | goal text + visible labels of the current (non-sensitive) screen, over HTTPS, bound to the signed-in user |
| Stored | nothing from screens; anonymous daily counters only |
| Overlays | small guide panel and a non-touchable outline (accessibility overlay type); never full-screen |
| User control | Continue / double-tap resumes, End Guide stops, Android settings switch disables |

## Play Console — Permissions declaration (draft text)

**Core functionality that requires the Accessibility API:**
> ASKODOX Screen Guide helps people complete tasks in other apps step by step. While the user runs a guide they
> started in ASKODOX, the service reads the visible button and label names of the app on screen so ASKODOX can show
> and say which control to press next, with an outline around it. The user performs every action; ASKODOX never taps,
> types, submits, pays or changes settings. The feature is optional; ASKODOX works fully without it.

**Data accessed and why:**
> Visible labels and roles of the current screen, only during an active guide, to determine the next step. Values
> typed into fields are never read. Screens with passwords, OTPs, PINs, UPI PINs, card, bank, payment authorisation or
> identity data, and payment or banking apps, are detected on the device and the guide pauses without reading or
> sending them.

**Data shared:**
> The user's goal and the visible labels of the current non-sensitive screen are sent to ASKODOX servers (and the AI
> model ASKODOX uses) to compute the next step. They are not stored or used for advertising.

## Store listing disclosure (draft)
> **Screen Guide (optional):** step-by-step help in other apps. Uses Android's Accessibility service, only while you run
> a guide, to read on-screen button names so ASKODOX can show you what to press. You press every button. Pauses on
> password, OTP, PIN, card, bank and ID screens. No screenshots; nothing from your screen is stored.

## Reviewer instructions (draft)
1. Install from the Play test track and sign in (reviewer test account to be provided in Play Console).
2. Profile → **Screen Guide (beta)** → read the disclosure → **AGREE & CONTINUE** (or **NOT NOW** to see that ASKODOX
   keeps working).
3. Tap *Turn on "ASKODOX Screen Guide"* → Android Accessibility settings → enable it → return.
4. Type "turn on Wi-Fi" → **Start guide** → open Android Settings: the panel shows the next step and outlines it.
5. Open any login screen with a password field: **Privacy Paused — sensitive information detected.** appears.
6. Leave it, press **Continue** (or double-tap the panel) to resume; press **End Guide** to stop.

## Demo video checklist
- [ ] Prominent disclosure shown **before** Android settings, with AGREE & CONTINUE / NOT NOW
- [ ] NOT NOW path: ASKODOX still usable
- [ ] Enabling the service in Android settings
- [ ] A guided step with the outline; the user taps (not the app)
- [ ] Privacy pause on a password / OTP screen; explicit Continue
- [ ] End Guide; disabling the service in Android settings

## Data safety mapping (draft)
| Data type (Play) | Collected | Shared | Purpose | Optional | Retention |
|---|---|---|---|---|---|
| App activity → other actions (screen labels during a guide) | Yes, ephemeral | Processed by ASKODOX's AI provider | App functionality | Yes | Not stored |
| App info and performance → diagnostics (anonymous counters) | Yes | No | Analytics / reliability | Yes | Aggregated daily |
| Personal info, financial info, messages, photos, contacts | **No** (Privacy Shield blocks sensitive screens) | No | — | — | — |

## Privacy policy must state
- what Screen Guide reads, when, and that it is optional;
- that screen labels go to ASKODOX servers / AI only to compute the next step and are not stored;
- sensitive-screen pausing and that typed values are never read;
- how to stop (End Guide) and disable (Android settings);
- the AI processor used and its role (to be named once the provider contract is final).
