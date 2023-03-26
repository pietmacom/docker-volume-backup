#!/bin/bash -ex

# Cronjobs don't inherit their env, so load from file
source env.sh

function info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $1$reset\n"
}

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
  CUSTOM_LABEL="--filter label=$BACKUP_CUSTOM_LABEL"
fi

if [ -S "$DOCKER_SOCK" ]; then
  TEMPFILE="$(mktemp)"
  docker ps --format "{{.ID}}" --filter "label=docker-volume-backup.stop-during-backup=true" $CUSTOM_LABEL > "$TEMPFILE"
  CONTAINERS_TO_STOP="$(cat $TEMPFILE | tr '\n' ' ')"
  CONTAINERS_TO_STOP_TOTAL="$(cat $TEMPFILE | wc -l)"
  CONTAINERS_TOTAL="$(docker ps --format "{{.ID}}" | wc -l)"
  rm "$TEMPFILE"
  echo "$CONTAINERS_TOTAL containers running on host in total"
  echo "$CONTAINERS_TO_STOP_TOTAL containers marked to be stopped during backup"
else
  CONTAINERS_TO_STOP_TOTAL="0"
  CONTAINERS_TOTAL="0"
  echo "Cannot access \"$DOCKER_SOCK\", won't look for containers to stop"
fi

if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
  info "Stopping containers"
  docker stop $CONTAINERS_TO_STOP
fi

if [ -S "$DOCKER_SOCK" ]; then
  for id in $(docker ps --filter label=docker-volume-backup.exec-pre-backup $CUSTOM_LABEL --format '{{.ID}}'); do
    name="$(docker ps --filter id=$id --format '{{.Names}}')"
    cmd="$(docker ps --filter id=$id --format '{{.Label "docker-volume-backup.exec-pre-backup"}}')"
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
BACKUP_FILENAME="$(date +"${BACKUP_FILENAME:-backup-%Y-%m-%dT%H-%M-%S.tar.gz}")"

if [[ "${BACKUP_ONTHEFLY,,}" = "false" ]];

	# With Temporary File
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

	if [ -S "$DOCKER_SOCK" ]; then
	  for id in $(docker ps --filter label=docker-volume-backup.exec-post-backup $CUSTOM_LABEL --format '{{.ID}}'); do
		name="$(docker ps --filter id=$id --format '{{.Names}}')"
		cmd="$(docker ps --filter id=$id --format '{{.Label "docker-volume-backup.exec-post-backup"}}')"
		info "Post-exec command for: $name"
		echo docker exec $id $cmd # echo the command we're using, for debuggability
		eval docker exec $id $cmd
	  done
	fi

	if [ "$CONTAINERS_TO_STOP_TOTAL" != "0" ]; then
	  info "Starting containers back up"
	  docker start $CONTAINERS_TO_STOP
	fi

	info "Waiting before processing"
	echo "Sleeping $BACKUP_WAIT_SECONDS seconds..."
	sleep "$BACKUP_WAIT_SECONDS"

	_influxdbTimeUpload="0"
	_influxdbTimeUploaded="0"
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
	  SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
	  if [ ! -z "$PRE_SSH_COMMAND" ]; then
		echo "Pre-scp command: $PRE_SSH_COMMAND"
		ssh $SSH_CONFIG $SSH_USER@$SSH_HOST $PRE_SSH_COMMAND
	  fi
	  echo "Will upload to $SSH_HOST:$SSH_REMOTE_PATH"
	  _influxdbTimeUpload="$(date +%s.%N)"
	  scp $SSH_CONFIG $BACKUP_FILENAME $SSH_USER@$SSH_HOST:$SSH_REMOTE_PATH
	  echo "Upload finished"
	  _influxdbTimeUploaded="$(date +%s.%N)"
	  if [ ! -z "$POST_SSH_COMMAND" ]; then
		echo "Post-scp command: $POST_SSH_COMMAND"
		ssh $SSH_CONFIG $SSH_USER@$SSH_HOST $POST_SSH_COMMAND
	  fi
	fi

	if [ -d "$BACKUP_ARCHIVE" ]; then
	  info "Archiving backup"
	  mv -v "$BACKUP_FILENAME" "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
	  if (($BACKUP_UID > 0)); then
		chown -v $BACKUP_UID:$BACKUP_GID "$BACKUP_ARCHIVE/$BACKUP_FILENAME"
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
	
} else {

	# On-The-Fly
	if [ ! -z "$SSH_HOST" ]; then
		info "Uploading backup by means of SCP"
		SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
		
		_influxdbTimeBackup="$(date +%s.%N)"
		_influxdbTimeUpload="$(date +%s.%N)"
		echo "Will upload to $SSH_HOST:$SSH_REMOTE_PATH"
		tar -zcv $BACKUP_SOURCES | ssh [remote server IP address] "cat > $SSH_REMOTE_PATH/$BACKUP_FILENAME"
		echo "Upload finished"
		_influxdbBackupSize="$(du -bs $BACKUP_SOURCES)"
		_influxdbTimeBackedUp="$(date +%s.%N)"
		_influxdbTimeUploaded="$(date +%s.%N)"
	fi
}


info "Collecting metrics"
_influxdbTimeFinish="$(date +%s.%N)"
_influxdbLine="$_influxdbMeasurement\
,host=$BACKUP_HOSTNAME\
\
 size_compressed_bytes=$_influxdbBackupSize\
,containers_total=$CONTAINERS_TOTAL\
,containers_stopped=$CONTAINERS_TO_STOP_TOTAL\
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
