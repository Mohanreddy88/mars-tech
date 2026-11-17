#!/bin/bash
# Nightly DB + uploads backup, keeps 14 days. Install with:
#   (crontab -l 2>/dev/null; echo "30 2 * * * /opt/hrms/deploy/backup.sh >> /var/log/hrms-backup.log 2>&1") | crontab -
set -euo pipefail
cd "$(dirname "$0")"
source .env

DEST=/opt/hrms-backups
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"

docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$DEST/db-$STAMP.dump"
docker compose exec -T app tar -czf - -C /app/api/wwwroot uploads > "$DEST/uploads-$STAMP.tar.gz"

find "$DEST" -type f -mtime +14 -delete
echo "$(date) backup ok: $STAMP"
