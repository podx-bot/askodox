# Push notifications (Firebase Cloud Messaging): readiness and test procedure

Current state (2026-10-14): **NOT CONFIGURED**. No Firebase project credentials exist. The Android FCM client
is built (`lib/services/push_registration.dart`) but switches on only in an APK built with the Firebase values,
so phones cannot register for background push yet. While the app is open, it shows local,
silent notifications. Nothing here claims push works until step 5 passes on a real phone.

Update (auth + FCM round): one-phone self test (Profile -> Notifications -> Send a test notification to this
phone), message de-duplication, background / closed-app notifications on `askodox_updates`, opt-in Firebase
In-App Messaging and development-only Developer Diagnostics. Full owner steps and the phone checklist:
`docs/auth-and-push.md`.

## Alerts sent (each obeys the user's notification switches, once per event)
- Orders / booking requests and replies.
- Demand opportunities for sellers.
- Delivery / ride: partner accepted, picked up, arrived, delivered; quote accepted.
- Subscription and Travel Radio: pass / plan activated, payment refunded.

## What is already built
- Server sender: `backend/app/services/push_service.py` (FCM HTTP v1, silent channel `askodox_updates`, once
  per event, dead tokens removed). It sends nothing without `FIREBASE_SERVICE_ACCOUNT_JSON`.
- Device token registration: `POST /api/me/push-token` and `DELETE /api/me/push-token` (signed in).
- The user's own switches: Profile -> Notifications (`PUT /api/me/notification-settings`); every send obeys them.
- Android 13+ permission prompt (`POST_NOTIFICATIONS`, `requestNotificationPermission`).
- Staff readiness: Command Center `GET /admin/cc/push/readiness` reports `NOT_CONFIGURED`,
  `SERVER_READY_NO_DEVICES` or `READY_UNVERIFIED`, never "working".
- Staff test send: `POST /admin/cc/push/test {"user_id": "..."}` (integrations:manage). It sends only to that
  user's registered devices, respects their switches, is audited, and reports what FCM accepted.

## Owner / external steps (credentials are never invented)
1. Firebase console: create a project and add an Android app with package `com.askodox.askodox`.
2. From that Android app's settings, copy four values into **GitHub -> Settings -> Secrets and variables ->
   Actions -> Variables**:
   - `FIREBASE_API_KEY`
   - `FIREBASE_APP_ID`
   - `FIREBASE_SENDER_ID` (the project number)
   - `FIREBASE_PROJECT_ID`

   They are public client identifiers, not secrets, and no `google-services.json` is committed. The next Live
   Build APK then registers its token with `POST /api/me/push-token` and refreshes it automatically.
3. Firebase -> Project settings -> Service accounts -> generate a key. Put the JSON in the Railway variable
   `FIREBASE_SERVICE_ACCOUNT_JSON`, or paste it in Command Center -> Integrations -> Firebase push (encrypted).
   Never commit it to GitHub.

## Test procedure (real phone, after steps 1-3)
1. Install the new APK, sign in, allow notifications.
2. Command Center -> push readiness: expect `READY_UNVERIFIED` with `device_tokens >= 1`.
3. Test send to your own user id: expect `SENT` and a silent notification on the phone.
4. Turn notifications off in Profile -> Notifications, send again: expect `NOT_DELIVERED`, nothing on the phone.
5. Background the app, create a real request update: a silent notification arrives once; tapping it opens
   Updates on that item. Record the result in QA checks (#17) with a screen recording.
