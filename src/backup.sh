#!/bin/sh -e

# Cronjobs don't inherit their env, so load from file
source env.sh

function _info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

# Examples
# 	_dockerContainerLabelContains docker-volume-backup.stop-during-backup
# 	_dockerContainerLabelContains docker-volume-backup.stop-during-backup=true docker-volume-backup.newLabel
#
function _dockerContainerLabelContains() {
	local _labelFilters=""
	for label in "$@"
	do
		if [[ -z "${label}" ]]; then continue; fi
		_labelFilters="${_labelFilters} --filter "label=${label}""
	done
	if [[ ! -z "${_labelFilters}" ]];
	then
		docker ps --format "{{.ID}}" ${_labelFilters}
	fi
}

# Examples
#	_containerLabelGetValue 960a26447d46 docker-volume-backup.stop-during-backup
#
function _dockerContainerLabelValue() {
	local _id="$1"
	local _labelName="$2"
	
	docker ps --filter id=${_id} --format '{{.Label "${_labelName}"}}' | head -n 1
}

function _dockerContainerName() {
	local _id="$1"
	
	docker ps --filter id=${_id} --format '{{.Names}}'
}

function _docker(){
	local _action="$1"
	local _ids="$2"
	
	if [[ ! -z "${_ids}"}  ]];
	then
		_info "${_action} containers"
		docker ${_action} "${_ids}"
	fi
}

# Examples
#	_backupNumber 7
function _backupNumber() {
	local _fullEveryDays="$1"
	
	local _year=$(date "+%Y")
	local _dayOfYear=$(date "+%j")
	local _fullInDays=$(expr ${_dayOfYear} % ${_fullEveryDays})
	local _backupNumber=$(expr \( ${_dayOfYear} - ${_fullInDays} \) / ${_fullEveryDays})
	echo ${_year}$(printf "%02d" "${_backupNumber}")
}

function _sshBackup() {
	SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
	SSH="ssh $SSH_CONFIG -p $SSH_PORT"
	SSH_REMOTE="${SSH} ${SSH_USER}@${SSH_HOST}"

	echo -n "Test Connection... " && \
		 if ! ${SSH_REMOTE} "echo 'Successed'; sleep 1" 2>/dev/null ; then echo "Failed" && _docker start ${_containersToStop}  && exit 1; fi

	if [ ! -z "$PRE_SSH_COMMAND" ];
	then
		echo "Pre-SSH command: $PRE_SSH_COMMAND"
		${SSH_REMOTE} $PRE_SSH_COMMAND
	fi
	
	echo "Will upload to $SSH_USER@$SSH_HOST:$SSH_PORT/$SCP_DIRECTORY"
	if [[ "${BACKUP_INCREMENTAL}" == "true" ]];
	then
		${SSH_REMOTE} "mkdir -p ${_backupPathIncrementalRemote}"		
		for i in {1..3};
		do
			rsync -aviP -e "${SSH}" --stats --delete ${BACKUP_SOURCES}/ $SSH_USER@$SSH_HOST:${_backupPathIncrementalRemote}
			if [ $? -eq 0 ]; then break; fi
			if [ $i -ge 3 ]; then echo "Backup failed after ${i} times" && exit 1; fi
			_info "Repeat ${i} time due to an error"
			sleep 30
		done
		_influxdbBackupSize="$($SSH_REMOTE "du -bs ${_backupPathIncrementalRemote} | cut -f1")"
		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]];
	then
	
		tar -zcv $BACKUP_SOURCES | ${SSH_REMOTE} "cat > ${_backupPathFullRemote}"
		_influxdbBackupSize="$($SSH_REMOTE "du -bs ${_backupPathFullRemote} | cut -f1")"	
	
	else
		scp ${SSH_CONFIG} -P ${SSH_PORT} $BACKUP_FILENAME $SSH_USER@$SSH_HOST:$SSH_REMOTE_PATH
	
	fi
	
	if [ ! -z "$POST_SSH_COMMAND" ];
	then
		echo "Post-SSH command: $POST_SSH_COMMAND"
		${SSH_REMOTE} $POST_SSH_COMMAND
	fi
}

function _awsS3Backup() {
	echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\""
	aws $AWS_EXTRA_ARGS s3 cp --only-show-errors "$BACKUP_FILENAME" "s3://$AWS_S3_BUCKET_NAME/"
}

function _awsGlacierBackup() {
	echo "Will upload to vault \"$AWS_GLACIER_VAULT_NAME\""
	aws $AWS_EXTRA_ARGS glacier upload-archive --account-id - --vault-name "$AWS_GLACIER_VAULT_NAME" --body "$BACKUP_FILENAME"
}

function _archiveBackup() {
	mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
	if (($BACKUP_UID > 0)); then
	chown -v $BACKUP_UID:$BACKUP_GID "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
	fi
}



