#!/bin/bash
# Pull latest code and (re)build/restart. Run on the VPS from /opt/hrms/deploy
set -euo pipefail
cd "$(dirname "$0")"

git -C .. pull --ff-only
docker compose up -d --build
docker image prune -f >/dev/null

echo
docker compose ps
echo
echo "Logs:  docker compose logs -f app"
