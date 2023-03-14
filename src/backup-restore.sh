#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

_backupName="${1}"
_backupRestorTarget="${2:-${BACKUP_SOURCES}}"

if [[ -z "${_backupName}" ]]; then
	_hasFunctionOrFail "_backupRestoreListFiles not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestoreListFiles"
	_execFunctionOrFail "Please pass file from list" "_backupRestoreListFiles" "${BACKUP_PREFIX}"
	exit 0
fi

_hasFunctionOrFail "_backupRestore not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestore"

if [ -S "$DOCKER_SOCK" ]; then
	_containersThis="$(docker ps --filter status=running --filter name=docker-volume-backup --format '{{.ID}}')"
	echo ${_containersThis};
	exit 1
	_containersToStop="$(_dockerContainerFilter "status=running")"
	_containersToStopCount="$(echo ${_containersToStop} | wc -l)"
	_containersCount="$(docker ps --format "{{.ID}}" | wc -l)"

	echo "$_containersCount containers running on host in total"
	echo "$_containersToStopCount containers to be stopped during restore"
	_docker stop ${_containersToStop}
fi

_info "Cleanup existing volumes"

echo "Found volumes..."
ls -1d /backup/*

if ! yes_or_no "Do you want to delete content from existing volumes?" && find ${_backupRestorTarget} -mindepth 2 -maxdepth 2 -print0 | xargs -0 -I {} rm -v -R {};
then
	echo "Volumes must be empty before restore."
	_docker start ${_containersToStop}
	exit 1
fi

_execFunctionOrFail "Restore backup ${_backupName}" "_backupRestore" "${_backupName} ${_backupRestorTarget}"
_docker start ${_containersToStop}





