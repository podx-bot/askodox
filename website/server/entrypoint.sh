#!/bin/sh
# Build the site from config + ASKODOX_SITE_* variables, then serve it.
set -eu
python3 /app/build.py --out /srv/site --redirects /srv/generated.caddy
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
