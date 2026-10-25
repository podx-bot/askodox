#!/usr/bin/env bash
set -euo pipefail
RES="android/app/src/main/res"
MANIFEST="android/app/src/main/AndroidManifest.xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/askodox"
mkdir -p "$RES/values" "$RES/xml" "$KOTLIN_DIR"

cat > "$RES/values/askodox_colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="askodox_violet_light">#B48CFF</color>
  <color name="askodox_violet">#8A5CF6</color>
  <color name="askodox_violet_deep">#603EFF</color>
  <color name="askodox_ink">#05060A</color>
</resources>
EOF

cat > "$RES/values/strings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><string name="app_name">ASKODOX</string></resources>
EOF

# The launcher icon (adaptive mipmaps + PNGs) and the splash are COMMITTED in
# android/app/src/main/res and are the ONE source of the ASKODOX logo. This
# script must never write them again (it used to overwrite them with an older
# vector copy, so the phone showed the old logo).
for f in mipmap-anydpi-v26/ic_launcher.xml mipmap-anydpi-v26/ic_launcher_round.xml \
         mipmap-xxxhdpi/ic_launcher.png mipmap-xxxhdpi/ic_launcher_foreground.png \
         drawable-nodpi/askodox_splash_mark.png drawable/launch_background.xml; do
  test -f "$RES/$f" || { echo "Committed launcher/splash file missing: $RES/$f" >&2; exit 1; }
done

cat > "$RES/xml/askodox_update_paths.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="askodox_updates" path="." /><files-path name="askodox_files" path="." /></paths>
EOF

# MainActivity.kt is committed (android/app/src/main/kotlin/...) and is the
# ONE source of the native bridge (updater, voice, TTS + lip-sync events,
# location + Geocoder, notifications). `flutter create` keeps it; this script
# must never overwrite it with an older copy.
test -f "$KOTLIN_DIR/MainActivity.kt" || { echo "Committed MainActivity.kt missing in $KOTLIN_DIR" >&2; exit 1; }

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); s=p.read_text()
s,n=re.subn(r'android:label="[^"]*"','android:label="@string/app_name"',s,count=1)
if n != 1: raise SystemExit('Android app label not found')
if 'android.permission.REQUEST_INSTALL_PACKAGES' not in s:
    s=s.replace('<application','<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <application',1)
provider='''        <provider\n            android:name="androidx.core.content.FileProvider"\n            android:authorities="${applicationId}.askodox.fileprovider"\n            android:exported="false"\n            android:grantUriPermissions="true">\n            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/askodox_update_paths" />\n        </provider>'''
if '.askodox.fileprovider' not in s:
    s=s.replace('</application>',provider+'\n    </application>',1)
p.write_text(s)
PY

echo 'ASKODOX reference-style launcher, splash and updater bridge applied.'
