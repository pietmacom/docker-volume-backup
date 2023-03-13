#!/bin/sh -e

source backup.env # Cronjobs don't inherit their env, so load from file
source backup-functions.sh

# Environment
#
DOCKER_SOCK="/var/run/docker.sock"
BACKUP_TARGET="${BACKUP_TARGET:-ssh}"

PRE_BACKUP_COMMAND="${PRE_BACKUP_COMMAND:-}"
POST_BACKUP_COMMAND="${POST_BACKUP_COMMAND:-}"

BACKUP_CRON_SCHEDULE="${BACKUP_CRON:-0 9 * * *}"
BACKUP_ONTHEFLY="${BACKUP_ONTHEFLY:-true}"
BACKUP_STRATEGY="${BACKUP_STRATEGY:-0*10d}"
BACKUP_PREFIX="${BACKUP_PREFIX:-backup-volume}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
CHECK_HOST="${CHECK_HOST:-"false"}"

# Preperation
#
if [[ ! -z "${BACKUP_CUSTOM_LABEL}" ]]; then BACKUP_CUSTOM_LABEL="label=${BACKUP_CUSTOM_LABEL}"; fi
_backupStrategyNormalized="$(_backupStrategyNormalize ${BACKUP_STRATEGY})"
_cronScheduleNormalized="$(_backupCronNormalize ${BACKUP_STRATEGY} ${BACKUP_CRON_SCHEDULE})"

# Check Availability Of Target
if [[ ! -e "backup-target-${BACKUP_TARGET}.sh" ]];
then	
	_error "Backup target [${BACKUP_TARGET}] not implemented. Try one of these...\n$(ls -1 backup-target-* | sed 's|^backup-target-||' | sed 's|.sh$||')"
	exit 1
fi
source "backup-target-${BACKUP_TARGET}.sh"

# Check Availability Of Functions
#
for _definition in ${_backupStrategyNormalized}
do
	_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
	_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
	
	if [[ "${_iteration}" == "i"* ]];
		then _hasFunctionOrFail "_backupIncremental not Implemented by backup target [${BACKUP_TARGET}]" "_backupIncremental";		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]];
		then _hasFunctionOrFail "_backupArchiveOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchiveOnTheFly";
		else _hasFunctionOrFail "_backupArchive not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchive";
	fi

	if [[ "${_retention}" == *"d" ]]; then
		if [[ "${_iteration}" == "i"* ]];
			then _hasFunctionOrFail "_backupRemoveIncrementalOlderThanDays not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveIncrementalOlderThanDays";
			else _hasFunctionOrFail "_backupRemoveArchiveOlderThanDays not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOlderThanDays";
		fi
	else
		if [[ "${_iteration}" == "i"* ]];
			then _hasFunctionOrFail "_backupRemoveIncrementalOldest not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveIncrementalOldest";
			else _hasFunctionOrFail "_backupRemoveArchiveOldest not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOldest";
		fi
	fi
done


# Main Process
#
if [ "$CHECK_HOST" != "false" ]; then
  _info "Check host availability"
  TEMPFILE="$(mktemp)"
  ping -c 1 $CHECK_HOST | grep '1 packets transmitted, 1 received' > "$TEMPFILE"
  PING_RESULT="$(cat $TEMPFILE)"
  if [ ! -z "$PING_RESULT" ]; then
    echo "$CHECK_HOST is available."
  else
    echo "$CHECK_HOST is not available."
    _info "Backup skipped"
    exit 0
  fi
fi

_info "Backup starting"
_influxdbTimeStart="$(date +%s)"
if [ -S "$DOCKER_SOCK" ]; then
	_containersToStop="$(_dockerContainerFilter "status=running" "label=docker-volume-backup.stop-during-backup=true" "${BACKUP_CUSTOM_LABEL}")"
	_containersToStopCount="$(echo ${_containersToStop} | wc -l)"
	_containersCount="$(docker ps --format "{{.ID}}" | wc -l)"

	echo "$_containersCount containers running on host in total"
	echo "$_containersToStopCount containers marked to be stopped during backup"
else
  _containersToStop="0"
  _containersCount="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi

_docker stop ${_containersToStop}
_dockerExecLabel "docker-volume-backup.exec-pre-backup"
_exec "Pre-backup command" "$PRE_BACKUP_COMMAND"

