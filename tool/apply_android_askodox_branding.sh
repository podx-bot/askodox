#!/usr/bin/env bash
set -euo pipefail
RES="android/app/src/main/res"
MANIFEST="android/app/src/main/AndroidManifest.xml"
KOTLIN_DIR="android/app/src/main/kotlin/com/askodox/podx"
mkdir -p "$RES/drawable" "$RES/drawable-v21" "$RES/mipmap-anydpi" "$RES/mipmap-anydpi-v26" "$RES/values" "$RES/xml" "$KOTLIN_DIR"

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

cat > "$RES/drawable/askodox_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
  <!-- Brain outline: rounded left half, matching ASKODOX reference mark. -->
  <path
      android:fillColor="@android:color/transparent"
      android:strokeColor="#FFF9FF"
      android:strokeWidth="3.2"
      android:strokeLineCap="round"
      android:strokeLineJoin="round"
      android:pathData="M47,19 C39,16 34,20 32,25 C25,24 21,29 22,35 C16,37 14,43 17,48 C12,53 14,61 20,64 C18,71 23,77 30,77 C33,84 41,86 47,81 C50,79 52,76 52,72 L52,27 C52,23 50,21 47,19 Z" />
  <!-- Brain inner branches. -->
  <path android:fillColor="@android:color/transparent" android:strokeColor="#D9B9FF" android:strokeWidth="2.35" android:strokeLineCap="round" android:strokeLineJoin="round" android:pathData="M25,35 L34,35 L39,30 M25,47 L36,47 L43,53 M23,59 L32,59 L38,54 M30,71 L38,71 L43,65 M39,39 L47,39 M40,59 L48,59 M45,27 L45,34 M45,65 L45,75" />
  <!-- Circuit nodes. -->
  <path android:fillColor="#FFF9FF" android:pathData="M22.5,35 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M32,35 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M39,30 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M23,47 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M35,47 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M43,53 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M21,59 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M31,59 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M29,71 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M38,71 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M45,39 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0 M46,59 a2.5,2.5 0,1 0,5 0 a2.5,2.5 0,1 0,-5 0" />
  <!-- Action / solution A-arrow, thicker and cleaner. -->
  <path android:fillColor="#FFB48CFF" android:pathData="M58,20 L86,48 L74,48 L74,57 L90,57 L64,84 L64,68 L54,68 L68,54 L68,47 L58,47 Z" />
  <path android:fillColor="#FF8A5CF6" android:pathData="M64,27 L80,43 L71,43 L71,52 L63,52 Z" />
  <path android:fillColor="#FF603EFF" android:pathData="M66,64 L81,64 L69,76 L66,76 Z" />
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
  <item android:drawable="@drawable/askodox_launcher_foreground" android:gravity="center" android:width="156dp" android:height="156dp"/>
</layer-list>
EOF
cp "$RES/drawable/launch_background.xml" "$RES/drawable-v21/launch_background.xml"

cat > "$RES/xml/askodox_update_paths.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android"><cache-path name="askodox_updates" path="." /></paths>
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
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.askodox.app/update")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) { result.error("missing_path", "APK path missing", null); return@setMethodCallHandler }
                try {
                    val apk = File(path)
                    val uri = FileProvider.getUriForFile(this, "$packageName.askodox.fileprovider", apk)
                    startActivity(Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    })
                    result.success(true)
                } catch (e: Exception) { result.error("install_failed", e.message, null) }
            }
    }
}
EOF

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
