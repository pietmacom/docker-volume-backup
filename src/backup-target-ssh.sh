# Environment
PRE_SSH_COMMAND="${PRE_SSH_COMMAND:-}"
POST_SSH_COMMAND="${POST_SSH_COMMAND:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-}"
SSH_REMOTE_PATH="${SSH_REMOTE_PATH:-.}"

# Internal
SSH_CONFIG="-o StrictHostKeyChecking=no -i /root/.ssh/id_rsa"
SSH="ssh $SSH_CONFIG -p $SSH_PORT"
SSH_REMOTE="${SSH} ${SSH_USER}@${SSH_HOST}"

function _backupTestConnection() {
	if [[ -z "$SSH_HOST" ]];
		then echo "SSH_HOST not set" && exit 1;fi
		
	echo -n "Test Connection... " && \
		if ! ${SSH_REMOTE} "echo 'Successed'; sleep 1" 2>/dev/null ; then echo "Failed" && _docker start ${_containersToStop}  && exit 1; fi		
}

function _backupPreUploadCommand() {
	if [ ! -z "$PRE_SSH_COMMAND" ];
	then
		echo "Pre-SSH command: $PRE_SSH_COMMAND"
		${SSH_REMOTE} ${PRE_SSH_COMMAND}
	fi
	echo "Will upload to $SSH_USER@$SSH_HOST:$SSH_PORT$SSH_REMOTE_PATH"
}

function _backupPostUploadCommand() {
	if [ ! -z "$POST_SSH_COMMAND" ];
	then
		echo "Post-SSH command: $POST_SSH_COMMAND"
		${SSH_REMOTE} ${POST_SSH_COMMAND}
	fi
}

function _backupArchiveOnTheFly() {
	local _sourcePath="${1}"
	local _fileName="${2}"
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}"
	
	if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	tar -cv -C ${_sourcePath} . | ${BACKUP_COMPRESS_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
	_influxdbBackupSize="$($SSH_REMOTE "du -bs ${SSH_REMOTE_PATH}/${_remoteFileName} | cut -f1")"
}

