#!/usr/bin/env python3
"""ASKODOX release APK guard (no Android SDK needed).

Reads an APK's package, versionCode/versionName (binary manifest), the
SHA-256 of its v2/v3 signing certificate and the backend hosts compiled
into libapp.so, prints them, and fails when any production rule is broken:

  --cert SHA256         signing certificate must match (the public pinned
                        fingerprint in .github/askodox-release-cert.sha256)
  --package NAME        applicationId must match (com.askodox.askodox)
  --min-version-code N  versionCode must be strictly greater than N
  --forbid-host HOST    HOST must not be compiled in (e.g. staging.askodox.com)
  --require-host HOST   HOST must be compiled in (the production backend)

Only public facts are printed: no secret is read or written.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
import zipfile

V2, V3 = 0x7109871A, 0xF05368C0
ANDROID_DEBUG_DN = b"CN=Android Debug"


def _signing_block(data: bytes) -> dict[int, bytes]:
    eocd = data.rfind(b"PK\x05\x06")
    cd_off = struct.unpack("<I", data[eocd + 16:eocd + 20])[0]
    if data[cd_off - 16:cd_off] != b"APK Sig Block 42":
        raise SystemExit("FAIL: APK has no v2/v3 signing block")
    size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
    pairs, i, out = data[cd_off - size - 8 + 8:cd_off - 24], 0, {}
    while i < len(pairs):
        length = struct.unpack("<Q", pairs[i:i + 8])[0]
        out[struct.unpack("<I", pairs[i + 8:i + 12])[0]] = pairs[i + 12:i + 8 + length]
        i += 8 + length
    return out


def _lp(buf: bytes, i: int) -> tuple[bytes, int]:
    n = struct.unpack("<I", buf[i:i + 4])[0]
    return buf[i + 4:i + 4 + n], i + 4 + n


def signing_cert(data: bytes) -> bytes:
    block = _signing_block(data)
    scheme = block.get(V3) or block.get(V2)
    if scheme is None:
        raise SystemExit("FAIL: APK is not v2/v3 signed")
    signers, _ = _lp(scheme, 0)
    signer, _ = _lp(signers, 0)
    signed_data, _ = _lp(signer, 0)
    _, j = _lp(signed_data, 0)  # digests
    certs, _ = _lp(signed_data, j)
    cert, _ = _lp(certs, 0)
    return cert


def manifest(apk: zipfile.ZipFile) -> dict[str, object]:
    m = apk.read("AndroidManifest.xml")
    sp = 8
    header = struct.unpack("<H", m[sp + 2:sp + 4])[0]
    chunk = struct.unpack("<I", m[sp + 4:sp + 8])[0]
    count, _, flags, strings_start = struct.unpack("<IIII", m[sp + 8:sp + 24])
    utf8 = flags & 0x100
    offsets = struct.unpack("<%dI" % count, m[sp + header:sp + header + 4 * count])
    strings = []
    for off in offsets:
        p = sp + strings_start + off
        if utf8:
            p += 2 if m[p] & 0x80 else 1
            n = m[p]
            if n & 0x80:
                n = ((n & 0x7F) << 8) | m[p + 1]
                p += 1
            strings.append(m[p + 1:p + 1 + n].decode("utf-8", "replace"))
        else:
            n = struct.unpack("<H", m[p:p + 2])[0]
            strings.append(m[p + 2:p + 2 + 2 * n].decode("utf-16-le", "replace"))
    i = sp + chunk
    while i < len(m):
        kind, _, size = struct.unpack("<HHI", m[i:i + 8])
        if kind == 0x0102 and strings[struct.unpack("<I", m[i + 20:i + 24])[0]] == "manifest":
            attrs, a = {}, i + 36
            for _ in range(struct.unpack("<H", m[i + 28:i + 30])[0]):
                _, name, raw, _, _, _, value = struct.unpack("<IIIHBBI", m[a:a + 20])
                attrs[strings[name]] = strings[raw] if raw != 0xFFFFFFFF else value
                a += 20
            return attrs
        i += size
    raise SystemExit("FAIL: no <manifest> element")


def backend_hosts(apk: zipfile.ZipFile) -> list[str]:
    names = [n for n in apk.namelist() if n.endswith("/libapp.so")]
    found: set[str] = set()
    for name in names:
        found.update(h.decode() for h in re.findall(
            rb"https://((?:[a-z0-9-]+\.)*(?:askodox\.com|up\.railway\.app))", apk.read(name)))
    return sorted(found)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("apk")
    ap.add_argument("--cert")
    ap.add_argument("--package")
    ap.add_argument("--min-version-code", type=int)
    ap.add_argument("--forbid-host", action="append", default=[])
    ap.add_argument("--require-host", action="append", default=[])
    args = ap.parse_args()

    data = open(args.apk, "rb").read()
    cert = signing_cert(data)
    cert_sha = hashlib.sha256(cert).hexdigest()
    with zipfile.ZipFile(args.apk) as apk:
        man = manifest(apk)
        hosts = backend_hosts(apk)
    print(f"apk: {args.apk}")
    print(f"apk_sha256: {hashlib.sha256(data).hexdigest()}")
    print(f"package: {man.get('package')}")
    print(f"versionCode: {man.get('versionCode')}")
    print(f"versionName: {man.get('versionName')}")
    print(f"signing_cert_sha256: {cert_sha}")
    print(f"backend_hosts: {', '.join(hosts) or '(none)'}")

    failures = []
    if ANDROID_DEBUG_DN in cert:
        failures.append("signed with an Android debug certificate")
    if args.cert and cert_sha != args.cert.strip().lower():
        failures.append(f"signing certificate {cert_sha} is not the ASKODOX release certificate {args.cert}")
    if args.package and man.get("package") != args.package:
        failures.append(f"package {man.get('package')} != {args.package}")
    if args.min_version_code is not None and not int(man.get("versionCode") or 0) > args.min_version_code:
        failures.append(f"versionCode {man.get('versionCode')} is not greater than {args.min_version_code}")
    for host in args.forbid_host:
        if host in hosts:
            failures.append(f"forbidden backend host compiled in: {host}")
    for host in args.require_host:
        if host not in hosts:
            failures.append(f"required backend host missing: {host}")
    for failure in failures:
        print(f"FAIL: {failure}")
    if not failures:
        print("PASS: APK guard")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
