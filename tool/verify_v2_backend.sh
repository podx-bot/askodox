#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${API_BASE_URL:-}"
if [ -z "$BASE_URL" ]; then
  echo 'API_BASE_URL is required for ASKODOX release builds.' >&2
  exit 1
fi

case "$BASE_URL" in
  http://*|https://*) ;;
  *) echo 'API_BASE_URL must be an absolute http(s) URL.' >&2; exit 1 ;;
esac

BASE_URL="${BASE_URL%/}"
ROOT_JSON="$(curl --fail --silent --show-error --location --max-time 20 "$BASE_URL/")"
HEALTH_JSON="$(curl --fail --silent --show-error --location --max-time 20 "$BASE_URL/health")"

ROOT_JSON="$ROOT_JSON" HEALTH_JSON="$HEALTH_JSON" python3 - <<'PY'
import json, os, sys

try:
    root = json.loads(os.environ['ROOT_JSON'])
    health = json.loads(os.environ['HEALTH_JSON'])
except Exception as exc:
    raise SystemExit(f'V2 backend returned invalid JSON: {exc}')

if root.get('app') != 'PODX AI CONNECT V2':
    raise SystemExit(
        'API_BASE_URL does not point to PODX AI CONNECT V2 '
        f"(app={root.get('app')!r})"
    )
if str(health.get('status', '')).lower() != 'healthy':
    raise SystemExit(f"V2 /health is not healthy: {health.get('status')!r}")
if health.get('database') is not True:
    raise SystemExit('V2 backend database health check failed')

print('Verified ASKODOX client target: PODX AI CONNECT V2')
PY
