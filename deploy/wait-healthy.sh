#!/bin/bash
# Wait until the app container reports "healthy". Used by deploy.sh / deploy-uat.sh so a
# release that fails to start (e.g. a failed database migration) is reported as FAILED.
#   usage: wait-healthy.sh <compose args...>      e.g. wait-healthy.sh -f docker-compose.uat.yml --env-file .env.uat
set -uo pipefail
CID=$(docker compose "$@" ps -q app)
[ -z "$CID" ] && { echo "app container not found"; exit 1; }
for i in $(seq 1 36); do                     # up to 3 minutes
  STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$CID" 2>/dev/null || echo missing)
  [ "$STATUS" = healthy ] && { echo "app is healthy"; exit 0; }
  sleep 5
done
echo "app did not become healthy (status: $STATUS) — last log lines:"
docker compose "$@" logs --tail 40 app
exit 1
