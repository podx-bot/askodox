# ASKODOX website — isolated from the backend image (repo root Dockerfile).
FROM caddy:2.10-alpine

RUN apk add --no-cache python3

WORKDIR /app
COPY build.py pages.py demos.py i18n.py ./
COPY locales ./locales
COPY config ./config
COPY static ./static
COPY server/Caddyfile /etc/caddy/Caddyfile
COPY server/entrypoint.sh /app/entrypoint.sh

# Fail the image build early if the site can't be generated.
RUN python3 build.py --out /tmp/check --redirects /tmp/check.caddy && rm -rf /tmp/check /tmp/check.caddy

ENV PORT=8080
EXPOSE 8080
CMD ["/app/entrypoint.sh"]
