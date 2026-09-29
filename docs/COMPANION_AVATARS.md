# ASKODOX companion avatars

## What ships in the app
- **Human 3D companions** (`lib/features/companion/companion_human.dart`): one
  shared human rig (head, eyes + irises, brows, nose, lips, cheeks, ears, hair,
  neck, torso, two-bone-IK arms, hands) rendered in real time by the lit-mesh
  engine in `companion_3d.dart` (perspective, lighting, depth sort, one
  `drawVertices` batch). 9 personas = the same rig with different skin, hair,
  outfit and accessories: Friendly Assistant, Professional Guide, Service
  Expert, Travel Guide, Finance Advisor, Education Mentor, Health & Wellness,
  Lifestyle Friend, Tech Expert. Generated in code: **0 bytes of model assets**.
- Stylized (low-poly, figurine-like) -- NOT photoreal scanned humans.
- **Robot (Lite)**: the earlier robot mesh, used when chosen, on slow phones,
  or if the human renderer fails. **3D off**: the flat 2D friend.

## States (driven by the one ASKODOX conversation state)
idle, greeting, listening (hand at ear, leans in with mic level),
understanding (voice being transcribed or an attachment being analyzed: eyes
down, both hands holding it), thinking (hand at chin, looks up), speaking
(lip-sync from device TTS word ranges or Sarvam audio position, talking
hands), suggesting (ASKODOX asked for the one detail it still needs: head
tilt, palm offered; the line names what it understood), explaining (points at
the result cards), guiding (a real Send request / Connect is in flight, via
the shared executor's `askodoxActionsInFlightProvider`), success (both hands
up, smile), help (open palms, shrug, concerned brows). Blink + glances every
2.5-6 s. Lines are en / te / hi (Hindi avoids gendered first-person verbs);
other languages use the chat labels.

## Floating / minimized companion outside the app -- NOT built
Android allows drawing over other apps only with the special
`SYSTEM_ALERT_WINDOW` ("Display over other apps") permission, granted by the
user on a Settings screen (not a runtime dialog). Google Play restricts it to
apps whose core function needs it, Android 12+ blocks touches through
untrusted overlays, and the mic can only be used from a visible activity or a
`microphone`-type foreground service with a persistent notification (Android
14+). A floating friend would therefore need: an explicit opt-in screen, the
permission, a foreground service (battery cost), and a Play policy
declaration. Until that is approved it is not implemented; the companion
lives docked in Main Chat only.

## Performance
The rig is procedural (0 bytes of model assets); release APK sizes are
written to `APK_SIZES.txt` by the Live Build. At runtime the median frame
time is watched and the friend steps down human 3D -> robot Lite -> flat 2D
for the session (`AskodoxCompanionPerformance`); motion runs only while a
state is active, and never with the phone's "remove animations" setting.
Real-phone FPS, memory, CPU/GPU and battery numbers are not measured in CI
(no device there) -- they come from phone testing.

## Optional avatar packs (richer models, not bundled)
Build with `--dart-define=ASKODOX_AVATAR_BASE_URL=https://<cdn>/avatars` and
host `<persona>.json` per persona (e.g. `financeAdvisor.json`). Format =
`AskodoxMesh.fromJson`:

```json
{"meta": {"rig": "human", "sleeve": 4280163071, "forearm": 4280163071},
 "parts": [{"name": "head", "color": "#B9825A",
            "vertices": [[x, y, z], ...], "triangles": [i, j, k, ...]}, ...]}
```

Part names must follow the rig (`head*`, `face_*`, `body_*`, `hand_l`,
`hand_r`; required: `head`, `face_mouth`, `hand_l`, `hand_r`) so the same
expressions, gestures and lip-sync animate it. Limits: <= 1.5 MB, <= 12,000
triangles, valid indices. Downloaded lazily once, cached in app support
storage; on any failure the procedural rig is used.

Photoreal humans (e.g. glTF/VRM with ARKit blendshapes) would need licensed
model files AND a glTF runtime (native or WebView) -- not included.
