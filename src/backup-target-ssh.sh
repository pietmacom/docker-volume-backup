# Environment
PRE_SSH_COMMAND="${PRE_SSH_COMMAND:-}"
POST_SSH_COMMAND="${POST_SSH_COMMAND:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-}"
SSH_REMOTE_PATH="${SSH_REMOTE_PATH:-.}"

# Internal
SSH_CONFIG="-o StrictHostKeyChecking=no -i /ssh/id_rsa"
SSH="ssh $SSH_CONFIG -p $SSH_PORT"
SSH_REMOTE="${SSH} ${SSH_USER}@${SSH_HOST}"

function _rotateBackups() {
	keepcount="3"
	
	_info "Delete last increment backups..."
    echo "Delete last increment backups."
    ${SSH_REMOTE} "ls -1d ${SSH_REMOTE_PATH}/*/ | sort -r | tail -n +2 | xargs -I {} rm -R {}"
	
	_info "Delete old (keep ${keepcount}) backups..."
	echo "Delete old (keep ${keepcount}) backups."
	${SSH_REMOTE} "ls -1 ${SSH_REMOTE_PATH}/*.tar.gz | sort -r | tail -n +$(expr $keepcount + 1) | xargs -I {} rm -R {}"
}

function _backupOnTheFly() {
	_backup
}

function _backup() {
	if [[ -z "$SSH_HOST" ]]; then echo "SSH_HOST not set" && exit 1; fi
	
	_info "Uploading backup by means of SSH"
	echo "Will upload to $SSH_USER@$SSH_HOST:$SSH_PORT$SSH_REMOTE_PATH"
	echo -n "Test Connection... " && \
		 if ! ${SSH_REMOTE} "echo 'Successed'; sleep 1" 2>/dev/null ; then echo "Failed" && _docker start ${_containersToStop}  && exit 1; fi

	if [ ! -z "$PRE_SSH_COMMAND" ];
	then
		echo "Pre-SSH command: $PRE_SSH_COMMAND"
		${SSH_REMOTE} $PRE_SSH_COMMAND
	fi
	
	if [[ "${BACKUP_INCREMENTAL}" == "true" ]];
	then
		echo "Maintain remote increment backup"
		${SSH_REMOTE} "mkdir -p ${SSH_REMOTE_PATH}/${_backupIncrementalDirectoryName}"		
		for i in {1..3};
		do
			rsync -aviP -e "${SSH}" --stats --delete ${BACKUP_SOURCES}/ $SSH_USER@$SSH_HOST:${SSH_REMOTE_PATH}/${_backupIncrementalDirectoryName}
			if [ $? -eq 0 ]; then break; fi
			if [ $i -ge 3 ]; then echo "Backup failed after ${i} times" && exit 1; fi
			_info "Repeat ${i} time due to an error"
			sleep 30
		done
		if [[ "${BACKUP_INCREMENTAL_MAINTAIN_FULL}" == "true" ]] \
		   && ! $SSH_REMOTE -q "[[ -e ${SSH_REMOTE_PATH}/${_backupFullFilename} ]]";
		then
			echo "Create full backup vom increment backup"
			tar -zcv $BACKUP_SOURCES | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_backupFullFilename}";
		fi
		_influxdbBackupSize="$($SSH_REMOTE "du -bs ${SSH_REMOTE_PATH}/${_backupIncrementalDirectoryName} | cut -f1")"
		
	elif [[ "${BACKUP_ONTHEFLY}" == "true" ]];
	then
		tar -zcv $BACKUP_SOURCES | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_backupFullFilename}"
		_influxdbBackupSize="$($SSH_REMOTE "du -bs ${SSH_REMOTE_PATH}/${_backupFullFilename} | cut -f1")"	
	
	else
		scp ${SSH_CONFIG} -P ${SSH_PORT} $BACKUP_FILENAME $SSH_USER@$SSH_HOST:$SSH_REMOTE_PATH
	
	fi
	
	if [ ! -z "$POST_SSH_COMMAND" ];
	then
		echo "Post-SSH command: $POST_SSH_COMMAND"
		${SSH_REMOTE} $POST_SSH_COMMAND
	fi
}
