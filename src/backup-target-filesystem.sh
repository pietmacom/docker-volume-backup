BACKUP_FILESYSTEM_PATH="${BACKUP_FILESYSTEM_PATH:-/archive}"
BACKUP_FILESYSTEM_UID=${BACKUP_UID:-0}
BACKUP_FILESYSTEM_GID=${BACKUP_GID:-$BACKUP_UID}

function _backupApiVersion() {
	echo "1.0.0"
}

function _backupArchiveOnTheFly() {
	local _sourcePath="${1}"
	local _fileName="${2}"
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}"
	
	if [[ -e "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}" ]]; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	tar -cv -C ${_sourcePath} . | ${BACKUP_COMPRESS_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	_metaBackupSize="$(du -bs ${BACKUP_FILESYSTEM_PATH}/${_remoteFileName} | cut -f1)"
}

function _backupArchiveEncryptedOnTheFly() {
	local _sourcePath="${1}"
	local _fileName="${2}"
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
	
	if [[ -e "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}" ]]; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	tar -cv -C ${_sourcePath} . | ${BACKUP_COMPRESS_PIPE} | ${BACKUP_ENCRYPT_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	_metaBackupSize="$(du -bs ${BACKUP_FILESYSTEM_PATH}/${_remoteFileName} | cut -f1)"
}

function _backupIncremental() {
	local _sourcePath="${1}"
	local _fileName="${2}"
		
	echo "Maintain remote increment backup"
	mkdir -p ${BACKUP_FILESYSTEM_PATH}/${_fileName}
	for i in {1..3};
	do
		rsync -aviP --stats --delete ${_sourcePath}/ ${BACKUP_FILESYSTEM_PATH}/${_fileName}
		if [ $? -eq 0 ]; then break; fi
		if [ $i -ge 3 ]; then echo "Backup failed after ${i} times" && exit 1; fi
		_info "Repeat ${i} time due to an error"
		sleep 30
	done
	touch ${BACKUP_FILESYSTEM_PATH}/${_fileName} # make last action visible
	_metaBackupSize="$(du -bs ${BACKUP_FILESYSTEM_PATH}/${_fileName} | cut -f1)"
}

function _backupArchive() {
	local _sourceFile="${1}"
	local _fileName="${2}"	
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}"
	
	if [[ -e "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}" ]]; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi	
	cat ${_sourceFile} | ${BACKUP_COMPRESS_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	_metaBackupSize="$(du -bs ${BACKUP_FILESYSTEM_PATH}/${_remoteFileName} | cut -f1)"
}

function _backupArchiveEncrypted() {
	local _sourceFile="${1}"
	local _fileName="${2}"	
	local _remoteFileName="${_fileName}${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
	
	if [[ -e "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}" ]]; then echo "Skip: File already backed up [${_remoteFileName}]" && return 0; fi
	cat ${_sourceFile} | ${BACKUP_COMPRESS_PIPE} | ${BACKUP_ENCRYPT_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	_metaBackupSize="$(du -bs ${BACKUP_FILESYSTEM_PATH}/${_remoteFileName} | cut -f1)"
}

function _backupRemoveIncrementalPrevious() {
	local _filePrefix="${1}"
	
	ls -1d ${BACKUP_FILESYSTEM_PATH}/${_filePrefix}*/ | sort -r | tail -n +2 | xargs -I {} rm -v -R {}
}

function _backupRemoveArchiveOldest() {
	local _filePrefix="${1}"
	local _keepCount="${2}"
	
	ls -1d ${BACKUP_FILESYSTEM_PATH}/${_filePrefix}*.tar${BACKUP_COMPRESS_EXTENSION}* | sort -r | tail -n +$(( ${_keepCount} + 1)) | xargs -I {} rm -v -R {}
}

function _backupRemoveArchiveOlderThanDays() {
	local _filePrefix="${1}"
	local _keepDays="${2}"
	
	find ${BACKUP_FILESYSTEM_PATH} -maxdepth 1 -name \"${_filePrefix}*.tar${BACKUP_COMPRESS_EXTENSION}*\" -type f -mtime +$(( ${_keepDays} - 1 )) -print0 | xargs -0 -I {} rm -v -R {}
}

function _backupRestoreListFiles() {
	local _filePrefix="${1}"
	
	cd ${BACKUP_FILESYSTEM_PATH} && ls -1ldh ${_filePrefix}* | sort -k9,9
}

function _backupRestore() {
	local _fileName="${1}"
	local _targetPath="${2}"
	
	if [[ ! -e "${BACKUP_FILESYSTEM_PATH}/${_fileName}" ]]; then echo "File does not exist [${_fileName}]" && exit 1; fi
	
	if [[ "${_fileName}" == *".tar${BACKUP_COMPRESS_EXTENSION}" ]]; then
		cat ${BACKUP_FILESYSTEM_PATH}/${_fileName} | ${BACKUP_DECOMPRESS_PIPE} | tar -xvf - -C ${_targetPath}
		
	elif [[ "${_fileName}" == *".tar${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}" ]]; then
		cat ${BACKUP_FILESYSTEM_PATH}/${_fileName} | ${BACKUP_DECRYPT_PIPE} | ${BACKUP_DECOMPRESS_PIPE} | tar -xvf - -C ${_targetPath}
		
	else
		tar -cf - -C ${BACKUP_FILESYSTEM_PATH}/${_fileName} . | tar -xvf - -C ${_targetPath}
		
	fi
}

function _backupImagesEncryptedOnTheFly() {
	local _filePrefix="${1}" && shift	
	local _ids="$@"
	
	local _remoteBackupImages="$(find ${BACKUP_FILESYSTEM_PATH} -maxdepth 1 -name \"${_filePrefix}*\" -type f)" # Speedup skipping
	for _id in ${_ids}; do	
		_remoteFileName="${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}${BACKUP_ENCRYPT_EXTENSION}"
		if echo "${_remoteBackupImages}" | grep -q "${_remoteFileName}" ; then echo "Skip: File already backed up [${_remoteFileName}]" && continue; fi  # Skip when found
		
		echo "Backing up image [${_id}] [${_remoteFileName}]"
		docker save "${_id}" | ${BACKUP_COMPRESS_PIPE} |  ${BACKUP_ENCRYPT_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	done
}

function _backupImagesOnTheFly() {
	local _filePrefix="${1}" && shift
	local _ids="$@"
	
	local _remoteBackupImages="$(find ${BACKUP_FILESYSTEM_PATH} -maxdepth 1 -name \"${_filePrefix}*\" -type f)" # Speedup skipping
	for _id in ${_ids}; do	
		_remoteFileName="${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}"
		if echo "${_remoteBackupImages}" | grep -q "${_remoteFileName}" ; then echo "Skip: File already backed up [${_remoteFileName}]" && continue; fi # Skip when found
		
		echo "Backing up image [${_id}] [${_remoteFileName}]"
		docker save "${_id}" | ${BACKUP_COMPRESS_PIPE} > "${BACKUP_FILESYSTEM_PATH}/${_remoteFileName}"
	done
}

function _backupRemoveImages() {
	local _filePrefix="${1}" && shift	
	local _keepIds="$@"
	
	local _dontRemove=""
	for _id in ${_keepIds}; do
		_dontRemove="${_dontRemove} -not -name \"${_filePrefix}-${_id}.tar${BACKUP_COMPRESS_EXTENSION}*\" ";
	done
	find ${BACKUP_FILESYSTEM_PATH} -maxdepth 1 -name \"${_filePrefix}*\" ${_dontRemove} -type f -print0 | xargs -0 -I {} rm -v -R {}
}
