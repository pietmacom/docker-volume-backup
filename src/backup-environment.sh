#!/bin/sh -e

source backup.env # Cronjobs don't inherit their env, so load from file

DOCKER_SOCK="/var/run/docker.sock"
BACKUP_TARGET="${BACKUP_TARGET:-ssh}"

PRE_BACKUP_COMMAND="${PRE_BACKUP_COMMAND:-}"
POST_BACKUP_COMMAND="${POST_BACKUP_COMMAND:-}"

BACKUP_CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 9 * * *}"
BACKUP_ONTHEFLY="${BACKUP_ONTHEFLY:-true}"
BACKUP_STRATEGY="${BACKUP_STRATEGY:-0*10d}"
BACKUP_FILENAME_PREFIX="${BACKUP_FILENAME_PREFIX:-backup-volume}"
BACKUP_FILENAME="${BACKUP_FILENAME:-${BACKUP_FILENAME_PREFIX}-%Y-%m-%dT%H-%M-%S}"
BACKUP_ENCRYPTION_PASSPHRASE="${BACKUP_ENCRYPTION_PASSPHRASE:-}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"

BACKUP_PIPE_COMPRESS="${BACKUP_PIPE_COMPRESS:-gzip}"
BACKUP_PIPE_DECOMPRESS="${BACKUP_PIPE_DECOMPRESS:-gzip -d}"
BACKUP_PIPE_ENCRYPT="${BACKUP_PIPE_ENCRYPT:-gpg --symmetric --cipher-algo aes256 --batch --passphrase \"${BACKUP_ENCRYPTION_PASSPHRASE}\"}"
BACKUP_PIPE_DECRYPT="${BACKUP_PIPE_DECRYPT:-gpg --decrypt --batch --passphrase \"${BACKUP_ENCRYPTION_PASSPHRASE}\"}"

INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
CHECK_HOST="${CHECK_HOST:-"false"}"

# Preperation
#
if [[ ! -z "${BACKUP_CUSTOM_LABEL}" ]]; then 
	BACKUP_CUSTOM_LABEL="label=${BACKUP_CUSTOM_LABEL}"
fi
_backupStrategyNormalized="$(_backupStrategyNormalize "${BACKUP_STRATEGY}")"
_cronScheduleNormalized="$(_backupCronNormalize "${BACKUP_STRATEGY}" "${BACKUP_CRON_SCHEDULE}")"

# Target: Check Availability
#
if [[ ! -e "backup-target-${BACKUP_TARGET}.sh" ]];
then	
	_error "Backup target [${BACKUP_TARGET}] not implemented. Try one of these...\n$(ls -1 backup-target-* | sed 's|^backup-target-||' | sed 's|.sh$||')"
	exit 1
fi
source "backup-target-${BACKUP_TARGET}.sh"
