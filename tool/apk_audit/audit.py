"""APK audit (CI): identity, label, signing, SDK levels, every permission,
components (exported / permission-protected), accessibility service config,
and a diff between builds. Evidence only -- it changes nothing.

usage: audit.py <out_dir> <name>=<apk> [<name>=<apk> ...]
"""
import json
import os
import re
import subprocess
import sys
import zipfile

BT = sorted(os.listdir(os.path.join(os.environ["ANDROID_HOME"], "build-tools")))[-1]
TOOLS = os.path.join(os.environ["ANDROID_HOME"], "build-tools", BT)
DANGEROUS = {  # runtime ("dangerous") permissions per the Android docs
    "RECORD_AUDIO", "CAMERA", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "ACCESS_BACKGROUND_LOCATION",
    "READ_CONTACTS", "WRITE_CONTACTS", "READ_PHONE_STATE", "CALL_PHONE", "READ_SMS", "SEND_SMS", "RECEIVE_SMS",
    "READ_EXTERNAL_STORAGE", "WRITE_EXTERNAL_STORAGE", "READ_MEDIA_IMAGES", "READ_MEDIA_VIDEO",
    "READ_MEDIA_AUDIO", "POST_NOTIFICATIONS", "BODY_SENSORS", "READ_CALENDAR", "WRITE_CALENDAR",
    "NEARBY_WIFI_DEVICES", "BLUETOOTH_CONNECT", "BLUETOOTH_SCAN", "READ_MEDIA_VISUAL_USER_SELECTED",
}
SPECIAL = {"SYSTEM_ALERT_WINDOW", "REQUEST_INSTALL_PACKAGES", "BIND_ACCESSIBILITY_SERVICE", "QUERY_ALL_PACKAGES",
           "MANAGE_EXTERNAL_STORAGE", "FOREGROUND_SERVICE_SPECIAL_USE", "FOREGROUND_SERVICE_MEDIA_PROJECTION",
           "SCHEDULE_EXACT_ALARM", "USE_FULL_SCREEN_INTENT", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
           "PACKAGE_USAGE_STATS", "BIND_NOTIFICATION_LISTENER_SERVICE", "BIND_DEVICE_ADMIN"}


def run(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def audit(apk):
    badging = run(os.path.join(TOOLS, "aapt2"), "dump", "badging", apk)
    tree = run(os.path.join(TOOLS, "aapt2"), "dump", "xmltree", "--file", "AndroidManifest.xml", apk)
    certs = run(os.path.join(TOOLS, "apksigner"), "verify", "--print-certs", apk)
    pkg = re.search(r"package: name='([^']*)' versionCode='([^']*)' versionName='([^']*)'", badging)
    perms = sorted(set(re.findall(r"uses-permission: name='([^']*)'", badging)))
    out = {
        "file": os.path.basename(apk), "bytes": os.path.getsize(apk),
        "package": pkg.group(1) if pkg else None, "versionCode": pkg.group(2) if pkg else None,
        "versionName": pkg.group(3) if pkg else None,
        "application_label": (re.search(r"application-label:'([^']*)'", badging) or [None, None])[1],
        "application_line": (re.search(r"^application: .*$", badging, re.M) or [""])[0],
        "sdk": {"min": (re.search(r"(?:minSdkVersion|sdkVersion):'(\d+)'", badging) or [0, None])[1],
                "target": (re.search(r"targetSdkVersion:'(\d+)'", badging) or [0, None])[1]},
        "certificate_sha256": (re.search(r"certificate SHA-256 digest: ([0-9a-f]+)", certs) or [0, None])[1],
        "permissions": perms,
        "dangerous": [p for p in perms if p.split(".")[-1] in DANGEROUS],
        "special_or_restricted": [p for p in perms if p.split(".")[-1] in SPECIAL],
        "application_class": None, "components": [], "queries": [], "accessibility_config": None,
    }
    # Components from the binary manifest tree.
    current = None
    for line in tree.splitlines():
        s = line.strip()
        m = re.match(r"E: (activity|activity-alias|service|receiver|provider|application|queries)", s)
        if m:
            current = {"type": m.group(1)}
            if m.group(1) in ("activity", "activity-alias", "service", "receiver", "provider"):
                out["components"].append(current)
            elif m.group(1) == "queries":
                out["queries"].append("queries-block")
            continue
        if re.match(r"E: (meta-data|intent-filter|action|category|data|property)", s):
            current = {"type": "child"}  # attributes of child elements are not the component's
            continue
        a = re.match(r"A: http://schemas.android.com/apk/res/android:(\w+)\([^)]*\)=(?:\(type [^)]*\))?\"?([^\" ]*)", s)
        if a and current is not None and current.get("type") != "child":
            key, val = a.group(1), a.group(2)
            if current["type"] == "application" and key == "name":
                out["application_class"] = val
            elif current["type"] != "application" and key in ("name", "exported", "permission",
                                                                "foregroundServiceType", "label"):
                current[key] = val
    with zipfile.ZipFile(apk) as z:
        names = [n for n in z.namelist() if n.startswith("res/") and n.endswith(".xml")]
        out["has_accessibility_service"] = any(c.get("permission") == "android.permission.BIND_ACCESSIBILITY_SERVICE"
                                               for c in out["components"])
    for c in out["components"]:
        if c.get("permission") == "android.permission.BIND_ACCESSIBILITY_SERVICE":
            out["accessibility_config"] = c
    return out


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    results = {}
    for arg in sys.argv[2:]:
        name, apk = arg.split("=", 1)
        if os.path.exists(apk):
            results[name] = audit(apk)
    with open(os.path.join(out_dir, "audit.json"), "w") as f:
        json.dump(results, f, indent=1)
    names = list(results)
    lines = []
    for n in names:
        r = results[n]
        lines += [f"== {n}: {r['file']}", f"package={r['package']} versionCode={r['versionCode']} "
                  f"versionName={r['versionName']} label={r['application_label']!r} "
                  f"applicationClass={r['application_class']}", f"sdk={r['sdk']} cert={r['certificate_sha256']}",
                  f"application line: {r['application_line']}",
                  f"permissions ({len(r['permissions'])}): {', '.join(r['permissions'])}",
                  f"dangerous: {r['dangerous']}", f"special/restricted: {r['special_or_restricted']}",
                  f"accessibility service: {r['has_accessibility_service']} {r['accessibility_config']}",
                  "components:"] + [f"   {c}" for c in r["components"]] + [""]
    for a, b in zip(names, names[1:]):
        ra, rb = results[a], results[b]
        lines.append(f"== DIFF {a} -> {b}")
        lines.append(f"permissions added: {sorted(set(rb['permissions']) - set(ra['permissions']))}")
        lines.append(f"permissions removed: {sorted(set(ra['permissions']) - set(rb['permissions']))}")
        ca = {c.get('name') for c in ra['components']}
        cb = {c.get('name') for c in rb['components']}
        lines.append(f"components added: {sorted(x for x in cb - ca if x)}")
        lines.append(f"components removed: {sorted(x for x in ca - cb if x)}")
        for key in ("package", "application_label", "application_class", "certificate_sha256", "sdk"):
            if ra[key] != rb[key]:
                lines.append(f"CHANGED {key}: {ra[key]} -> {rb[key]}")
        lines.append("")
    text = "\n".join(lines)
    print(text)
    with open(os.path.join(out_dir, "audit.txt"), "w") as f:
        f.write(text)


main()
