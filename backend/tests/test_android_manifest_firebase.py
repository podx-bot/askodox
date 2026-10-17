"""Firebase phone sign-in needs ASKODOX's activities in ONE task (APK 1336).

`android:taskAffinity=""` on MainActivity puts Firebase's RecaptchaActivity
(singleTask, default affinity) in a separate task: after the reCAPTCHA browser
step the app is not brought back to the front and Firebase's code request runs
in the background, where Android can close the connection ("Software caused
connection abort" / network-request-failed).
"""
from pathlib import Path
import re

MANIFEST = Path(__file__).resolve().parents[2] / "android" / "app" / "src" / "main" / "AndroidManifest.xml"


def _main_activity() -> str:
    text = MANIFEST.read_text(encoding="utf-8")
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    match = re.search(r"<activity\b[^>]*android:name=\"\.MainActivity\"[^>]*>", text, flags=re.S)
    assert match, "MainActivity not found"
    return match.group(0)


def test_main_activity_keeps_the_default_task_affinity():
    activity = _main_activity()
    assert "taskAffinity" not in activity, "an empty / custom taskAffinity breaks the Firebase reCAPTCHA return"


def test_main_activity_launch_mode_unchanged():
    activity = _main_activity()
    assert 'android:launchMode="singleTop"' in activity
    assert 'android:exported="true"' in activity
