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

## Production companion: natural human, 2D photo states (current default)
The procedural 3D rig is stylized/low-poly and the VRM "Human HD" model is
anime-style, so neither is the approved natural human. Until a natural human
3D model is ready, the companion is ONE natural human identity -- the "Smart
Advisor" (see SMART_ADVISOR_VROID_SPEC.md) -- shown as photographic states
in `assets/companion/human2d/` (`AskodoxHuman2d`), everywhere: Home, the
centre nav button, chat, floating companion, voice.
- Photos in this build: neutral, listening, thinking (generated from one
  base portrait; identity kept by editing that same image).
- speaking / explaining / happy use the neutral photo with a state treatment
  (speaking pulse driven by the voice level, explaining / success glow) until
  their photos are added: drop `speaking.jpg`, `explaining.jpg`, `happy.jpg`
  (512x512, same person, same framing) into the folder and add the names to
  `AskodoxHuman2d.bundled`.
- Motion: slow breathing, listening rings follow the microphone level,
  thinking dots, cross-fade between states; still with "remove animations".
- 3D personas and Human HD remain opt-in in Profile ("3D beta"); any 3D
  failure returns to this same human, never to the robot or another face.
  The robot appears only if the user picks it.
- The saved companion preference moved to `askodox.companion.v2`, so an
  older 3D pick is not carried over after the update.

## Companion as the app's entry point (Home + nav)
- Bottom navigation: Home | Explore | [companion face] | Orders | Profile.
  The centre item is the live companion (same mood as Main Chat via
  `askodoxCompanionLiveProvider`), not a microphone.
- Tapping it opens the action ring (`AskodoxCompanionHub`): Voice, Chat,
  Camera, Photos, Video, Files, Location. Tap outside, tap again or double
  tap closes it. The ring is never a permanent row on Home.
- Voice lives only in the companion: while listening, a tap on the companion
  (nav, Home stage or floating) stops it ("Tap the companion again to stop").
  The composer has no mic or attach button any more; attachments go through
  the one attachment pipeline.
- Home order: header (ASKODOX, location, language, notifications) -> earlier
  turns -> current results -> the companion with its contextual line ->
  the current question / follow-ups right above the input.

## In-app floating companion -- built, opt-in
Profile > "Floating companion in ASKODOX" (off by default): a small avatar
over the other ASKODOX screens (not on Main Chat, which already shows it).
Draggable, snaps to the nearest side, keeps clear of the status bar, the
bottom navigation and the keyboard, and remembers its side / height across
navigation and restarts (`askodox.companion.float.v1`). Tap = compact panel
(Ask about this, Voice, Chat, Camera, Photos, Video, Files, Location,
Minimize, Hide). Every action continues the SAME Main Chat conversation
(`AskodoxChatRequest.action` / `.ask`), same language and persona.
Evidence so far is widget tests only -- drag, snap, persistence, panel and
keyboard behaviour still need real-phone acceptance.

## Performance
The rig is procedural (0 bytes of model assets); release APK sizes are
written to `APK_SIZES.txt` by the Live Build. At runtime the median frame
time is watched and the friend steps down WITHOUT changing who it is:
level 1 = lighter motion (short bursts instead of continuous loops),
level 2 = still pose; after 2 minutes it tries the full level again
(`AskodoxCompanionPerformance.stepDown` / `maybeStepUp`). The robot is
shown only if chosen or if the human renderer fails; flat 2D only when 3D
is switched off or the phone's "remove animations" setting is on.
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
