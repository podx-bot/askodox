# Screen Guide — privacy and user control

**Model:** ASKODOX GUIDE → USER DECIDES → USER TAPS → ASKODOX OBSERVES THE PERMITTED RESULT → NEXT GUIDANCE.

## What ASKODOX never does
It never taps, types, submits forms, performs transactions, confirms payments, enters OTP/password/PIN/CVV, changes
device settings, bypasses Android or another app's protections, or runs multi-app actions for the user. Checks:
the service declares no gestures and calls no `performAction` / `dispatchGesture`; the highlight window is
`FLAG_NOT_TOUCHABLE`; the model's answer is validated against a fixed schema (instruction + a label that is on screen).

## Privacy Shield (mandatory, fail-closed)
1. **On the phone, first:** payment / banking / UPI apps (package list), password fields (`isPassword`), and
   sensitive words in labels or hints — OTP, password, PIN, UPI PIN, MPIN, CVV/CVC, card number, expiry, net banking,
   transaction password, payment authorisation / approve / confirm payment, 3-D Secure, mandate, Aadhaar, PAN, passport,
   biometric, security question (English, Telugu, Hindi). A match stops the capture before anything is kept or sent.
2. **On the server, again:** the same checks on the minimal payload (defence in depth).
3. **Result:** "Privacy Paused — sensitive information detected." + the full pause message. The highlight and voice stop.
4. **Resume:** only when the user presses Continue or double-taps the panel; leaving the screen does not resume. A
   sensitive screen after resume pauses again.
5. **Switch:** `companion.privacy_shield` is fail-closed — turning it off stops the Screen Guide, never runs it
   unprotected.
6. **Known limit:** detection is text/field based; a sensitive screen with no recognisable words and no password
   field could be missed. Screens protected with FLAG_SECURE are hidden by Android itself.

Sensitive-screen content is never sent to AI or backend, stored, logged, counted in analytics, screenshotted
(no screenshots exist) or put in crash reports (the service writes no logs with screen content).

## Data minimisation
| Need | API used | Narrower alternative considered |
|---|---|---|
| Know which button to press in another app | AccessibilityService, labels only | None on Android for other apps' UI; MediaProjection would capture full images (broader) |
| Show a hint over another app | accessibility overlay (no extra permission) | SYSTEM_ALERT_WINDOW (broader, not used for the guide) |
| Read typed values | **not used** | — |
| Screenshots / OCR | **not used** | — |

Payload: package, app name, up to 60 visible labels (80 chars) with role/clickable; editable fields only as their
hint. Server keeps the session (goal, counters) in memory for at most 30 minutes; End Guide deletes it.
Command Center receives aggregate counts only.

## Controls
| Switch | Effect |
|---|---|
| `companion.enabled` | all companion capabilities off; ASKODOX unaffected |
| `companion.floating_bubble` | bubble off (stops if running) |
| `companion.screen_guide` | Screen Guide off |
| `companion.accessibility` | kill switch for the accessibility-based guide (policy change) |
| `companion.privacy_shield` | fail-closed (off = no guide) |

Switching a capability off mid-guide ends it on the phone with: "Screen Guide is not available right now. ASKODOX works
normally…". No switch can grant or change an Android permission; the user controls those in Android settings.
