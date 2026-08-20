#!/usr/bin/env bash
set -euo pipefail

RES="android/app/src/main/res"
mkdir -p "$RES/drawable" "$RES/drawable-v21" "$RES/mipmap-anydpi" "$RES/mipmap-anydpi-v26" "$RES/values"

cat > "$RES/values/askodox_colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="askodox_violet">#603EFF</color>
    <color name="askodox_blue">#2F7BFF</color>
    <color name="askodox_ink">#05060A</color>
</resources>
EOF

cat > "$RES/drawable/askodox_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M27,25 L62,25 C75,25 84,33 84,45 C84,54 79,61 71,65 L84,83 L68,83 L57,68 L45,68 L45,83 L27,83 Z M45,40 L45,54 L60,54 C64,54 67,51 67,47 C67,43 64,40 60,40 Z" />
    <path
        android:fillColor="#FFB48CFF"
        android:pathData="M20,20 L88,20 L88,26 L20,26 Z" />
</vector>
EOF

cat > "$RES/drawable/askodox_launcher_legacy.xml" <<'EOF'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <gradient
                android:angle="315"
                android:startColor="#603EFF"
                android:centerColor="#4823B9"
                android:endColor="#2F7BFF" />
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
    <background android:drawable="@color/askodox_violet" />
    <foreground android:drawable="@drawable/askodox_launcher_foreground" />
</adaptive-icon>
EOF

cat > "$RES/mipmap-anydpi-v26/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/askodox_violet" />
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
                android:centerColor="#151823"
                android:endColor="#2B176F" />
        </shape>
    </item>
    <item
        android:drawable="@drawable/askodox_launcher_foreground"
        android:gravity="center"
        android:width="132dp"
        android:height="132dp" />
</layer-list>
EOF

cp "$RES/drawable/launch_background.xml" "$RES/drawable-v21/launch_background.xml"

echo "ASKODOX Android branding applied."
