#!/usr/bin/env bash
set -euo pipefail
RES="android/app/src/main/res"
MANIFEST="android/app/src/main/AndroidManifest.xml"
mkdir -p "$RES/drawable" "$RES/drawable-v21" "$RES/mipmap-anydpi" "$RES/mipmap-anydpi-v26" "$RES/values"

cat > "$RES/values/askodox_colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
  <color name="askodox_violet">#8A5CF6</color>
  <color name="askodox_ink">#05060A</color>
</resources>
EOF

cat > "$RES/values/strings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><string name="app_name">ASKODOX</string></resources>
EOF

cat > "$RES/drawable/askodox_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="@android:color/transparent" android:strokeColor="#FFF7FF" android:strokeWidth="3.4" android:strokeLineCap="round" android:strokeLineJoin="round" android:pathData="M43,25 C35,21 28,26 28,33 C22,34 19,40 22,46 C17,51 19,59 25,62 C23,69 29,76 36,75 C39,81 48,80 51,74 L51,31 C49,27 46,25 43,25 Z" />
  <path android:fillColor="#FFB48CFF" android:pathData="M55,24 L84,51 L71,51 L71,60 L88,60 L63,85 L63,69 L52,69 L66,55 L66,47 L55,47 Z" />
  <path android:fillColor="#FFFFFFFF" android:fillAlpha="0.22" android:pathData="M58,28 L79,48 L68,48 L68,55 L58,55 Z" />
</vector>
EOF

cat > "$RES/drawable/askodox_launcher_legacy.xml" <<'EOF'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
  <item><shape android:shape="rectangle"><corners android:radius="24dp"/><gradient android:angle="315" android:startColor="#05060A" android:centerColor="#100A20" android:endColor="#24104E"/></shape></item>
  <item android:drawable="@drawable/askodox_launcher_foreground" android:gravity="center"/>
</layer-list>
EOF

cat > "$RES/mipmap-anydpi/ic_launcher.xml" <<'EOF'
<inset xmlns:android="http://schemas.android.com/apk/res/android" android:drawable="@drawable/askodox_launcher_legacy" android:inset="0dp" />
EOF
cp "$RES/mipmap-anydpi/ic_launcher.xml" "$RES/mipmap-anydpi/ic_launcher_round.xml"

cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/askodox_ink"/><foreground android:drawable="@drawable/askodox_launcher_foreground"/></adaptive-icon>
EOF
cp "$RES/mipmap-anydpi-v26/ic_launcher.xml" "$RES/mipmap-anydpi-v26/ic_launcher_round.xml"

cat > "$RES/drawable/launch_background.xml" <<'EOF'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
  <item><shape android:shape="rectangle"><gradient android:angle="315" android:startColor="#05060A" android:centerColor="#100A20" android:endColor="#24104E"/></shape></item>
  <item android:drawable="@drawable/askodox_launcher_foreground" android:gravity="center" android:width="144dp" android:height="144dp"/>
</layer-list>
EOF
cp "$RES/drawable/launch_background.xml" "$RES/drawable-v21/launch_background.xml"

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); s=p.read_text()
s,n=re.subn(r'android:label="[^"]*"','android:label="@string/app_name"',s,count=1)
if n != 1: raise SystemExit('Android app label not found')
p.write_text(s)
PY

echo 'ASKODOX launcher, app name and splash branding applied.'
