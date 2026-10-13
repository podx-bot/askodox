# Push notifications (Firebase Cloud Messaging): readiness and test procedure

Current state (2026-10-13): **NOT CONFIGURED**. No Firebase project credentials exist and the Android app has
no FCM client yet, so phones cannot register for background push. While the app is open, it shows local,
silent notifications. Nothing here claims push works until step 5 passes on a real phone.

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
1. Create a Firebase project and add an Android app with package `com.askodox.askodox`.
2. Download `google-services.json`. It goes into the app build (CI secret / repo per the owner's choice);
   then the FCM client (`firebase_messaging`) is added and the app registers its token with
   `POST /api/me/push-token`. This is a code change and a new APK.
3. Create a service account with the "Firebase Cloud Messaging API Admin" role and put its JSON in the
   Railway variable `FIREBASE_SERVICE_ACCOUNT_JSON` (production only, never in the repo).

## Test procedure (real phone, after steps 1-3)
1. Install the new APK, sign in, allow notifications.
2. Command Center -> push readiness: expect `READY_UNVERIFIED` with `device_tokens >= 1`.
3. Test send to your own user id: expect `SENT` and a silent notification on the phone.
4. Turn notifications off in Profile -> Notifications, send again: expect `NOT_DELIVERED`, nothing on the phone.
5. Background the app, create a real request update: a silent notification arrives once; tapping it opens
   Updates on that item. Record the result in QA checks (#17) with a screen recording.
