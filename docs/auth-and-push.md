# Sign up, sign in, sign out, sessions and push (auth + FCM round)

Status labels follow the Integration Platform: **CODE READY** = built and tested automatically;
**PHONE VERIFIED** only after a real-phone test with evidence. Nothing below is phone verified yet.

## How it works

| Piece | Where | Notes |
|---|---|---|
| Phone numbers | `lib/core/auth/phone_number.dart` (`askodoxE164`) | India default (+91), any other country with `+`. Server key: `account_identity.phone_key` (Indian spellings share one account; other countries keep full digits). |
| Server OTP | `POST /onboarding/otp/send`, `/onboarding/otp/verify` | WhatsApp / SMS via `otp_delivery`; 45 s resend cooldown (`Retry-After`), 5 min expiry, 5 attempts. Demo number off in production. |
| Firebase phone sign-in | app `lib/core/auth/phone_auth.dart`; server `POST /onboarding/firebase/verify` (`firebase_id_token.py`) | The server verifies the Firebase ID token (RS256 against Google's public certs, `aud`/`iss` = project, times, `phone_number`). Offered only when `/onboarding/methods` says `firebase_phone_auth` (Railway `FIREBASE_PROJECT_ID` + `ASKODOX_FIREBASE_PHONE_AUTH=yes`, because Google bills the SMS) AND the APK has the Firebase values. Setup problems fall back to the server OTP. |
| One place a session is made | `onboarding_auth.signed_in` | one account per number, signed token, `returning` + saved `profile` (the app restores it, never overwrites it). |
| Sign-up | onboarding screen | language -> number -> code -> name -> roles (buyer always; seller / services / work / delivery optional). |
| Persistent login | `main.dart` `_verifySession` -> `GET /api/me/session` | 401 -> signed out on this phone; offline -> kept. |
| Sign-out | `lib/core/auth/sign_out.dart` | Profile -> Settings & Privacy -> **Sign out** (last item) and side menu -> **Logout**: confirm -> `POST /api/me/logout` (revokes THIS session, unlinks this phone's push token, deletes nothing) -> FCM token deleted on the phone -> Firebase sign-out -> account data on the phone put away (`askodox.stash.<account>.*`, max 3 accounts, restored when the same account signs in) -> app restarts with fresh state on the sign-in screen. |
| Push | `lib/services/push_registration.dart`, `push_service.py` | token after sign-in (Android 13 permission asked then), refresh, foreground shown once (message id), background / closed shown by Android on channel `askodox_updates`, tap opens the in-app route. |
| One-phone push test | Profile -> Notifications -> **Send a test notification to this phone** (`POST /api/me/push-test`) | only the caller's own devices, 3 per 10 min, obeys their switches. |
| In-App Messaging | `lib/services/in_app_messaging.dart` | opt-in (Notifications -> Offer messages in the app); collects nothing until then (manifest); trigger `askodox_app_open` at most once per 20 h. Text / image only: video ads stay in the ASKODOX native content system. |
| Developer Diagnostics | Profile -> Settings & Privacy (development builds only) | FCM token + Firebase Installation ID, masked until "Show full values", copy on tap, never logged. Not in production release builds (`APP_ENV=production`). |

## Owner steps (nothing is invented; each is CONFIGURATION REQUIRED until done)
1. Firebase Console -> create / open the project -> Add app -> Android, package `com.askodox.askodox`.
2. Add the release signing fingerprints (Project settings -> Your apps -> Add fingerprint):
   - SHA-1 `63:37:E1:1A:34:E7:55:31:20:77:EF:7D:52:B2:69:AA:A1:7B:19:0A`
   - SHA-256 `72:7B:4A:66:22:F0:F9:DF:A3:36:36:DA:4F:26:61:62:E9:CA:B7:50:FB:DF:24:00:04:E9:B2:1F:56:C9:57:CF`
3. GitHub -> Settings -> Secrets and variables -> Actions -> **Variables**: `FIREBASE_API_KEY`, `FIREBASE_APP_ID`,
   `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` (public app identifiers). The next APK build includes them.
4. Railway -> production -> podx-ai-connect -> Variables: `FIREBASE_SERVICE_ACCOUNT_JSON` (push sender; never in
   GitHub) and `FIREBASE_PROJECT_ID`.
5. Only if you want Google to send the sign-in SMS: Firebase -> Authentication -> Sign-in method -> Phone ->
   Enable (Blaze plan), then Railway `ASKODOX_FIREBASE_PHONE_AUTH=yes`. Otherwise sign-in keeps using the
   server OTP (WhatsApp template / SMS -- see the Setup Wizard).

## Safe push test (ONE development device; never a campaign to all users)
- Simplest, works in the release APK: Profile -> Notifications -> Send a test notification to this phone.
- Firebase Console way: Messaging -> New campaign -> Notifications -> fill title / text -> **Send test message**
  -> paste the FCM registration token from Developer Diagnostics (a development build) -> Test. Do **not**
  press Review / Publish (that sends to everyone).
- Check three states: app open (foreground: shown once), app in background, app swiped away (terminated).
  Tap each notification: the screen in its `route` opens (test messages without a route open the app).

## Phone test checklist (owner, real phone; record each with a screen recording)
1. New number: language -> number -> code -> name -> roles -> Home.
2. Wrong code -> "Incorrect OTP."; wait 5 min -> "OTP expired"; Resend only after the timer.
3. Profile -> Settings & Privacy -> Sign out -> Cancel (nothing happens) -> Sign out -> sign-in screen; Back
   does not reopen Profile.
4. Sign in again with the same number: name, listings, orders, roles, chats are back.
5. Side menu -> Logout -> sign in with a DIFFERENT number: none of the first account's data is visible.
6. Close and reopen the app while signed in: still signed in.
7. Notifications: allow on first prompt (Android 13+); then deny on another phone/test -> app works, test send
   says notifications are off.
8. Push test in foreground, background and closed; tap opens ASKODOX.
9. In-App Messaging (after Firebase setup): switch "Offer messages in the app" on, Firebase "Test on device"
   with the Installation ID -> the message shows once.
