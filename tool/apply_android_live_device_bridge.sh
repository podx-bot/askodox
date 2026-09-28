#!/usr/bin/env bash
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
RES_XML="android/app/src/main/res/xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/askodox"
mkdir -p "$KOTLIN_DIR" "$RES_XML"

# Keep a narrow FileProvider fallback for compatibility, but the primary updater
# no longer depends on any file path being shareable. Android PackageInstaller
# receives the APK bytes through an install session instead.
cat > "$RES_XML/askodox_update_paths.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="askodox_updates" path="askodox_updates/" />
    <files-path name="askodox_files" path="askodox_updates/" />
</paths>
EOF

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
]
for permission in permissions:
    if permission not in s:
        s = s.replace('<application', f'<uses-permission android:name="{permission}" />\n    <application', 1)
p.write_text(s)
PY

echo 'ASKODOX PackageInstaller updater, internet, voice and device location bridge applied.'
