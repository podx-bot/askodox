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
HEALTH_JSON="$(curl --fail --silent --show-error --location --max-time 20 "$BASE_URL/health")"
READINESS_JSON="$(curl --fail --silent --show-error --location --max-time 20 "$BASE_URL/readiness")"

HEALTH_JSON="$HEALTH_JSON" READINESS_JSON="$READINESS_JSON" python3 - <<'PY'
import json, os

try:
    health = json.loads(os.environ['HEALTH_JSON'])
    readiness = json.loads(os.environ['READINESS_JSON'])
except Exception as exc:
    raise SystemExit(f'ASKODOX backend returned invalid JSON: {exc}')

if str(health.get('status', '')).lower() != 'healthy':
    raise SystemExit(f"ASKODOX /health is not healthy: {health.get('status')!r}")
if health.get('app') != 'ASKODOX':
    raise SystemExit(f"API_BASE_URL does not point to ASKODOX (app={health.get('app')!r})")
if readiness.get('database_ready') is not True:
    raise SystemExit('ASKODOX backend database readiness check failed')

print('Verified ASKODOX production backend')
PY
