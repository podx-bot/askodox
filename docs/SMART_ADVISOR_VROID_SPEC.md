# ASKODOX "Smart Advisor" — VRoid Studio build sheet (free route)

Goal: an ORIGINAL, commercially safe, human-style female ASKODOX companion
that matches the approved "Avatar 2 – Smart Advisor" direction, exported as a
VRM the app animates (expressions, lip-sync, gaze, gestures). Built only from
VRoid Studio's own editor + presets (no third-party paid/borrowed assets, no
likeness of a real person). Confirm VRoid Studio's current terms of use for
commercial use of exported models before release.

## 1. Character (match "Avatar 2 – Smart Advisor")
- Friendly, confident, trustworthy advisor; approachable smile at rest.
- Adult woman, South-Asian features: warm medium-brown skin, dark brown eyes,
  natural brows, soft (not anime-exaggerated) proportions.
  VRoid Face: reduce eye size ~15-25%, lower eye "anime" highlights,
  natural nose/mouth sliders, subtle blush only.
- Hair: dark brown/black, shoulder length or neat low ponytail; avoid
  extreme strands (fewer hair groups = better performance).
- Outfit: smart-casual professional — navy or teal blazer/jacket over a
  plain top, ASKODOX purple (#6C4DFF) accent (e.g., top or pin). No logos
  other than ASKODOX, no text.
- Upper body is what the app shows most (head, shoulders, hands); keep
  hands natural (default hand shape).

## 2. Expressions (keep ALL VRoid defaults — the app drives them)
aa, ih, ou, ee, oh (lip-sync) · blink, blinkLeft, blinkRight · happy,
sad, angry, surprised, relaxed, neutral · lookUp/Down/Left/Right.
Tune "happy" to a warm smile (not closed-eye anime joy).

## 3. Export (VRoid Studio > Export > VRM)
- Format: **VRM 1.0** (0.x also works).
- Reduce polygons: hair ~ 50%, clothing reduction on; target
  **<= 25,000 triangles** total.
- Texture atlas **2048** (1024 if the file is > 8 MB); materials: reduce.
- Remove unused blend shapes: OFF (keep expressions).
- Metadata: Title "ASKODOX Smart Advisor", Author "ASKODOX",
  Avatar permission "Only author", Commercial use "Allow (corporation)",
  Redistribution "Disallow", Modification "Allow".
- Target file size: **<= 8 MB**.

## 4. Hand-off (no terminal needed)
Upload the .vrm (and the .vroid project file) to Google Drive and share the
link, or add it to the repo via GitHub web upload under
`assets/companion/source/`. The app downloads the model lazily (cached),
so it does not bloat the APK.

## 5. What the app already does with it
Moods from the ASKODOX conversation state (listening, thinking, speaking,
explaining, success, help, greeting, idle), lip-sync from the existing voice
hooks (device TTS word ranges / Sarvam audio position), blink + gaze,
pause in background, fallback to the Lite companions if WebGL is slow or
unavailable.
