#!/bin/sh
# Back up the gateway's SQLite database with a consistent online snapshot.
# Run from cron on the Docker host, e.g. nightly at 03:15:
#
#   15 3 * * * /opt/sms-gateway/deploy/backup.sh >> /var/log/sms-gateway-backup.log 2>&1
#
# BACKUP_DIR (default: deploy/backups) and KEEP_DAYS (default 14) can be set.
set -eu

cd "$(dirname "$0")"
BACKUP_DIR=${BACKUP_DIR:-./backups}
KEEP_DAYS=${KEEP_DAYS:-14}
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

# sqlite3 .backup is safe while the gateway is writing
docker compose exec -T backend sqlite3 /data/gateway.db ".backup '/data/backup-tmp.db'"
docker compose cp backend:/data/backup-tmp.db "$BACKUP_DIR/gateway-$STAMP.db"
docker compose exec -T backend rm -f /data/backup-tmp.db
gzip "$BACKUP_DIR/gateway-$STAMP.db"

find "$BACKUP_DIR" -name 'gateway-*.db.gz' -mtime +"$KEEP_DAYS" -delete
echo "Backed up to $BACKUP_DIR/gateway-$STAMP.db.gz"