_execFunction "Test connection" "_backupTestConnection"
_execFunction "Pre-Upload command" "_backupPreUploadCommand"
_influxdbTimeBackup="$(date +%s)"
for _definition in ${_backupStrategyNormalized}
do
	_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
	_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
	_iterationNumber="$(echo "${_iteration}" | sed 's|^i||')"
	_retentionNumber="$(echo "${_retention}" | sed 's|d$||')"
	
	if [[ "${_iterationNumber}" == "0" ]]; then
		_filePrefix="${BACKUP_PREFIX}"
		_fileName="${_filePrefix}-$(date +'%Y-%m-%dT%H-%M-%S')"
	else
		_retentionDays="$(( ${_iterationNumber} * ${_retentionNumber} ))"
		_filePrefix="${BACKUP_PREFIX}-${_retentionDays}"
		_fileName="${_filePrefix}-$(_backupNumber ${_iterationNumber})"
	fi
	_fileNameArchive="${_fileName}.tar.gz"
	
	if [[ "${_iteration}" == "i"* ]];
		then _execFunctionOrFail "Create incremental backup" "_backupIncremental" "${_fileName}" 
		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]];
		then _execFunctionOrFail "Create and upload backup in one step (On-The-Fly)" "_backupArchiveOnTheFly" "${_fileNameArchive}"
		
	else
		tar -czvf "${_fileNameArchive}" -C ${BACKUP_SOURCES} . # allow the var to expand, in case we have multiple sources
		if [ -z "$GPG_PASSPHRASE" ];
		then _execFunctionOrFail "Upload archiv" "_backupArchive" "${_fileNameArchive}"
		else
			_info "Encrypting backup"
			gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" -o "${_fileNameArchive}.gpg" ${_fileNameArchive}
			rm ${_fileNameArchive}
			_execFunctionOrFail "Upload archiv" "_backupArchive" "${_fileNameArchive}.gpg"
		fi
	fi
	
	if [[ "${_retention}" == *"d" ]]; then 
		if [[ "${_iteration}" == "i"* ]];
			then _execFunctionOrFail "Remove incremental backups [${_filePrefix}*] older than ${_retentionNumber} days" "_backupRemoveIncrementalOlderThanDays" "${_filePrefix} ${_retentionNumber}";
			else _execFunctionOrFail "Remove archive backups [${_filePrefix}*] older than ${_retentionNumber} days" "_backupRemoveArchiveOlderThanDays" "${_filePrefix} ${_retentionNumber}";
		fi
	else
		if [[ "${_iteration}" == "i"* ]];
			then _execFunctionOrFail "Remove oldest ${_retentionNumber} incremental backups [${_filePrefix}*]" "_backupRemoveIncrementalOldest" "${_filePrefix} ${_retentionNumber}";
			else _execFunctionOrFail "Remove oldest ${_retentionNumber} archive backups [${_filePrefix}*]" "_backupRemoveArchiveOldest" "${_filePrefix} ${_retentionNumber}";
		fi
	fi
done
_influxdbTimeBackedUp="$(date +%s)"
_execFunction "Post-Upload command" "_backupPostUploadCommand"
echo "Upload finished"


_dockerExecLabel "docker-volume-backup.exec-post-backup"
_docker start ${_containersToStop}

_info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

_influxdbTimeUpload="0"
_influxdbTimeUploaded="0"
if [[ "${BACKUP_ONTHEFLY}" == "false" ]];
then
	_execFunction "Test connection" "_backupTestConnection"
	_execFunction "Pre-Upload command" "_backupPreUploadCommand"
	_influxdbTimeUpload="$(date +%s)"
	_execFunctionOrFail "Upload archive" "_backupArchive"
	_influxdbTimeUploaded="$(date +%s)"
	_execFunction "Post-Upload command" "_backupPostUploadCommand"
fi

_exec "Post-backup command" "$POST_BACKUP_COMMAND"

if [ -f "$BACKUP_FILENAME" ]; then
  _info "Cleaning up"
  rm -vf "$BACKUP_FILENAME"
fi


_execFunction "Remove oldest backups" "_backupRemoveOldest" 3


_info "Collecting metrics"
_influxdbTimeFinish="$(date +%s)"
_influxdbLine="${INFLUXDB_MEASUREMENT}\
,host=${BACKUP_HOSTNAME}\
\
 size_compressed_bytes=$_influxdbBackupSize\
,containers_total=$_containersCount\
,containers_stopped=$_containersToStopCount\
,time_wall=$(( ${_influxdbTimeFinish} - ${_influxdbTimeStart} ))\
,time_total=$(( ${_influxdbTimeFinish} - ${_influxdbTimeStart} - ${BACKUP_WAIT_SECONDS} ))\
,time_compress=$(( ${_influxdbTimeBackedUp} - ${_influxdbTimeBackup} ))\
,time_upload=$(( ${_influxdbTimeUploaded} - ${_influxdbTimeUpload} ))\
"
echo "$_influxdbLine" | sed 's/ /,/g' | tr , '\n'

if [[ ! -z "$INFLUXDB_URL" ]]; then
  _info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$_influxdbLine"
fi

_info "Backup finished"
echo "Will wait for next scheduled backup"