# /*
# Declarations
# */
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-volumes-%Y-%m-%dT%H-%M-%S}")"
_backupPathFullRemote="${SSH_REMOTE_PATH}/${BACKUP_FILENAME}.tar.gz"
_backupPathIncrementalRemote="${SSH_REMOTE_PATH}/backup-$(_backupNumber ${BACKUP_INCREMENTAL_MAINTAIN_DAYS})"
DOCKER_SOCK="/var/run/docker.sock"

if [ ! -z "$BACKUP_CUSTOM_LABEL" ]; then
  CUSTOM_LABEL="$BACKUP_CUSTOM_LABEL"
fi



# /*
# Main Process
# */
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
_influxdbTimeStart="$(date +%s.%N)"

if [ -S "$DOCKER_SOCK" ]; then
	_containersToStop="$(_dockerContainerLabelContains "docker-volume-backup.stop-during-backup=true" "${CUSTOM_LABEL}")"
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

if [ -S "$DOCKER_SOCK" ]; then
  for id in $(_dockerContainerLabelContains "docker-volume-backup.exec-pre-backup" "${CUSTOM_LABEL}"); do
    name="$(_dockerContainerName "$id")"
    cmd="$(_dockerContainerLabelValue "${id}" "docker-volume-backup.exec-pre-backup")"
    _info "Pre-exec command for: $name"
    echo docker exec $id $cmd # echo the command we're using, for debuggability
    eval docker exec $id $cmd
  done
fi

if [ ! -z "$PRE_BACKUP_COMMAND" ]; then
  _info "Pre-backup command"
  echo "$PRE_BACKUP_COMMAND"
  eval $PRE_BACKUP_COMMAND
fi

if [[ "${BACKUP_ONTHEFLY}" == "false" ]]; then
	_info "Creating backup"
	_influxdbTimeBackup="$(date +%s.%N)"
	tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
	_influxdbBackupSize="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
	_influxdbTimeBackedUp="$(date +%s.%N)"
	
	if [ ! -z "$GPG_PASSPHRASE" ]; then
	  _info "Encrypting backup"
	  gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" -o "${BACKUP_FILENAME}.gpg" $BACKUP_FILENAME
	  rm $BACKUP_FILENAME
	  BACKUP_FILENAME="${BACKUP_FILENAME}.gpg"
	fi
	
else 
	_info "Creating and uploading backup in one steo (On-The-Fly)"
	_influxdbTimeBackup="$(date +%s.%N)"
	if [[ ! -z "$SSH_HOST" ]]; then _sshBackup; fi
	_influxdbTimeBackedUp="$(date +%s.%N)"		
	echo "Upload finished"
fi


if [ -S "$DOCKER_SOCK" ]; then
  for id in $(_dockerContainerLabelContains "docker-volume-backup.exec-post-backup" "${CUSTOM_LABEL}"); do
	name="$(_dockerContainerName "$id")"
	cmd="$(_dockerContainerLabelValue "${id}" "docker-volume-backup.exec-post-backup")"
	_info "Post-exec command for: $name"
	echo docker exec $id $cmd # echo the command we're using, for debuggability
	eval docker exec $id $cmd
  done
fi

_docker start ${_containersToStop}


_info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

_influxdbTimeUpload="0"
_influxdbTimeUploaded="0"
if [[ "${BACKUP_ONTHEFLY}" == "false" ]];
then
	_influxdbTimeUpload="$(date +%s.%N)"
	if [ ! -z "$AWS_S3_BUCKET_NAME" ]; then _info "Uploading backup to S3" && _awsS3Backup; fi
	if [ ! -z "$AWS_GLACIER_VAULT_NAME" ]; then _info "Uploading backup to GLACIER" && _awsGlacierBackup; fi
	if [ ! -z "$SSH_HOST" ]; then _info "Uploading backup by means of SSH" && _sshBackup && exit 1; fi
	if [ -d "$BACKUP_ARCHIVE" ]; then _info "Archiving backup" && _archiveBackup; fi
	_influxdbTimeUploaded="$(date +%s.%N)"
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
_influxdbTimeFinish="$(date +%s.%N)"
_influxdbLine="$_influxdbMeasurement\
,host=$BACKUP_HOSTNAME\
\
 size_compressed_bytes=$_influxdbBackupSize\
,containers_total=$_containersCount\
,containers_stopped=$_containersToStopCount\
,time_wall=$(perl -E "say $_influxdbTimeFinish - $_influxdbTimeStart")\
,time_total=$(perl -E "say $_influxdbTimeFinish - $_influxdbTimeStart - $BACKUP_WAIT_SECONDS")\
,time_compress=$(perl -E "say $_influxdbTimeBackedUp - $_influxdbTimeBackup")\
,time_upload=$(perl -E "say $_influxdbTimeUploaded - $_influxdbTimeUpload")\
"
echo "$_influxdbLine" | sed 's/ /,/g' | tr , '\n'

if [ ! -z "$INFLUXDB_URL" ]; then
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
