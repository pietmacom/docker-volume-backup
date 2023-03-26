#!/bin/sh -e

source backup-environment.sh

# Main
#
_info "Validate backup strategy"
_backupStrategyExplain "${_backupStrategyNormalized}"
_backupStrategyValidate "${_backupStrategyNormalized}"


if [ "${CHECK_HOST}" != "false" ]; then
  _info "Check host availability"
  TEMPFILE="$(mktemp)"
  ping -c 1 ${CHECK_HOST} | grep '1 packets transmitted, 1 received' > "$TEMPFILE"
  PING_RESULT="$(cat $TEMPFILE)"
  if [ ! -z "$PING_RESULT" ]; then
    echo "$CHECK_HOST is available."
  else
    echo "$CHECK_HOST is not available."
    _info "Backup skipped"
    exit 0
  fi
fi

_info "Start backup"
_metaBackupStart="$(date +%s)"
if [ -S "$DOCKER_SOCK" ]; then
	_backupGroupFilter=""
	if [[ ! -z "${BACKUP_GROUP}" ]]; then 
		_backupGroupFilter="label=${BACKUP_LABEL_GROUP}=${BACKUP_GROUP}"
	fi	
	_containersToStop="$(_dockerContainerFilter "status=running" "label=${BACKUP_LABEL_CONTAINER_STOP_DURING}" "${_backupGroupFilter}")"
	_containersToStopCount="$(echo "${_containersToStop}" | wc -l)"
	_containersCount="$(docker ps --format "{{.ID}}" | wc -l)"

	echo "$_containersCount containers running on host in total"
	echo "$_containersToStopCount containers marked to be stopped during backup"
else
  _containersToStop="0"
  _containersCount="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi

_dockerExecLabel "Run Pre-Backup command in containers" "${BACKUP_LABEL_CONTAINER_EXEC_COMMAND_BEFORE}"
_docker "Stop containers" "stop" "${_containersToStop}"
_exec "Run Pre-Backup command" "$BACKUP_PRE_COMMAND"

_execFunction "Test connection" "_backupTestConnection"
_execFunction "Run Pre-Upload command" "_backupPreUploadCommand"

_info "Wait before processing"
echo "Sleeping ${BACKUP_WAIT_SECONDS} seconds..."
sleep "${BACKUP_WAIT_SECONDS}"

# Volumes
#
_metaTimeUploadStart="$(date +%s)"
_backupStrategyIterationDays=""
for _definition in ${_backupStrategyNormalized}; do
	_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\1|g")
	_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\2|g" | sed 's|^\*||')
	_iterationNumber="$(echo "${_iteration}" | sed 's|^i||')"
	_retentionNumber="$(echo "${_retention}" | sed 's|d$||')"
	
	# _backupStrategyIterationDays
	if [[ -z "${_backupStrategyIterationDays}" ]];
		then _backupStrategyIterationDays="${_iterationNumber}"
		else _backupStrategyIterationDays="$(( ${_backupStrategyIterationDays} * ${_iterationNumber} ))"
	fi
	
	# _retentionDays - Always individual per definition
	_retentionDays="$(( ${_backupStrategyIterationDays} * ${_retentionNumber} ))"
	if [[ "${_retention}" == *"d" ]]; then
		_retentionDays=$(( ${_backupStrategyIterationDays} + ${_retentionNumber} ))
	fi

	_fileNamePrefix="${BACKUP_FILENAME_PREFIX}-i${_backupStrategyIterationDays}r${_retentionDays}"		
	if [[ "${_iteration}" == "i"* ]]; then 
		_fileName="${_fileNamePrefix}-$(_backupNumber ${_retentionDays})";
	elif [[ "${_iterationNumber}" == "0" ]]; then # Backup every run with individual name
		_fileNamePrefix="${BACKUP_FILENAME_PREFIX}"
		_fileName="$(date +"${BACKUP_FILENAME}")"		
	else
		_fileName="${_fileNamePrefix}-$(_backupNumber ${_backupStrategyIterationDays})";		
	fi

	_fileNameArchive="${_fileName}.tar"	
	if [[ "${_iteration}" == "i"* ]]; then
		_execFunctionOrFail "Create incremental backup [${_fileName}]" "_backupIncremental" "${BACKUP_SOURCES}" "${_fileName}" 
		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]]; then
		if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ];
			then _execFunctionOrFail "Create, encrypt and upload backup in one step (On-The-Fly) [${_fileNameArchive}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}]" "_backupArchiveEncryptedOnTheFly" "${BACKUP_SOURCES}" "${_fileNameArchive}"			
			else _execFunctionOrFail "Create and upload backup in one step (On-The-Fly) [${_fileNameArchive}${BACKUP_COMPRESS_EXTENSION}]" "_backupArchiveOnTheFly" "${BACKUP_SOURCES}" "${_fileNameArchive}"
		fi		
	else		
		_metaTimeCompressStart="$(date +%s)"
		tar -cv -C ${BACKUP_SOURCES} . > ${_fileNameArchive} # allow the var to expand, in case we have multiple sources
		_metaTimeCompressEnd="$(date +%s)"
		
		if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ]; 
			then _execFunctionOrFail "Upload encrypted archiv [${_fileNameArchive}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}]" "_backupArchiveEncrypted" "${_fileNameArchive}" "${_fileNameArchive}"
			else _execFunctionOrFail "Upload archiv [${_fileNameArchive}${BACKUP_COMPRESS_EXTENSION}]" "_backupArchive" "${_fileNameArchive}" "${_fileNameArchive}"
		fi
		rm "${_fileNameArchive}"
	fi
	
	if [[ "${_iteration}" == "i"* ]]; then # incremental backups maintain only one directory per _retentionDays
		_execFunctionOrFail "Remove previous incremental backups" "_backupRemoveIncrementalPrevious" "${_fileNamePrefix}"
	elif [[ "${_retention}" == *"d" ]]; then 
		_execFunctionOrFail "Remove archive backups [${_fileNamePrefix}*] older than ${_retentionDays} days" "_backupRemoveArchiveOlderThanDays" "${_fileNamePrefix}" "${_retentionDays}"
	else
		_execFunctionOrFail "Remove oldest ${_retentionNumber} archive backups [${_fileNamePrefix}*]" "_backupRemoveArchiveOldest" "${_fileNamePrefix}" "${_retentionNumber}"
	fi
