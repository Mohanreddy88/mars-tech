#!/bin/bash
# Pull latest "uat" branch and (re)build/restart the UAT stack. Run on the VPS from /opt/hrms-uat/deploy
set -euo pipefail
cd "$(dirname "$0")"

docker network create web >/dev/null 2>&1 || true
git -C .. pull --ff-only
docker compose -f docker-compose.uat.yml --env-file .env.uat up -d --build
docker image prune -f >/dev/null

echo
docker compose -f docker-compose.uat.yml --env-file .env.uat ps
echo
echo "Logs:  docker compose -f docker-compose.uat.yml --env-file .env.uat logs -f app"
