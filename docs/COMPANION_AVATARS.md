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

## Human HD (beta) -- a real VRM human
Profile > Your companion > "Human HD (beta)": a VRM model rendered by
three.js 0.169 + @pixiv/three-vrm 3.5.5 inside Android's system WebView
(`assets/companion/engine.html`, ~700 KB; `companion_vrm_view.dart`). Same
mood / lip-sync / mic signals as every companion (newer states map to the
engine's closest body language). The light human rig shows while it loads
and takes over for the session on an engine error, a 25 s load timeout or
< 18 fps median. Default model: the stand-in "Seed-san" (VirtualCast, Inc.,
VRM Public License 1.0), downloaded at runtime -- NOT the final ASKODOX
character; our own VRoid export replaces it with
`--dart-define=ASKODOX_VRM_MODEL_URL=...` (spec: SMART_ADVISOR_VROID_SPEC.md).
Stylized anime-style human, not a photoreal scan.

## Floating bubble (Android) -- built, opt-in
Profile > "Floating ASKODOX bubble" (off by default):
- asks for Android's "Display over other apps" (SYSTEM_ALERT_WINDOW) on the
  system Settings page; nothing runs until it is granted;
- runs `AskodoxFloatingCompanionService` (foreground service, type
  specialUse -- Android requires a service + a silent notification to keep
  an overlay alive); started only while ASKODOX is on screen (Android 12+
  forbids starting it from the background);
- the bubble appears when you leave ASKODOX and hides when you return;
  drag to move, tap = back to ASKODOX, x = hide, notification "Turn off" =
  setting off; no timers (battery), no microphone, no screen capture.
Limits: voice from the bubble is not offered (the mic may only be used from
a visible screen or a microphone-type foreground service -- we do not run
one); Google Play requires the overlay + special-use declarations in the
Play Console before a store release; Android 7 and older: not available.

## Performance
The rig is procedural (0 bytes of model assets); release APK sizes are
written to `APK_SIZES.txt` by the Live Build. At runtime the median frame
time is watched and the friend steps down human 3D -> robot Lite -> flat 2D
for the session (`AskodoxCompanionPerformance`); motion runs only while a
state is active, and never with the phone's "remove animations" setting.
Profile > Companion performance shows, on the phone itself, with a live
companion animating: sustainable fps, build/raster p50/p90 (Flutter frame
timings), app RSS/PSS and free phone memory, battery %, temperature,
thermal state, battery saver, startup (Dart main -> first frame and process
start -> first frame) and "Copy report". GPU counters are not exposed to
apps; CI has no device, so these numbers come from the phone. The Human HD
engine lab (fps, worst frame, triangles, draw calls, JS heap) is linked
there.

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
