#!/usr/bin/env bash
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
RES_XML="android/app/src/main/res/xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/askodox"
mkdir -p "$KOTLIN_DIR" "$RES_XML"

# Owner 2026-11-15 (pani A, "WhatsApp bill / QR share does not work"): this script used to REWRITE
# askodox_update_paths.xml with only cache/askodox_updates/, AFTER the branding script had written the whole
# cache. Every picture / PDF the app shares lives in cache/images or cache/... -> FileProvider refused it
# ("Failed to find configured root") and the share sheet never opened. The file is committed and written by
# tool/apply_android_askodox_branding.sh; here we only CHECK that it still exposes the whole cache.
grep -q '<cache-path[^>]*path="\."' "$RES_XML/askodox_update_paths.xml" || {
  echo "askodox_update_paths.xml must expose the whole cache (cache-path path=\".\") or sharing breaks" >&2
  exit 1
}

# MainActivity.kt is committed (android/app/src/main/kotlin/...) and is the
# ONE source of the native bridge (updater, voice, TTS + lip-sync events,
# location + Geocoder, notifications). `flutter create` keeps it; this script
# must never overwrite it with an older copy.
test -f "$KOTLIN_DIR/MainActivity.kt" || { echo "Committed MainActivity.kt missing in $KOTLIN_DIR" >&2; exit 1; }

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
permissions = [
    'android.permission.INTERNET',
    'android.permission.RECORD_AUDIO',
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.SYSTEM_ALERT_WINDOW',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
]
for permission in permissions:
    if permission not in s:
        s = s.replace('<application', f'<uses-permission android:name="{permission}" />\n    <application', 1)
if 'AskodoxFloatingCompanionService' not in s:
    raise SystemExit('AndroidManifest.xml lost the floating bubble service declaration')
p.write_text(s)
PY

echo 'ASKODOX PackageInstaller updater, internet, voice and device location bridge applied.'
