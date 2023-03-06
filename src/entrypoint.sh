#!/bin/sh

# Exit immediately on error
set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
env | sed 's/=/="/;s/$/"/' > backup.env

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup"
echo "$BACKUP_CRON_EXPRESSION /root/backup.sh > /proc/1/fd/1 2>&1" >> /var/spool/cron/crontabs/root

# Let cron take the wheel
echo "Starting cron in foreground with expression: $BACKUP_CRON_EXPRESSION"
crond -f
