#!/bin/bash
# Periodic pg_dump of the Sure database into /backups, pruned after BACKUP_KEEP_DAYS.
# Runs from the postgres image itself: no packages installed at start, no internet access needed.
set -euo pipefail
umask 077

export PGPASSWORD
PGPASSWORD="$(cat /run/secrets/postgres_password)"
interval=$(( ${BACKUP_INTERVAL_HOURS:-24} * 3600 ))
keep_days=${BACKUP_KEEP_DAYS:-7}

until pg_isready -h db -U sure -d sure_production -q; do sleep 5; done

while true; do
  stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
  partial="/backups/.sure-$stamp.sql.gz.partial"
  if pg_dump -h db -U sure -d sure_production --no-owner --no-privileges | gzip -9 > "$partial"; then
    mv "$partial" "/backups/sure-$stamp.sql.gz"
    echo "backup ok: sure-$stamp.sql.gz ($(du -h "/backups/sure-$stamp.sql.gz" | cut -f1))"
  else
    rm -f "$partial"
    echo "backup FAILED at $stamp" >&2
  fi
  find /backups -maxdepth 1 -name 'sure-*.sql.gz' -mtime +"$keep_days" -delete
  sleep "$interval"
done
