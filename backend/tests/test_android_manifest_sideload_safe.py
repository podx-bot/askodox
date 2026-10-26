"""Sideloaded APKs must install: Play Protect's enhanced fraud protection blocks internet-sideloaded
apps that declare a notification listener or an accessibility service (APK 1366 was blocked).
Those services are added only to Play-distributed builds by their own scripts."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"


def _declared(text: str) -> str:
    return re.sub(r"<!--.*?-->", "", text, flags=re.S)


def test_default_manifest_declares_no_play_protect_blocked_services():
    text = _declared(MANIFEST.read_text(encoding="utf-8"))
    assert "BIND_NOTIFICATION_LISTENER_SERVICE" not in text
    assert "BIND_ACCESSIBILITY_SERVICE" not in text


def test_play_build_script_adds_the_payment_alerts_listener(tmp_path):
    work = tmp_path / "repo"
    (work / "android/app/src/main").mkdir(parents=True)
    (work / "tool").mkdir()
    (work / "android/app/src/main/AndroidManifest.xml").write_text(MANIFEST.read_text(encoding="utf-8"))
    for name in ("apply_android_payment_alerts.sh", "android_payment_alerts_service.xml"):
        (work / "tool" / name).write_text((ROOT / "tool" / name).read_text(encoding="utf-8"))
    subprocess.run(["bash", "tool/apply_android_payment_alerts.sh"], cwd=work, check=True)
    text = _declared((work / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8"))
    assert text.count("AskodoxPaymentAlertListener") == 1
    assert 'android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"' in text
