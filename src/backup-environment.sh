#!/bin/sh -e

source backup.env # Cronjobs don't inherit their env, so load from file



PRE_BACKUP_COMMAND="${PRE_BACKUP_COMMAND:-}"
POST_BACKUP_COMMAND="${POST_BACKUP_COMMAND:-}"

DOCKER_SOCK="${DOCKER_SOCK:-}"
BACKUP_TARGET="${BACKUP_TARGET:-ssh}"
BACKUP_CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 9 * * *}"
BACKUP_ONTHEFLY="${BACKUP_ONTHEFLY:-true}"
BACKUP_STRATEGY="${BACKUP_STRATEGY:-0*10d}"
BACKUP_FILENAME_PREFIX="${BACKUP_FILENAME_PREFIX:-backup-volume}"
BACKUP_FILENAME="${BACKUP_FILENAME:-${BACKUP_FILENAME_PREFIX}-%Y-%m-%dT%H-%M-%S}"
BACKUP_ENCRYPT_PASSPHRASE="${BACKUP_ENCRYPT_PASSPHRASE:-}"

BACKUP_IMAGES="${BACKUP_IMAGES:-false}"
BACKUP_IMAGES_FILENAME_PREFIX="${BACKUP_IMAGES_FILENAME_PREFIX:-backup-image}"

# Application Properties For Customization
#
BACKUP_COMPRESS_EXTENSION="${BACKUP_COMPRESS_EXTENSION:-.gz}"
BACKUP_COMPRESS_PIPE="${BACKUP_COMPRESS_PIPE:-gzip}"
BACKUP_DECOMPRESS_PIPE="${BACKUP_DECOMPRESS_PIPE:-gzip -d}"

BACKUP_ENCRYPT_EXTENSION="${BACKUP_ENCRYPT_EXTENSION:-.gpg}"
BACKUP_ENCRYPT_PIPE="${BACKUP_ENCRYPT_PIPE:-gpg --symmetric --cipher-algo aes256 --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\"}"
BACKUP_DECRYPT_PIPE="${BACKUP_DECRYPT_PIPE:-gpg --decrypt --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\"}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"

# ---

BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"

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
if [[ ! -e "backup-target-${BACKUP_TARGET}.sh" ]]; then	
	_error "Backup target [${BACKUP_TARGET}] not implemented. Try one of these...\n$(ls -1 backup-target-* | sed 's|^backup-target-||' | sed 's|.sh$||')"
	exit 1
fi
source "backup-target-${BACKUP_TARGET}.sh"
