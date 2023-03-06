BACKUP_ARCHIVE="${BACKUP_ARCHIVE:-/archive}"
BACKUP_UID=${BACKUP_UID:-0}
BACKUP_GID=${BACKUP_GID:-$BACKUP_UID}

function _backup() {
	if [ ! -d "$BACKUP_ARCHIVE" ]; then echo "$BACKUP_ARCHIVE not found" && exit 1; fi
	
	_info "Archiving backup"
	mv -v "$_backupFullFilename" "$BACKUP_ARCHIVE/$_backupFullFilename"
	if (($BACKUP_UID > 0)); then
		chown -v $BACKUP_UID:$BACKUP_GID "$BACKUP_ARCHIVE/$_backupFullFilename"
	fi
}