function _backupArchiveEncryptedOnTheFly() {
	local _sourcePath="${1}"
	local _fileName="${2}"
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
	
	if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	tar -cv -C ${_sourcePath} . | ${BACKUP_COMPRESS_PIPE} | ${BACKUP_ENCRYPT_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
	_influxdbBackupSize="$($SSH_REMOTE "du -bs ${SSH_REMOTE_PATH}/${_remoteFileName} | cut -f1")"
}

function _backupIncremental() {
	local _sourcePath="${1}"
	local _fileName="${2}"
	
	echo "Maintain remote increment backup"
	${SSH_REMOTE} "mkdir -p ${SSH_REMOTE_PATH}/${_fileName}"		
	for i in {1..3};
	do
		rsync -aviP -e "${SSH}" --stats --delete ${_sourcePath}/ ${SSH_USER}@${SSH_HOST}:${SSH_REMOTE_PATH}/${_fileName}
		if [ $? -eq 0 ]; then break; fi
		if [ $i -ge 3 ]; then echo "Backup failed after ${i} times" && exit 1; fi
		_info "Repeat ${i} time due to an error"
		sleep 30
	done
	${SSH_REMOTE} "touch ${SSH_REMOTE_PATH}/${_fileName}" # make last action visible
	_influxdbBackupSize="$($SSH_REMOTE "du -bs ${SSH_REMOTE_PATH}/${_backupIncrementalDirectoryName} | cut -f1")"
}

function _backupArchive() {
	local _sourceFile="${1}"
	local _fileName="${2}"	
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}"
	
	if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	cat ${_sourceFile} | ${BACKUP_COMPRESS_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
}

function _backupArchiveEncrypted() {
	local _sourceFile="${1}"
	local _fileName="${2}"	
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
	
	if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi
	cat ${_sourceFile} | ${BACKUP_COMPRESS_PIPE} | ${BACKUP_ENCRYPT_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
}

function _backupRemoveIncrementalOldest() {
	local _filePrefix="${1}"
	
	${SSH_REMOTE} "ls -1d ${SSH_REMOTE_PATH}/${_filePrefix}*/ | sort -r | tail -n +2 | xargs -I {} rm -v -R {}"
}

function _backupRemoveArchiveOldest() {
	local _filePrefix="${1}"
	local _keepCount="${2}"
	
	${SSH_REMOTE} "ls -1d ${SSH_REMOTE_PATH}/${_filePrefix}*.tar${BACKUP_COMPRESS_EXTENSION}* | sort -r | tail -n +$(( ${_keepCount} + 1)) | xargs -I {} rm -v -R {}"
}

function _backupRemoveArchiveOlderThanDays() {
	local _filePrefix="${1}"
	local _keepDays="${2}"
	
	${SSH_REMOTE} "find ${SSH_REMOTE_PATH} -maxdepth 1 -name \"${_filePrefix}*.tar${BACKUP_COMPRESS_EXTENSION}*\" -type f -mtime +$(( ${_keepDays} - 1 )) -print0 | xargs -0 -I {} rm -v -R {}"
}

function _backupRestoreListFiles() {
	local _filePrefix="${1}"
	
	${SSH_REMOTE} "cd ${SSH_REMOTE_PATH} && ls -1ldh ${_filePrefix}* | sort -k9,9"
}

function _backupRestore() {
	local _fileName="${1}"
	local _targetPath="${2}"
	
	if ${SSH_REMOTE} -q "[[ ! -e ${SSH_REMOTE_PATH}/${_fileName} ]]"; then echo "File does not exist [${_fileName}]" && exit 1; fi
	
	if [[ "${_fileName}" == *".tar${BACKUP_COMPRESS_EXTENSION}" ]]; then
		${SSH_REMOTE} "cat ${SSH_REMOTE_PATH}/${_fileName}" | ${BACKUP_DECOMPRESS_PIPE} | tar -xvf - -C ${_targetPath}
		
	elif [[ "${_fileName}" == *".tar${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}" ]]; then
		${SSH_REMOTE} "cat ${SSH_REMOTE_PATH}/${_fileName}" | ${BACKUP_DECRYPT_PIPE} | ${BACKUP_DECOMPRESS_PIPE} | tar -xvf - -C ${_targetPath}
		
	else
		${SSH_REMOTE} "tar -cf - -C ${SSH_REMOTE_PATH}/${_fileName} ." | tar -xvf - -C ${_targetPath}
		
	fi
}

function _backupImagesEncryptedOnTheFly() {
	local _filePrefix="${1}"
	shift	
	local _ids="$@"
	
	for _id in ${_ids}
	do	
		_remoteFileName="${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
		if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then 
			echo "Skip: Image [${_id}] already backed up [${_remoteFileName}]"
			continue
		fi
		
		echo "Backing up image [${_id}] [${_remoteFileName}]"
		docker save "${_id}" | ${BACKUP_COMPRESS_PIPE} |  ${BACKUP_ENCRYPT_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
	done
}

function _backupImagesOnTheFly() {
	local _filePrefix="${1}"
	shift	
	local _ids="$@"
	
	for _id in ${_ids}
	do	
		_remoteFileName="${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}"
		if ${SSH_REMOTE} -q "[[ -e ${SSH_REMOTE_PATH}/${_remoteFileName} ]]"; then 
			echo "Skip: Image [${_id}] already backed up [${_remoteFileName}]"
			continue
		fi
		
		echo "Backing up image [${_id}] [${_remoteFileName}]"
		docker save "${_id}" | ${BACKUP_COMPRESS_PIPE} | ${SSH_REMOTE} "cat > ${SSH_REMOTE_PATH}/${_remoteFileName}"
	done
}

function _backupRemoveImages() {
	local _filePrefix="${1}"
	shift	
	local _keepIds="$@"
	
	# exit when empty?
	
	_keepFiles=""
	for _id in ${_ids}
	do	
		_remoteFileName="${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}*"
		_keepFiles="${_keepFiles}-e \"${_remoteFileName}\" "
	done
	
	echo "deleting!"
	${SSH_REMOTE} "find ${SSH_REMOTE_PATH} -maxdepth 1 -name \"${_filePrefix}*\" -type f -exec basename {} \; | grep -v ${_keepFiles}"
}
