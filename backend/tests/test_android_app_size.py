"""App size (owner 2026-11-23, Play Console: "this artifact significantly increases the size of APK(s)").

The attendance live face check must use Google's face model inside Google Play services (~0.8 MB in the app), never
the copy bundled into the app (~6.9 MB per phone, +14 MB in the Play bundle 1619). The Flutter plugin
google_mlkit_face_detection depends on the bundled `com.google.mlkit:face-detection`; the app excludes it and depends
on `play-services-mlkit-face-detection`, and the manifest asks Play services to download the model after install.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
GRADLE = ROOT / "android" / "app" / "build.gradle.kts"
MANIFEST = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"


def _code(text: str) -> str:
    return re.sub(r"//[^\n]*", "", text)


def test_the_bundled_face_model_is_excluded_and_the_play_services_one_used():
    gradle = _code(GRADLE.read_text(encoding="utf-8"))
    assert re.search(r'exclude\(\s*group\s*=\s*"com\.google\.mlkit"\s*,\s*module\s*=\s*"face-detection"\s*\)', gradle)
    assert 'implementation("com.google.android.gms:play-services-mlkit-face-detection:' in gradle
    assert 'implementation("com.google.mlkit:face-detection' not in gradle


def test_play_services_downloads_the_face_model_after_install():
    text = re.sub(r"<!--.*?-->", "", MANIFEST.read_text(encoding="utf-8"), flags=re.S)
    match = re.search(r'android:name="com\.google\.mlkit\.vision\.DEPENDENCIES"\s+android:value="([^"]+)"', text)
    assert match and "face" in match.group(1).split(",")
