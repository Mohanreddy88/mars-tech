#!/bin/bash
# Auto-deploy UAT: runs from cron every 2 minutes on the VPS.
# If origin/uat has a new commit, runs deploy-uat.sh. A commit that failed to
# deploy is not retried until a newer commit is pushed.
#   */2 * * * * /opt/hrms-uat/deploy/auto-deploy-uat.sh >> /var/log/hrms-uat-deploy.log 2>&1
set -uo pipefail
APP_DIR=/opt/hrms-uat
STATE=/var/lib/hrms-uat-last-attempt

exec 9>/var/lock/hrms-uat-deploy.lock
flock -n 9 || exit 0            # a deploy is already running

cd "$APP_DIR" || exit 1
git fetch -q origin uat || { echo "$(date -Is) fetch failed"; exit 1; }

REMOTE=$(git rev-parse origin/uat)
LOCAL=$(git rev-parse HEAD)
[ "$REMOTE" = "$LOCAL" ] && exit 0
[ "$REMOTE" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0   # already tried, failed

echo "$REMOTE" > "$STATE"
echo "$(date -Is) deploying $(git log -1 --format='%h %s' "$REMOTE")"
if bash "$APP_DIR/deploy/deploy-uat.sh"; then
  echo "$(date -Is) deploy OK $(git rev-parse --short HEAD)"
else
  echo "$(date -Is) deploy FAILED for ${REMOTE:0:7} — fix and push again"
fi
