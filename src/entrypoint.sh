#!/bin/sh

# Exit immediately on error
set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
cat <<EOF > env.sh

# BACKUP
BACKUP_ONTHEFLY="${BACKUP_ONTHEFLY:-false}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_CRON_EXPRESSION="${BACKUP_CRON_EXPRESSION:-@daily}"
BACKUP_FILENAME=${BACKUP_FILENAME:-"backup-%Y-%m-%dT%H-%M-%S.tar.gz"}
BACKUP_ARCHIVE="${BACKUP_ARCHIVE:-/archive}"
BACKUP_UID=${BACKUP_UID:-0}
BACKUP_GID=${BACKUP_GID:-$BACKUP_UID}
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

# AWS
AWS_S3_BUCKET_NAME="${AWS_S3_BUCKET_NAME:-}"
AWS_GLACIER_VAULT_NAME="${AWS_GLACIER_VAULT_NAME:-}"
AWS_EXTRA_ARGS="${AWS_EXTRA_ARGS:-}"

# SSH
PRE_BACKUP_COMMAND="${PRE_BACKUP_COMMAND:-}"
POST_BACKUP_COMMAND="${POST_BACKUP_COMMAND:-}"
PRE_SSH_COMMAND="${PRE_SSH_COMMAND:-}"
POST_SSH_COMMAND="${POST_SSH_COMMAND:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-}"
SSH_REMOTE_PATH="${SSH_REMOTE_PATH:-}"

# INFLUXDB
INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"

# ETC
CHECK_HOST="${CHECK_HOST:-"false"}"

EOF
chmod a+x env.sh
source env.sh

# Configure AWS CLI
mkdir -p .aws
cat <<EOF > .aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
EOF
if [ ! -z "$AWS_DEFAULT_REGION" ]; then
cat <<EOF > .aws/config
[default]
region = ${AWS_DEFAULT_REGION}
EOF
fi

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup"
echo "$BACKUP_CRON_EXPRESSION /root/backup.sh > /proc/1/fd/1 2>&1" >> /var/spool/cron/crontabs/root

# Let cron take the wheel
echo "Starting cron in foreground with expression: $BACKUP_CRON_EXPRESSION"
crond -f
