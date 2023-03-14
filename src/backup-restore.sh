#!/bin/sh -e

source backup-environment.sh
source backup-functions.sh

_backupName="${1}"

if [[ -z "${_backupName}" ]]; then
	_hasFunctionOrFail "_backupRestoreListFiles not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestoreListFiles"
	_execFunctionOrFail "Please choose a backup from List" "_backupRestoreListFiles" "${BACKUP_PREFIX}"
else 
	_hasFunctionOrFail "_backupRestore not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestore"
	_execFunctionOrFail "Restore backup ${_backupName}" "_backupRestoreListFiles" "${_backupName} ${BACKUP_SOURCES}1"
fi





