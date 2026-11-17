#!/bin/bash
# Nightly backup of EVERY database (master + one per company) and uploads; keeps 14 days.
# Files: /opt/hrms-backups/db-<database>-<stamp>.dump  (restore one company without touching others)
# Install with:
#   (crontab -l 2>/dev/null; echo "30 2 * * * /opt/hrms/deploy/backup.sh >> /var/log/hrms-backup.log 2>&1") | crontab -
set -euo pipefail
cd "$(dirname "$0")"
source .env

DEST=/opt/hrms-backups
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"

DATABASES=$(docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY 1" </dev/null)

for DB in $DATABASES; do
  docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$DB" -Fc </dev/null > "$DEST/db-$DB-$STAMP.dump"
done
docker compose exec -T app tar -czf - -C /app/api/wwwroot uploads </dev/null > "$DEST/uploads-$STAMP.tar.gz"

find "$DEST" -type f -mtime +14 -delete
echo "$(date) backup ok: $STAMP ($(echo $DATABASES | wc -w) databases: $(echo $DATABASES))"
