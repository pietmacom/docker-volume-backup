#!/bin/sh -e

# User Settings
#
BACKUP_PRE_COMMAND="${BACKUP_PRE_COMMAND:-}"
BACKUP_POST_COMMAND="${BACKUP_POST_COMMAND:-}"

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

BACKUP_GROUP="${BACKUP_GROUP:-}"

BACKUP_NOTIFICATION_URL="${BACKUP_NOTIFICATION_URL:-}"

# Behaviour For Customization
#
BACKUP_COMPRESS_EXTENSION="${BACKUP_COMPRESS_EXTENSION:-.gz}"
BACKUP_COMPRESS_PIPE="${BACKUP_COMPRESS_PIPE:-gzip}"
BACKUP_DECOMPRESS_PIPE="${BACKUP_DECOMPRESS_PIPE:-gzip -d}"

BACKUP_ENCRYPT_EXTENSION="${BACKUP_ENCRYPT_EXTENSION:-.gpg}"
BACKUP_ENCRYPT_PIPE="${BACKUP_ENCRYPT_PIPE:-gpg --symmetric --cipher-algo aes256 --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\"}"
BACKUP_DECRYPT_PIPE="${BACKUP_DECRYPT_PIPE:-gpg --decrypt --batch --passphrase \"${BACKUP_ENCRYPT_PASSPHRASE}\"}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/volumes}"

BACKUP_LABEL_CONTAINER_STOP_DURING="${BACKUP_LABEL_CONTAINER_STOP_DURING:-com.pietma.backup.container.stop-during}"								# docker-volume-backup.stop-during-backup
BACKUP_LABEL_CONTAINER_EXEC_COMMAND_BEFORE="${BACKUP_LABEL_CONTAINER_EXEC_COMMAND_BEFORE:-com.pietma.backup.container.exec-command-before}"		# docker-volume-backup.exec-pre-backup
BACKUP_LABEL_CONTAINER_EXEC_COMMAND_AFTER="${BACKUP_LABEL_CONTAINER_EXEC_COMMAND_AFTER:-com.pietma.backup.container.exec-command-after}" 		# docker-volume-backup.exec-post-backup
BACKUP_LABEL_GROUP="${BACKUP_LABEL_GROUP:-com.pietma.backup.group}"																				# 

BACKUP_NOTIFICATION_PREPARE_COMMAND="${BACKUP_NOTIFICATION_PREPARE_COMMAND:-docker pull containrrr/shoutrrr}"

# MISC
#
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"

INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
CHECK_HOST="${CHECK_HOST:-"false"}"

# Constants
BACKUP_TARGET_API_VERSION="1.0.0"
BACKUP_STRATEGY_DEFINITION="^(i*[0-9]+)(\*[0-9]+d*)?$"


source backup-functions.sh

# Preperation
#
_backupStrategyNormalized="$(_backupStrategyNormalize "${BACKUP_STRATEGY}")"
_cronScheduleNormalized="$(_backupCronNormalize "${BACKUP_STRATEGY}" "${BACKUP_CRON_SCHEDULE}")"

# Target: Check Availability
#
if [[ ! -e "backup-target-${BACKUP_TARGET}.sh" ]]; then	
	_error "Backup target [${BACKUP_TARGET}] not implemented. Try one of these...\n$(ls -1 backup-target-* | sed 's|^backup-target-||' | sed 's|.sh$||')"
	exit 1
fi
source "backup-target-${BACKUP_TARGET}.sh"

_hasFunctionOrFail "_backupApiVersion not Implemented by backup target [${BACKUP_TARGET}]" "_backupApiVersion"
if [[ ! "${BACKUP_TARGET_API_VERSION}" == "$(_backupApiVersion)" ]]; then
    _error "Backup target [${BACKUP_TARGET}] implements different API-Version [$(_backupApiVersion)]"
	exit 1
fi
