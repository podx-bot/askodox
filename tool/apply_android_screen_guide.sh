#!/usr/bin/env bash
# Adds the ASKODOX Screen Guide accessibility service to the manifest.
# ONLY for builds distributed through Google Play after the Play Console
# accessibility declaration is approved. Sideloaded phone-test builds must
# not include it (Play Protect blocks internet-sideloaded apps that declare
# BIND_ACCESSIBILITY_SERVICE). Never used to evade any security control.
set -euo pipefail
MANIFEST="android/app/src/main/AndroidManifest.xml"
python3 - "$MANIFEST" tool/android_screen_guide_service.xml <<'PY'
import sys
from pathlib import Path
p, block = Path(sys.argv[1]), Path(sys.argv[2]).read_text()
s = p.read_text()
if "AskodoxScreenGuideService" not in s:
    s = s.replace("        <provider", block + "        <provider", 1)
if "AskodoxScreenGuideService" not in s:
    raise SystemExit("could not add the Screen Guide service")
p.write_text(s)
PY
echo "Screen Guide accessibility service declared (Play-distribution build)."
