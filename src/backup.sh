#!/bin/sh -e

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

# Parameters:
#	List Of Labels
#
# Returns
#	List Of ContainerIds
#
# Examples
# 	_containerLabelContain docker-volume-backup.stop-during-backup
# 	_containerLabelContain docker-volume-backup.stop-during-backup=true docker-volume-backup.newLabel
#
function _containerLabelContain() {
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

# Parameters: 
#	container-id 
#	label
#
# Returns:
#	Value Assigned To Label
#
# Examples
#	_containerLabelGetValue 960a26447d46 docker-volume-backup.stop-during-backup
#
function _containerLabelValue() {
	local _id="$1"
	local _labelName="$2"
	docker ps --filter id=${_id} --format '{{.Label "${_labelName}"}}' | head -n 1
}

function _containerName() {
	local _id="$1"
	docker ps --filter id=${_id} --format '{{.Names}}'
}

function _docker(){
	local _action="$1"
	local _ids="$2"
	
	if [[ ! -z "${_ids}"}  ]];
	then
		info "${_action} containers"
		docker ${_action} "${_ids}"
	fi
}


SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
SSH="ssh $SSH_CONFIG -p $SSH_PORT"
SSH_REMOTE="${SSH} ${SSH_USER}@${SSH_HOST}"

SCP="scp ${SSH_CONFIG} -P ${SSH_PORT}"
RSYNC="rsync -aviP -e "${SSH}" --stats --delete --port ${SSH_PORT}"

# ---- 

if [ "$CHECK_HOST" != "false" ]; then
  info "Check host availability"
  TEMPFILE="$(mktemp)"
  ping -c 1 $CHECK_HOST | grep '1 packets transmitted, 1 received' > "$TEMPFILE"
  PING_RESULT="$(cat $TEMPFILE)"
  if [ ! -z "$PING_RESULT" ]; then
    echo "$CHECK_HOST is available."
  else
    echo "$CHECK_HOST is not available."
    info "Backup skipped"
    exit 0
  fi
fi

info "Backup starting"
_influxdbTimeStart="$(date +%s.%N)"
DOCKER_SOCK="/var/run/docker.sock"

if [ ! -z "$BACKUP_CUSTOM_LABEL" ]; then
  CUSTOM_LABEL="$BACKUP_CUSTOM_LABEL"
fi

if [ -S "$DOCKER_SOCK" ]; then
	_containersToStop="$(_containerLabelContain "docker-volume-backup.stop-during-backup=true" "${CUSTOM_LABEL}")"
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
  for id in $(_containerLabelContain "docker-volume-backup.exec-pre-backup" "${CUSTOM_LABEL}"); do
    name="$(_containerName "$id")"
    cmd="$(_containerLabelValue "${id}" "docker-volume-backup.exec-pre-backup")"
    info "Pre-exec command for: $name"
    echo docker exec $id $cmd # echo the command we're using, for debuggability
    eval docker exec $id $cmd
  done
fi

if [ ! -z "$PRE_BACKUP_COMMAND" ]; then
  info "Pre-backup command"
  echo "$PRE_BACKUP_COMMAND"
  eval $PRE_BACKUP_COMMAND
fi

info "Creating backup"
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-volumes-%Y-%m-%dT%H-%M-%S.tar.gz}")"
###
# On-The-Fly: SSH
#
if [[ "${BACKUP_ONTHEFLY}" == "true" ]] && [[ ! -z "$SSH_HOST" ]]; then
	info "Uploading backup On-The-Fly by means of SSH"
	
	# Test connection before 
	echo -n "Test Connection... " && \
		if ${SSH_REMOTE} "echo > /dev/null" 1>/dev/null 2>/dev/null ; then echo "Successed"; else echo "Failed" && _docker start ${_containersToStop}  && exit 1; fi
	sleep 1

	if [ ! -z "$PRE_SSH_COMMAND" ]; then
		echo "Pre-scp command: $PRE_SSH_COMMAND"
		${SSH_REMOTE} $PRE_SSH_COMMAND
	fi		

	_influxdbTimeBackup="$(date +%s.%N)"			
	if [[ "${BACKUP_INCREMENTAL}" == "true" ]];
	then
		echo "Will Synchronize To $SSH_HOST:$SSH_REMOTE_PATH:$SSH_PORT"
		_sshRemotePathBackupIncremental="${SSH_REMOTE_PATH}/${BACKUP_FILENAME}-incremental"
		${SSH_REMOTE} "mkdir -p ${_sshRemotePathBackupIncremental}"		
        for i in {1..3};
        do
			${RSYNC} ${BACKUP_SOURCES}/ $SSH_USER@$SSH_HOST:${_sshRemotePathBackupIncremental}
			if [ $? -eq 0 ]; then
					break;
			fi

			if [ $i -ge 3 ];
			then
				echo "Backup failed after ${i} times"
				exit 1
			fi

			echo "Repeat ${i} time due to an error"
			sleep 30
        done
		
	else
		echo "Will upload to $SSH_HOST:$SSH_REMOTE_PATH:$SSH_PORT"
		tar -zcv $BACKUP_SOURCES | ${SSH_REMOTE} "cat > $SSH_REMOTE_PATH/$BACKUP_FILENAME"
		
	fi
	echo "Upload finished"
	_influxdbTimeBackedUp="$(date +%s.%N)"
	_influxdbBackupSize="$($SSH "du -bs $SSH_REMOTE_PATH/$BACKUP_FILENAME")"		

	
	if [ ! -z "$POST_SSH_COMMAND" ]; then
		echo "Post-scp command: $POST_SSH_COMMAND"
		${SSH_REMOTE} $POST_SSH_COMMAND
	fi

