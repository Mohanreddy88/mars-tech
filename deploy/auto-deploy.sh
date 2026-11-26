#!/bin/bash
# Auto-deploy on push. Run from cron every 2 minutes on the VPS:
#   */2 * * * * /opt/hrms/deploy/auto-deploy.sh uat  >> /var/log/hrms-uat-deploy.log  2>&1
#   */2 * * * * /opt/hrms/deploy/auto-deploy.sh prod >> /var/log/hrms-prod-deploy.log 2>&1
#
#   uat  : branch "uat"  → /opt/hrms-uat  → deploy-uat.sh
#   prod : branch "main" → /opt/hrms      → backup.sh, then deploy.sh
#
# Deploys only when the branch has a new commit. A commit that failed to deploy
# is not retried until a newer one is pushed. One deploy at a time (shared lock).
set -uo pipefail

case "${1:-}" in
  uat)  APP_DIR=/opt/hrms-uat; BRANCH=uat;  DEPLOY=deploy-uat.sh ;;
  prod) APP_DIR=/opt/hrms;     BRANCH=main; DEPLOY=deploy.sh ;;
  *) echo "usage: $0 uat|prod"; exit 2 ;;
esac
STATE=/var/lib/hrms-$1-last-attempt

exec 9>/var/lock/hrms-deploy.lock
# uat and prod start in the same second: wait briefly for the other check instead of skipping
# this tick (a real deploy takes minutes; then give up and try again next tick).
flock -w 50 9 || exit 0

cd "$APP_DIR" || exit 1
git fetch -q origin "$BRANCH" || { echo "$(date -Is) [$1] fetch failed"; exit 1; }

REMOTE=$(git rev-parse "origin/$BRANCH")
[ "$REMOTE" = "$(git rev-parse HEAD)" ] && exit 0
[ "$REMOTE" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0   # already tried, failed

echo "$REMOTE" > "$STATE"
echo "$(date -Is) [$1] deploying $(git log -1 --format='%h %s' "$REMOTE")"

if [ "$1" = prod ]; then
  bash "$APP_DIR/deploy/backup.sh" || { echo "$(date -Is) [prod] backup FAILED — deploy skipped"; exit 1; }
fi

if bash "$APP_DIR/deploy/$DEPLOY"; then
  echo "$(date -Is) [$1] deploy OK $(git rev-parse --short HEAD)"
else
  echo "$(date -Is) [$1] deploy FAILED for ${REMOTE:0:7} — fix and push again"
fi
