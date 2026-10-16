#!/usr/bin/env python3
"""Firebase Android configuration for CI builds -- validated, never printed.

The four GitHub Actions *variables* FIREBASE_PROJECT_ID, FIREBASE_SENDER_ID,
FIREBASE_APP_ID and FIREBASE_API_KEY (public Firebase client identifiers of
the Android app ``com.askodox.askodox``) are turned into:

* ``android/app/google-services.json`` -- read by the Google Services Gradle
  plugin, which creates the native default Firebase app (needed for FCM
  delivery while ASKODOX is closed, phone sign-in app verification and
  In-App Messaging). Generated at build time only; it is git-ignored and never
  committed or uploaded as an artifact.
* a Dart define file (``--dart-define-from-file``) so the Flutter side uses
  exactly the same values (``AskodoxFirebaseConfig``).

Commands
  write       [--require] [--out PATH] [--dart-defines PATH]
  check-apk   APK [--require]   (the built APK really carries the config)

Output never contains a value: only which names are missing / malformed and
"configured". All four empty = Firebase not configured (allowed unless
--require). Partly set or malformed = always an error (a half-configured
build is worse than none).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import zipfile
from pathlib import Path

PACKAGE = "com.askodox.askodox"
NAMES = ("FIREBASE_PROJECT_ID", "FIREBASE_SENDER_ID", "FIREBASE_APP_ID", "FIREBASE_API_KEY")

_PROJECT = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
_SENDER = re.compile(r"^[0-9]{6,20}$")
_APP_ID = re.compile(r"^1:([0-9]{6,20}):android:[0-9a-f]{6,40}$")
_API_KEY = re.compile(r"^AIza[0-9A-Za-z_\-]{35}$")


class ConfigError(ValueError):
    """Message names the problem, never the value."""


def read_values(env: dict) -> dict | None:
    """The four values (stripped), None when none is set; ConfigError when
    some are missing or any is malformed."""
    values = {name: str(env.get(name) or "").strip() for name in NAMES}
    present = [n for n in NAMES if values[n]]
    if not present:
        return None
    missing = [n for n in NAMES if not values[n]]
    if missing:
        raise ConfigError("Firebase is partly configured; missing: " + ", ".join(missing))
    problems = []
    if not _PROJECT.match(values["FIREBASE_PROJECT_ID"]):
        problems.append("FIREBASE_PROJECT_ID is not a Firebase project id")
    if not _SENDER.match(values["FIREBASE_SENDER_ID"]):
        problems.append("FIREBASE_SENDER_ID must be the numeric project number")
    app = _APP_ID.match(values["FIREBASE_APP_ID"])
    if not app:
        problems.append("FIREBASE_APP_ID is not an Android app id (1:<number>:android:<hex>)")
    elif app.group(1) != values["FIREBASE_SENDER_ID"]:
        problems.append("FIREBASE_APP_ID does not belong to FIREBASE_SENDER_ID (different project number)")
    if not _API_KEY.match(values["FIREBASE_API_KEY"]):
        problems.append("FIREBASE_API_KEY is not a Google API key")
    if problems:
        raise ConfigError("; ".join(problems))
    return values


def google_services(values: dict) -> dict:
    """The google-services.json the Google Services plugin expects."""
    return {
        "project_info": {
            "project_number": values["FIREBASE_SENDER_ID"],
            "project_id": values["FIREBASE_PROJECT_ID"],
        },
        "client": [{
            "client_info": {
                "mobilesdk_app_id": values["FIREBASE_APP_ID"],
                "android_client_info": {"package_name": PACKAGE},
            },
            "oauth_client": [],
            "api_key": [{"current_key": values["FIREBASE_API_KEY"]}],
            "services": {"appinvite_service": {"other_platform_oauth_client": []}},
        }],
        "configuration_version": "1",
    }


def _gh_output(**pairs: str) -> None:
    target = os.environ.get("GITHUB_OUTPUT")
    if target:
        with open(target, "a", encoding="utf-8") as handle:
            for key, value in pairs.items():
                handle.write(f"{key}={value}\n")


def write(args: argparse.Namespace) -> int:
    try:
        values = read_values(dict(os.environ))
    except ConfigError as error:
        print(f"::error::{error}")
        return 1
    out = Path(args.out)
    defines = Path(args.dart_defines)
    if values is None:
        out.unlink(missing_ok=True)
        defines.parent.mkdir(parents=True, exist_ok=True)
        defines.write_text("{}\n", encoding="utf-8")
        if args.require:
            print("::error::Firebase is required for this build but FIREBASE_PROJECT_ID / FIREBASE_SENDER_ID / "
                  "FIREBASE_APP_ID / FIREBASE_API_KEY are not set (GitHub -> Settings -> Variables).")
            return 1
        print("::notice::Firebase Android config: not configured (no FIREBASE_* variables); building without Firebase.")
        _gh_output(configured="false")
        return 0
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(google_services(values), indent=2) + "\n", encoding="utf-8")
    os.chmod(out, 0o600)
    defines.parent.mkdir(parents=True, exist_ok=True)
    defines.write_text(json.dumps({name: values[name] for name in NAMES}) + "\n", encoding="utf-8")
    os.chmod(defines, 0o600)
    print(f"::notice::Firebase Android config: configured for {PACKAGE} (4/4 values valid; values not shown).")
    _gh_output(configured="true")
    return 0


def check_apk(args: argparse.Namespace) -> int:
    """The APK carries the native config (google_app_id resource) and the Dart
    side's identifiers -- checked by value, reported only as yes / no."""
    try:
        values = read_values(dict(os.environ))
    except ConfigError as error:
        print(f"::error::{error}")
        return 1
    if values is None:
        if args.require:
            print("::error::Firebase is required but not configured.")
            return 1
        print("::notice::APK Firebase check: skipped (Firebase not configured).")
        return 0
    with zipfile.ZipFile(args.apk) as apk:
        arsc = apk.read("resources.arsc")
        dart = b"".join(apk.read(n) for n in apk.namelist() if n.endswith("/libapp.so"))
    app_id = values["FIREBASE_APP_ID"]
    native = b"google_app_id" in arsc and (app_id.encode() in arsc or app_id.encode("utf-16-le") in arsc)
    flutter = values["FIREBASE_API_KEY"].encode() in dart and app_id.encode() in dart
    print(f"::notice::APK Firebase check: native google-services config {'present' if native else 'MISSING'}; "
          f"Flutter Firebase values {'present' if flutter else 'MISSING'}.")
    return 0 if native and flutter else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    w = sub.add_parser("write")
    w.add_argument("--require", action="store_true")
    w.add_argument("--out", default="android/app/google-services.json")
    w.add_argument("--dart-defines", default="build/firebase-dart-defines.json")
    c = sub.add_parser("check-apk")
    c.add_argument("apk")
    c.add_argument("--require", action="store_true")
    args = parser.parse_args(argv)
    return write(args) if args.command == "write" else check_apk(args)


if __name__ == "__main__":
    sys.exit(main())
