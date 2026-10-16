"""CI Firebase Android config (tool/firebase_android_config.py): validated from
the four GitHub variables, google-services.json for com.askodox.askodox, values
never printed, half / malformed configs refused, the APK check, and the Gradle /
git wiring that keeps the generated file out of the repository."""
import importlib.util
import json
import os
import stat
import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("firebase_android_config", ROOT / "tool" / "firebase_android_config.py")
fac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fac)

VALID = {
    "FIREBASE_PROJECT_ID": "askodox-test-1a2b",
    "FIREBASE_SENDER_ID": "123456789012",
    "FIREBASE_APP_ID": "1:123456789012:android:0a1b2c3d4e5f60718293a4",
    "FIREBASE_API_KEY": "AIza" + "S" * 20 + "y-_" + "Q" * 12,
}


@pytest.fixture()
def env(monkeypatch, tmp_path):
    for name in fac.NAMES:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("GITHUB_OUTPUT", str(tmp_path / "gh_out"))
    return monkeypatch, tmp_path


def _run(tmp_path, *extra):
    return fac.main(["write", "--out", str(tmp_path / "app" / "google-services.json"),
                     "--dart-defines", str(tmp_path / "defines.json"), *extra])


def _set(mp, values):
    for k, v in values.items():
        mp.setenv(k, v)


def test_valid_values_make_google_services_json_without_printing_them(env, capsys):
    mp, tmp = env
    _set(mp, VALID)
    assert _run(tmp, "--require") == 0
    out = capsys.readouterr().out
    for value in VALID.values():
        assert value not in out, "values are never printed"
    gs = json.loads((tmp / "app" / "google-services.json").read_text())
    client = gs["client"][0]
    assert client["client_info"]["android_client_info"]["package_name"] == "com.askodox.askodox"
    assert client["client_info"]["mobilesdk_app_id"] == VALID["FIREBASE_APP_ID"]
    assert client["api_key"][0]["current_key"] == VALID["FIREBASE_API_KEY"]
    assert gs["project_info"] == {"project_number": VALID["FIREBASE_SENDER_ID"],
                                  "project_id": VALID["FIREBASE_PROJECT_ID"]}
    assert json.loads((tmp / "defines.json").read_text()) == VALID, "Dart uses exactly the same values"
    for f in (tmp / "app" / "google-services.json", tmp / "defines.json"):
        assert stat.S_IMODE(os.stat(f).st_mode) == 0o600
    assert (tmp / "gh_out").read_text().strip() == "configured=true"


def test_not_configured_builds_without_firebase_unless_required(env, capsys):
    mp, tmp = env
    (tmp / "app").mkdir()
    (tmp / "app" / "google-services.json").write_text("stale")
    assert _run(tmp) == 0
    assert not (tmp / "app" / "google-services.json").exists(), "a stale file never survives"
    assert json.loads((tmp / "defines.json").read_text()) == {}
    assert "not configured" in capsys.readouterr().out
    assert _run(tmp, "--require") == 1, "main must ship with Firebase"


@pytest.mark.parametrize("change,needle", [
    ({"FIREBASE_API_KEY": ""}, "missing: FIREBASE_API_KEY"),
    ({"FIREBASE_PROJECT_ID": "Bad_Project"}, "FIREBASE_PROJECT_ID"),
    ({"FIREBASE_SENDER_ID": "12ab"}, "FIREBASE_SENDER_ID"),
    ({"FIREBASE_APP_ID": "1:123456789012:ios:abcdef"}, "FIREBASE_APP_ID is not an Android app id"),
    ({"FIREBASE_APP_ID": "1:999999999999:android:0a1b2c3d4e5f"}, "does not belong to FIREBASE_SENDER_ID"),
    ({"FIREBASE_API_KEY": "not-a-google-key"}, "FIREBASE_API_KEY"),
])
def test_half_or_malformed_config_is_refused_without_echoing_values(env, capsys, change, needle):
    mp, tmp = env
    values = {**VALID, **change}
    _set(mp, {k: v for k, v in values.items() if v})
    assert _run(tmp) == 1, "refused even when not required"
    out = capsys.readouterr().out
    assert needle in out
    for value in values.values():
        if len(value) > 6:
            assert value not in out
    assert not (tmp / "app" / "google-services.json").exists()


def _apk(path, arsc: bytes, libapp: bytes):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("resources.arsc", arsc)
        z.writestr("lib/arm64-v8a/libapp.so", libapp)
    return str(path)


def test_apk_check_reports_presence_only(env, capsys):
    mp, tmp = env
    _set(mp, VALID)
    good = _apk(tmp / "good.apk", b"..google_app_id.." + VALID["FIREBASE_APP_ID"].encode("utf-16-le"),
                b"x" + VALID["FIREBASE_API_KEY"].encode() + b"y" + VALID["FIREBASE_APP_ID"].encode())
    assert fac.main(["check-apk", good, "--require"]) == 0
    out = capsys.readouterr().out
    assert "native google-services config present" in out and "Flutter Firebase values present" in out
    assert all(v not in out for v in VALID.values())
    bare = _apk(tmp / "bare.apk", b"nothing", b"nothing")
    assert fac.main(["check-apk", bare]) == 1
    assert "MISSING" in capsys.readouterr().out


def test_gradle_and_git_wiring():
    settings = (ROOT / "android" / "settings.gradle.kts").read_text()
    app = (ROOT / "android" / "app" / "build.gradle.kts").read_text()
    assert 'id("com.google.gms.google-services") version "4.5.0" apply false' in settings
    assert 'if (file("google-services.json").exists())' in app
    assert 'apply(plugin = "com.google.gms.google-services")' in app
    assert 'applicationId = "com.askodox.askodox"' in app, "package name unchanged"
    assert 'signingConfigs.getByName("release")' in app and 'signingConfigs.getByName("debug")' not in app
    assert "android/app/google-services.json" in (ROOT / ".gitignore").read_text()
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    assert not [f for f in tracked if f.endswith("google-services.json")], "never committed"


def test_every_apk_workflow_generates_the_config():
    wf = ROOT / ".github" / "workflows"
    live = (wf / "android-live-build.yml").read_text()
    ci = (wf / "flutter-ci.yml").read_text()
    apk = (wf / "android-apk.yml").read_text()
    for text in (live, ci, apk):
        assert "tool/firebase_android_config.py write" in text
        for name in fac.NAMES:
            assert f"${{{{ vars.{name} }}}}" in text
    assert "check-apk" in live and "check-apk" in ci
    assert "--dart-define-from-file=build/firebase-dart-defines.json" in ci
    for text in (live, ci, apk):
        assert "cat android/app/google-services.json" not in text and "echo $FIREBASE" not in text
