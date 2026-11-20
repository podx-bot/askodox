#!/usr/bin/env bash
# Adds the POS payment voice alerts notification listener to the manifest.
# ONLY for builds distributed through Google Play. Sideloaded phone-test builds must not
# include it: Play Protect blocks internet-sideloaded apps that declare
# BIND_NOTIFICATION_LISTENER_SERVICE. Never used to evade any security control.
set -euo pipefail
MANIFEST="android/app/src/main/AndroidManifest.xml"
python3 - "$MANIFEST" tool/android_payment_alerts_service.xml <<'PY'
import sys
from pathlib import Path
p, block = Path(sys.argv[1]), Path(sys.argv[2]).read_text()
s = p.read_text()
if "AskodoxPaymentAlertListener" not in s:
    s = s.replace("        <provider", block + "        <provider", 1)
if "AskodoxPaymentAlertListener" not in s:
    raise SystemExit("could not add the payment alerts listener")
# Owner 2026-11-20 (zero setup): "Allow" on Android's own battery dialog instead of a settings list to search.
battery = '    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />\n'
if "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" not in s:
    s = s.replace("    <application", battery + "    <application", 1)
p.write_text(s)
PY
echo "Payment alerts notification listener declared (Play-distribution build)."
