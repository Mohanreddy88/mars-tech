#!/bin/bash
# Pull latest code and (re)build/restart. Run on the VPS from /opt/hrms/deploy
set -euo pipefail
cd "$(dirname "$0")"

docker network create web >/dev/null 2>&1 || true
CADDY_BEFORE=$(sha1sum Caddyfile | cut -d' ' -f1)
git -C .. pull --ff-only
docker compose up -d --build
docker image prune -f >/dev/null

# The Caddyfile is a bind-mounted file: after git replaces it, Caddy must be
# recreated to see the new version (domains, redirects, headers).
if [ "$CADDY_BEFORE" != "$(sha1sum Caddyfile | cut -d' ' -f1)" ]; then
  echo "Caddyfile changed — validating and recreating caddy"
  docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
  docker compose up -d --no-deps --force-recreate caddy
fi

echo
docker compose ps
echo
echo "Logs:  docker compose logs -f app"
