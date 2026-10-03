"""Staging admin isolation check (no secret involved): the Command Center page
loads, and the admin API refuses a missing key, a wrong key and the literal
unresolved Railway template text (proves ADMIN_SEED_KEY resolved to a real
random value). The real key is never used or printed."""
import sys

import httpx

BASE = sys.argv[1].rstrip("/")
http = httpx.Client(timeout=30)
results = []


def check(name, ok, detail):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")


page = http.get(f"{BASE}/admin/console")
check("/admin/console loads", page.status_code == 200 and "ASKODOX Console" in page.text, {"status": page.status_code})
literal = "$" + '{{secret(64, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}'
for label, headers in (("no key", {}), ("wrong key", {"X-ASKODOX-Admin-Key": "wrong-key-for-isolation-check"}),
                       ("unresolved template text", {"X-ASKODOX-Admin-Key": literal})):
    r = http.get(f"{BASE}/admin/cc/me", headers=headers)
    check(f"admin API refuses {label}", r.status_code in (401, 403), {"status": r.status_code})
health = http.get(f"{BASE}/readiness").json()
check("still the staging environment", health.get("environment") == "staging", {"environment": health.get("environment")})
sys.exit(0 if all(results) else 1)
