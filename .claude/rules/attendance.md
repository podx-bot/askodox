---
paths:
  - "backend/app/services/pos_attendance.py"
  - "backend/app/api/routes/pos_frontdesk.py"
  - "lib/features/steps/presentation/checkin_steps_screen.dart"
  - "lib/features/steps/presentation/live_face_screen.dart"
  - "lib/features/steps/domain/live_face.dart"
  - "lib/features/business/presentation/biz_staff.dart"
  - "lib/features/location/**"
---

# Staff attendance: real place + live face (owner 2026-11-23)

The owner said: the location was not being taken, and a fingerprint or a plain photo can be cheated. These hold for
every shop, every staff phone, owner, manager and staff alike.

- Proof of a person = the LIVE face check (`AskodoxLiveCheck` + `live_face_screen.dart`, Google ML Kit on the phone,
  free, no paid API). Never bring back a fingerprint / phone lock or a plain selfie as proof: Android never tells an
  app whose finger it was, and a photo of a photo passes a selfie. The moves stay in a new random order every time,
  with a straight look between moves and the same tracking id throughout; a still photo must never pass
  (`test/features/steps/live_face_test.dart`).
- Location is compulsory when `require_location` is on: no GPS = not marked; a fake-GPS fix (`GeoPoint.mocked`) is
  sent as such and the server refuses it (403 `mock_location`) and tells the owner / managers; never drop the
  `mocked` field from a check-in body.
- Far from the shop is never marked silently: the phone shows the distance first, the person can only go "field work
  -- ask the owner" (`outside`), the row keeps note `outside` and the owner is told.
- The shop pin is set by the owner / manager in one tap standing in the shop (check-in step or Attendance setup);
  a fake-GPS fix is never taken as the shop.
- An older app's check-in (lock / photo) is kept with note `old_app` and the owner is told -- the shop never stops.
- Only the last straight frame leaves the phone (owner only, 90 days). Camera frames are deleted as soon as read.
- The live check proves a live person, not WHICH person. Face matching (an on-device embedding model) is the owner's
  call -- do not claim identity matching in any wording.
