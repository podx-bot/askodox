"""Play Store bundle only (owner 2026-11-10): drop what Google Play does not allow or what Phase 1 never uses.

The sideloaded APK keeps these (its GitHub in-app updater needs REQUEST_INSTALL_PACKAGES). Run right
before `flutter build appbundle`; it edits the working copy of the manifest, never the committed file.
  - REQUEST_INSTALL_PACKAGES: Play apps update through Play only.
  - SYSTEM_ALERT_WINDOW + FOREGROUND_SERVICE_SPECIAL_USE + the floating companion service: no Phase 1 feature
    turns the floating companion on.
"""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml"
DROP_PERMISSIONS = ("android.permission.REQUEST_INSTALL_PACKAGES", "android.permission.SYSTEM_ALERT_WINDOW",
                    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE")
DROP_SERVICES = (".AskodoxFloatingCompanionService",)

text = open(PATH, encoding="utf-8").read()
for perm in DROP_PERMISSIONS:
    text, n = re.subn(r'[ \t]*<uses-permission[^>]*android:name="%s"[^>]*/>\n?' % re.escape(perm), "", text)
    print(f"{perm}: removed {n}")
for name in DROP_SERVICES:
    text, n = re.subn(r'[ \t]*<service\s[^>]*android:name="%s".*?</service>\n?' % re.escape(name), "", text, flags=re.S)
    print(f"service {name}: removed {n}")
for perm in DROP_PERMISSIONS:
    if perm in text:
        sys.exit(f"still declared: {perm}")
open(PATH, "w", encoding="utf-8").write(text)
