#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh # Cronjobs don't inherit their env, so load from file

# Target: Check Availability Of Functions
#
for _definition in ${_backupStrategyNormalized}
do
	_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
	_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
	
	if [[ "${_iteration}" == "i"* ]]; then 
		_hasFunctionOrFail "_backupIncremental not Implemented by backup target [${BACKUP_TARGET}]" "_backupIncremental";	
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]]; then
		if [ ! -z "$BACKUP_ENCRYPT_PASSPHRASE" ];
			then _hasFunctionOrFail "_backupEncryptedArchiveOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupEncryptedArchiveOnTheFly";			
			else _hasFunctionOrFail "_backupArchiveOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchiveOnTheFly";			
		fi
	else
		if [ ! -z "$BACKUP_ENCRYPT_PASSPHRASE" ];
			then _hasFunctionOrFail "_backupEncryptedArchive not Implemented by backup target [${BACKUP_TARGET}]" "_backupEncryptedArchive";
			else _hasFunctionOrFail "_backupArchive not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchive";
		fi
	fi

	if [[ "${_iteration}" == "i"* ]]; then # incremental backups maintain only one directory per _retentionDays
		_hasFunctionOrFail "_backupRemoveIncrementalOlderThanDays not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveIncrementalOldest"		
	elif [[ "${_retention}" == *"d" ]]; then 
		_hasFunctionOrFail "_backupRemoveArchiveOlderThanDays not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOlderThanDays"
	else
		_hasFunctionOrFail "_backupRemoveArchiveOldest not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOldest"
	fi
done

# Main Process
#
_backupStrategyExplain "${_backupStrategyNormalized}"

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
	_containersToStopCount="$(echo "${_containersToStop}" | wc -l)"
	_containersCount="$(docker ps --format "{{.ID}}" | wc -l)"

	echo "$_containersCount containers running on host in total"
	echo "$_containersToStopCount containers marked to be stopped during backup"
else
  _containersToStop="0"
  _containersCount="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi

_docker stop "${_containersToStop}"
_dockerExecLabel "docker-volume-backup.exec-pre-backup"
_exec "Pre-backup command" "$PRE_BACKUP_COMMAND"

_execFunction "Test connection" "_backupTestConnection"
_execFunction "Pre-Upload command" "_backupPreUploadCommand"
_influxdbTimeBackup="$(date +%s)"

_backupStrategyIterationDays=""
for _definition in ${_backupStrategyNormalized}
do
	_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
	_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
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
		_execFunctionOrFail "Create incremental backup" "_backupIncremental" "${BACKUP_SOURCES}" "${_fileName}" 
		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]]; then
		if [ ! -z "$BACKUP_ENCRYPT_PASSPHRASE" ];
			then _execFunctionOrFail "Create, Encrypt and upload backup in one step (On-The-Fly)" "_backupEncryptedArchiveOnTheFly" "${BACKUP_SOURCES}" "${_fileNameArchive}"			
			else _execFunctionOrFail "Create and upload backup in one step (On-The-Fly)" "_backupArchiveOnTheFly" "${BACKUP_SOURCES}" "${_fileNameArchive}"
		fi		
	else		
		tar -cv -C ${BACKUP_SOURCES} . > ${_fileNameArchive} # allow the var to expand, in case we have multiple sources
		if [ ! -z "$BACKUP_ENCRYPT_PASSPHRASE" ]; 
			then _execFunctionOrFail "Upload encrypted archiv" "_backupEncryptedArchive" "${_fileNameArchive} ${_fileNameArchive}"
			else _execFunctionOrFail "Upload archiv" "_backupArchive" "${_fileNameArchive} ${_fileNameArchive}"
		fi
		rm ${_fileName}.tar
	fi
	
	if [[ "${_iteration}" == "i"* ]]; then # incremental backups maintain only one directory per _retentionDays
		_execFunctionOrFail "Remove oldest ${_retentionNumber} incremental backups [prefix: ${_fileNamePrefix}*]" "_backupRemoveIncrementalOldest" "${_fileNamePrefix}"
	elif [[ "${_retention}" == *"d" ]]; then 
		_execFunctionOrFail "Remove archive backups [prefix: ${_fileNamePrefix}*] older than ${_retentionDays} days" "_backupRemoveArchiveOlderThanDays" "${_fileNamePrefix} ${_retentionDays}"
	else
		_execFunctionOrFail "Remove oldest ${_retentionNumber} archive backups [prefix: ${_fileNamePrefix}*]" "_backupRemoveArchiveOldest" "${_fileNamePrefix} ${_retentionNumber}"
	fi
done
_influxdbTimeBackedUp="$(date +%s)"
_execFunction "Post-Upload command" "_backupPostUploadCommand"
echo "Upload finished"


_dockerExecLabel "docker-volume-backup.exec-post-backup"
_docker start "${_containersToStop}"

_info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

_influxdbTimeUpload="0"
_influxdbTimeUploaded="0"

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

