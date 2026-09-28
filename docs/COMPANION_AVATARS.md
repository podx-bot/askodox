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
idle, greeting, listening (hand at ear, leans in with mic level), thinking
(hand at chin, looks up), speaking (lip-sync from device TTS word ranges or
Sarvam audio position, talking hands), explaining (points at the result
cards), success (both hands up, smile), help (open palms, shrug, concerned
brows). Blink + glances every 2.5-6 s.

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