###
# Temporary File
#
else 	
	_influxdbTimeBackup="$(date +%s.%N)"
	tar -czvf "$BACKUP_FILENAME" $BACKUP_SOURCES # allow the var to expand, in case we have multiple sources
	_influxdbBackupSize="$(du --bytes $BACKUP_FILENAME | sed 's/\s.*$//')"
	_influxdbTimeBackedUp="$(date +%s.%N)"
	
	if [ ! -z "$GPG_PASSPHRASE" ]; then
	  info "Encrypting backup"
	  gpg --symmetric --cipher-algo aes256 --batch --passphrase "$GPG_PASSPHRASE" -o "${BACKUP_FILENAME}.gpg" $BACKUP_FILENAME
	  rm $BACKUP_FILENAME
	  BACKUP_FILENAME="${BACKUP_FILENAME}.gpg"
	fi
	
fi

if [ -S "$DOCKER_SOCK" ]; then
  for id in $(_containerLabelContain "docker-volume-backup.exec-post-backup" "${CUSTOM_LABEL}"); do
	name="$(_containerName "$id")"
	cmd="$(_containerLabelValue "${id}" "docker-volume-backup.exec-post-backup")"
	info "Post-exec command for: $name"
	echo docker exec $id $cmd # echo the command we're using, for debuggability
	eval docker exec $id $cmd
  done
fi

_docker start ${_containersToStop}


info "Waiting before processing"
echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
sleep "$BACKUP_WAIT_SECONDS"

_influxdbTimeUpload="0"
_influxdbTimeUploaded="0"
if [ -f "$BACKUP_FILENAME" ]; then
then
	if [ ! -z "$AWS_S3_BUCKET_NAME" ]; then
	  info "Uploading backup to S3"
	  echo "Will upload to bucket \"$AWS_S3_BUCKET_NAME\""
	  _influxdbTimeUpload="$(date +%s.%N)"
	  aws $AWS_EXTRA_ARGS s3 cp --only-show-errors "$BACKUP_FILENAME" "s3://$AWS_S3_BUCKET_NAME/"
	  echo "Upload finished"
	  _influxdbTimeUploaded="$(date +%s.%N)"
	fi
	if [ ! -z "$AWS_GLACIER_VAULT_NAME" ]; then
	  info "Uploading backup to GLACIER"
	  echo "Will upload to vault \"$AWS_GLACIER_VAULT_NAME\""
	  _influxdbTimeUpload="$(date +%s.%N)"
	  aws $AWS_EXTRA_ARGS glacier upload-archive --account-id - --vault-name "$AWS_GLACIER_VAULT_NAME" --body "$BACKUP_FILENAME"
	  echo "Upload finished"
	  _influxdbTimeUploaded="$(date +%s.%N)"
	fi

	if [ ! -z "$SSH_HOST" ]; then
	  info "Uploading backup by means of SCP"
	  if [ ! -z "$PRE_SSH_COMMAND" ]; then
		echo "Pre-scp command: $PRE_SSH_COMMAND"
		${SSH_REMOTE} $PRE_SSH_COMMAND
	  fi
	  echo "Will upload to $SSH_HOST:$SSH_REMOTE_PATH"
	  _influxdbTimeUpload="$(date +%s.%N)"
	  ${SCP} $BACKUP_FILENAME $SSH_USER@$SSH_HOST:$SSH_REMOTE_PATH
	  echo "Upload finished"
	  _influxdbTimeUploaded="$(date +%s.%N)"
	  if [ ! -z "$POST_SSH_COMMAND" ]; then
		echo "Post-scp command: $POST_SSH_COMMAND"
		${SSH_REMOTE} $POST_SSH_COMMAND
	  fi
	fi

	if [ -d "$BACKUP_ARCHIVE" ]; then
	  info "Archiving backup"
	  mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
	  if (($BACKUP_UID > 0)); then
		chown -v $BACKUP_UID:$BACKUP_GID "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
	  fi
	fi
fi
	
if [ ! -z "$POST_BACKUP_COMMAND" ]; then
  info "Post-backup command"
  echo "$POST_BACKUP_COMMAND"
  eval $POST_BACKUP_COMMAND
fi

if [ -f "$BACKUP_FILENAME" ]; then
  info "Cleaning up"
  rm -vf "$BACKUP_FILENAME"
fi

info "Collecting metrics"
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
  info "Shipping metrics"
  curl \
    --silent \
    --include \
    --request POST \
    --user "$INFLUXDB_CREDENTIALS" \
    "$INFLUXDB_URL/write?db=$INFLUXDB_DB" \
    --data-binary "$_influxdbLine"
fi

info "Backup finished"
echo "Will wait for next scheduled backup"
