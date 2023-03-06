#!/bin/sh -e

# Cronjobs don't inherit their env, so load from file
source backup.env

#
### Functions
#
function _info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

function _dockerContainerFilter() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _filters=""
	for label in "$@"
	do
		if [[ -z "${label}" ]]; then continue; fi
		_filters="${_filters} --filter "${label}""
	done
	
	if [[ ! -z "${_filters}" ]];
	then
		docker container ls --format "{{.ID}}" --filter "status=running" ${_filters}
	fi
}

function _dockerContainerLabelValue() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _id="$1"
	local _labelName="$2"
	docker container ls --filter id=${_id} --format '{{.Label "${_labelName}"}}' | head -n 1
}

function _dockerContainerName() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _id="$1"	
	docker container ls --filter id=${_id} --format '{{.Names}}'
}

function _docker(){
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _action="$1"
	local _ids="$2"	
	if [[  -z "${_ids}"  ]]; then return 0; fi

	_info "${_action} containers"
	docker ${_action} "${_ids}"
}

function _dockerExecLabel() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _label="$1"
	for id in $(_dockerContainerFilter "label=${_label}" "${BACKUP_CUSTOM_LABEL}"); do
		name="$(_dockerContainerName "$id")"
		cmd="$(_dockerContainerLabelValue "${id}" "${_label}")"
		_info "Exec ${_label} command for: $name"
		echo docker exec -t $id $cmd # echo the command we're using, for debuggability
		eval docker exec -t $id $cmd
	done
}

function _backupNumber() {
	local _fullEveryDays="$1"
	
	local _year=$(date '+%Y')
	local _dayOfYear=$(date '+%j' | sed 's|^0*||')
	local _fullInDays=$(( ${_dayOfYear} % ${_fullEveryDays} ))
	local _backupNumber=$(( (${_dayOfYear} - ${_fullInDays}) / ${_fullEveryDays}))
	echo ${_year}$(printf "%02d" "${_backupNumber}")
}

function _backup() {
	echo "BACKUP_TARGET=${BACKUP_TARGET} not implemented"
	exit 1
}

#
### Environment
#
DOCKER_SOCK="/var/run/docker.sock"
BACKUP_TARGET="${BACKUP_TARGET:-ssh}"

PRE_BACKUP_COMMAND="${PRE_BACKUP_COMMAND:-}"
POST_BACKUP_COMMAND="${POST_BACKUP_COMMAND:-}"
BACKUP_ONTHEFLY="${BACKUP_ONTHEFLY:-false}"
BACKUP_INCREMENTAL="${BACKUP_INCREMENTAL:-false}"
BACKUP_INCREMENTAL_FILEPREFIX="${BACKUP_INCREMENTAL_FILEPREFIX:-backup}"
BACKUP_INCREMENTAL_MAINTAIN_FULL="${BACKUP_INCREMENTAL_MAINTAIN_FULL:-false}"
BACKUP_INCREMENTAL_MAINTAIN_DAYS="${BACKUP_INCREMENTAL_MAINTAIN_DAYS:-7}"

BACKUP_SOURCES="${BACKUP_SOURCES:-/backup}"
BACKUP_CRON_EXPRESSION="${BACKUP_CRON_EXPRESSION:-@daily}"
BACKUP_FILENAME=${BACKUP_FILENAME:-"backup-%Y-%m-%dT%H-%M-%S"}
BACKUP_WAIT_SECONDS="${BACKUP_WAIT_SECONDS:-0}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-$(hostname)}"
BACKUP_CUSTOM_LABEL="${BACKUP_CUSTOM_LABEL:-}"
GPG_PASSPHRASE="${GPG_PASSPHRASE:-}"

INFLUXDB_URL="${INFLUXDB_URL:-}"
INFLUXDB_DB="${INFLUXDB_DB:-}"
INFLUXDB_CREDENTIALS="${INFLUXDB_CREDENTIALS:-}"
INFLUXDB_MEASUREMENT="${INFLUXDB_MEASUREMENT:-docker_volume_backup}"
CHECK_HOST="${CHECK_HOST:-"false"}"

#
### Preperation
#
if [[ ! -z "${BACKUP_CUSTOM_LABEL}" ]];
then
	BACKUP_CUSTOM_LABEL="label=${BACKUP_CUSTOM_LABEL}"
fi

if [[ "${BACKUP_INCREMENTAL}" == "true" ]];
then
	BACKUP_ONTHEFLY="true" # So incremental backup make sense
fi

if [[ ! -e "backup-target-${BACKUP_TARGET}.sh" ]];
then	
	_info "Backup target [${BACKUP_TARGET}] not implemented."
	echo "Try on of these...\n"
	ls -1 backup-target-* | sed 's|^backup-target-||' | sed 's|.sh$||'	
	exit 1
fi

source "backup-target-${BACKUP_TARGET}.sh"

#
### Main Process
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

if [ ! -z "$PRE_BACKUP_COMMAND" ]; then
  _info "Pre-backup command"
  echo "$PRE_BACKUP_COMMAND"
  eval $PRE_BACKUP_COMMAND
fi

if [[ "${BACKUP_ONTHEFLY}" == "false" ]]; then
	_backupFullFilename="$(date +"${BACKUP_FILENAME}tar.gz")"
	
	_info "Creating backup"
	_influxdbTimeBackup="$(date +%s)"
	tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
	_influxdbBackupSize="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
	_influxdbTimeBackedUp="$(date +%s)"
	
	if [ ! -z "$GPG_PASSPHRASE" ]; then
	  _info "Encrypting backup"
	  gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" -o "${BACKUP_FILENAME}.gpg" $BACKUP_FILENAME
	  rm $BACKUP_FILENAME
	  BACKUP_FILENAME="${BACKUP_FILENAME}.gpg"
	fi
	
else 
	_backupIncrementalDirectoryName="${BACKUP_INCREMENTAL_FILEPREFIX}-$(_backupNumber ${BACKUP_INCREMENTAL_MAINTAIN_DAYS})"
	_backupFullFilename="${_backupIncrementalDirectoryName}.tar.gz"
	
	_info "Create and upload backup in one step (On-The-Fly)"
	_influxdbTimeBackup="$(date +%s)"
	_backup
	_influxdbTimeBackedUp="$(date +%s)"		
	echo "Upload finished"
	
fi

_dockerExecLabel "docker-volume-backup.exec-post-backup"
_docker start ${_containersToStop}

_info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

_influxdbTimeUpload="0"
_influxdbTimeUploaded="0"
if [[ "${BACKUP_ONTHEFLY}" == "false" ]];
then
	_influxdbTimeUpload="$(date +%s)"
	_backup
	_influxdbTimeUploaded="$(date +%s)"
fi

if [ ! -z "$POST_BACKUP_COMMAND" ]; then
  _info "Post-backup command"
  echo "$POST_BACKUP_COMMAND"
  eval $POST_BACKUP_COMMAND
fi

if [ -f "$BACKUP_FILENAME" ]; then
  _info "Cleaning up"
  rm -vf "$BACKUP_FILENAME"
fi

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

