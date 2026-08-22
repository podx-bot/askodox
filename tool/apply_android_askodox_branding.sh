#!/usr/bin/env bash
set -euo pipefail

RES="android/app/src/main/res"
MANIFEST="android/app/src/main/AndroidManifest.xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/podx"
MAPS_KEY="${GOOGLE_MAPS_API_KEY:-}"
mkdir -p "$RES/drawable" "$RES/drawable-v21" "$RES/mipmap-anydpi" "$RES/mipmap-anydpi-v26" "$RES/values" "$RES/xml" "$KOTLIN_DIR"

cat > "$RES/values/askodox_colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="askodox_violet">#8A5CF6</color>
    <color name="askodox_violet_deep">#603EFF</color>
    <color name="askodox_ink">#05060A</color>
</resources>
EOF

cat > "$RES/values/strings.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">ASKODOX</string>
    <string name="google_maps_key">${MAPS_KEY}</string>
</resources>
EOF

cat > "$RES/drawable/askodox_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- Brain / knowledge half of the ASKODOX mark. -->
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#FFF7FF"
        android:strokeWidth="3.4"
        android:strokeLineCap="round"
        android:strokeLineJoin="round"
        android:pathData="M43,25 C35,21 28,26 28,33 C22,34 19,40 22,46 C17,51 19,59 25,62 C23,69 29,76 36,75 C39,81 48,80 51,74 L51,31 C49,27 46,25 43,25 Z" />
    <path
        android:fillColor="#FFF7FF"
        android:pathData="M31,38 a2.7,2.7 0,1 0,5.4 0 a2.7,2.7 0,1 0,-5.4 0 M39,49 a2.7,2.7 0,1 0,5.4 0 a2.7,2.7 0,1 0,-5.4 0 M30,59 a2.7,2.7 0,1 0,5.4 0 a2.7,2.7 0,1 0,-5.4 0 M40,68 a2.7,2.7 0,1 0,5.4 0 a2.7,2.7 0,1 0,-5.4 0 M43,32 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0" />
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#FFF7FF"
        android:strokeWidth="2.2"
        android:strokeLineCap="round"
        android:pathData="M35,39 L41,47 M35,58 L40,51 M35,61 L41,67 M45,35 L45,46 M45,52 L45,65" />
    <!-- Action / solution arrow half of the ASKODOX mark. -->
    <path
        android:fillColor="#FFB48CFF"
        android:pathData="M55,24 L84,51 L71,51 L71,60 L88,60 L63,85 L63,69 L52,69 L66,55 L66,47 L55,47 Z" />
    <path
        android:fillColor="#FFFFFFFF"
        android:fillAlpha="0.22"
        android:pathData="M58,28 L79,48 L68,48 L68,55 L58,55 Z" />
</vector>
EOF

cat > "$RES/drawable/askodox_launcher_legacy.xml" <<'EOF'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <corners android:radius="24dp" />
            <gradient
                android:angle="315"
                android:startColor="#05060A"
                android:centerColor="#100A20"
                android:endColor="#24104E" />
        </shape>
    </item>
    <item
        android:drawable="@drawable/askodox_launcher_foreground"
        android:gravity="center" />
</layer-list>
EOF

cat > "$RES/mipmap-anydpi/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/askodox_launcher_legacy"
    android:inset="0dp" />
EOF

cat > "$RES/mipmap-anydpi/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<inset xmlns:android="http://schemas.android.com/apk/res/android"
    android:drawable="@drawable/askodox_launcher_legacy"
    android:inset="0dp" />
EOF

cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/askodox_ink" />
    <foreground android:drawable="@drawable/askodox_launcher_foreground" />
</adaptive-icon>
EOF

cat > "$RES/mipmap-anydpi-v26/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/askodox_ink" />
    <foreground android:drawable="@drawable/askodox_launcher_foreground" />
</adaptive-icon>
EOF

cat > "$RES/drawable/launch_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <gradient
                android:angle="315"
                android:startColor="#05060A"
                android:centerColor="#100A20"
                android:endColor="#24104E" />
        </shape>
    </item>
    <item
        android:drawable="@drawable/askodox_launcher_foreground"
        android:gravity="center"
        android:width="144dp"
        android:height="144dp" />
</layer-list>
EOF

cp "$RES/drawable/launch_background.xml" "$RES/drawable-v21/launch_background.xml"

cat > "$RES/xml/askodox_update_paths.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="askodox_updates" path="." />
</paths>
EOF

cat > "$KOTLIN_DIR/MainActivity.kt" <<'EOF'
package com.askodox.podx

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.askodox.app/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("missing_path", "APK path was not provided", null)
                    return@setMethodCallHandler
                }
                try {
                    val apk = File(path)
                    if (!apk.exists() || apk.length() <= 0L) {
                        result.error("missing_apk", "Downloaded APK was not found", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.askodox.fileprovider",
                        apk,
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }
}
EOF

if [ ! -f "$MANIFEST" ]; then
  echo "AndroidManifest.xml was not generated before branding." >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
updated, count = re.subn(
    r'android:label="[^"]*"',
    'android:label="@string/app_name"',
    text,
    count=1,
)
if count != 1:
    raise SystemExit('Could not locate Android application label')
text = updated

permissions = [
    'android.permission.REQUEST_INSTALL_PACKAGES',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_FINE_LOCATION',
]
for permission_name in permissions:
    if permission_name not in text:
        permission = f'<uses-permission android:name="{permission_name}" />'
        text = text.replace('<application', f'{permission}\n    <application', 1)

maps_metadata = '''        <meta-data
            android:name="com.google.android.geo.API_KEY"
            android:value="@string/google_maps_key" />'''
if 'com.google.android.geo.API_KEY' not in text:
    text = text.replace('</application>', f'{maps_metadata}\n    </application>', 1)

provider = '''        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.askodox.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/askodox_update_paths" />
        </provider>'''
if '.askodox.fileprovider' not in text:
    text = text.replace('</application>', f'{provider}\n    </application>', 1)

path.write_text(text)
PY

echo "ASKODOX Android branding, maps/location, and updater bridge applied."