done

# Images
#
if [[ "${BACKUP_IMAGES}" == "true" ]]; then
	if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ];
		then _execFunctionOrFail "Create, encrypt and upload images in one step (On-The-Fly)" "_backupImagesEncryptedOnTheFly" "${BACKUP_IMAGES_FILENAME_PREFIX}" "$(docker image ls -q)"
		else _execFunctionOrFail "Create and upload images in one step (On-The-Fly)" "_backupImagesOnTheFly" "${BACKUP_IMAGES_FILENAME_PREFIX}" "$(docker image ls -q)"
	fi
	 _execFunctionOrFail "Remove deleted images [${BACKUP_IMAGES_FILENAME_PREFIX}*]" "_backupRemoveImages" "${BACKUP_IMAGES_FILENAME_PREFIX}" "$(docker image ls -q)"
fi
_metaTimeUploadedEnd="$(date +%s)"

_execFunction "Run Post-Upload command" "_backupPostUploadCommand"
_docker "Start containers" "start" "${_containersToStop}"
_dockerExecLabel "Run Post-Backup command in containers" "${BACKUP_LABEL_CONTAINER_EXEC_COMMAND_AFTER}"
_exec "Run Post-backup command" "$BACKUP_POST_COMMAND"
_metaBackupEnd="$(date +%s)"


_info "Collecting metrics"

# Set defaults if not set
#
_metaBackupStart="${_metaBackupStart:-0}"
_metaBackupEnd="${_metaBackupEnd:-0}"
_containersCount="${_containersCount:-0}"
_containersToStopCount="${_containersToStopCount:-0}"
_metaTimeCompressStart="${_metaTimeCompressStart:-0}"
_metaTimeCompressEnd="${_metaTimeCompressEnd:-0}"
_metaTimeUploadStart="${_metaTimeUploadStart:-0}"
_metaTimeUploadedEnd="${_metaTimeUploadedEnd:-0}"

_influxdbLine="${INFLUXDB_MEASUREMENT}\
,host=${BACKUP_HOSTNAME}\
\
 size_compressed_bytes=${_metaBackupSize}\
,containers_total=${_containersCount}\
,containers_stopped=${_containersToStopCount}\
,time_wall=$(( ${_metaBackupEnd} - ${_metaBackupStart} ))\
,time_total=$(( ${_metaBackupEnd} - ${_metaBackupStart} - ${BACKUP_WAIT_SECONDS} ))\
,time_compress=$(( ${_metaTimeCompressEnd} - ${_metaTimeCompressStart} ))\
,time_upload=$(( ${_metaTimeUploadedEnd} - ${_metaTimeUploadStart} ))\
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

_info "Finished backup"
echo "Will wait for next scheduled backup"

