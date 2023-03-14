#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

_backupName="${1}"
_backupRestorTarget="${2:-${BACKUP_SOURCES}}"

if [[ -z "${_backupName}" ]]; then
	_hasFunctionOrFail "_backupRestoreListFiles not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestoreListFiles"
	_execFunctionOrFail "Please pass file from list to be restored" "_backupRestoreListFiles" "${BACKUP_PREFIX}"
	exit 0
fi

_hasFunctionOrFail "_backupRestore not Implemented by backup target [${BACKUP_TARGET}]" "_backupRestore"

_info "Cleanup existing volumes"
echo "Found volumes..."
ls -1d /backup/*
echo "Size $(du -sh ${_backupRestorTarget})"
sleep 3

if ! yes_or_no "Do you want to delete content from existing volumes?"  
then
	echo "Volumes must be empty before restore"
	exit 1
fi

_info "Cleanup existing volumes"
if [ -S "$DOCKER_SOCK" ]; then
	_containersThis="$(docker ps --filter status=running --filter name=docker-volume-backup --format '{{.ID}}')"	
	_containersRunning="$(_dockerContainerFilter "status=running")"
	_containersToStop=""
	for _running in ${_containersRunning}
	do
		_found=""
		for _this in ${_containersThis}; do
			if [[ "${_running}" == "${_this}" ]]; then _found="${_this}" && break; fi
		done
		if [[ ! -z "${_found}" ]]; then continue; fi
		_containersToStop="${_containersToStop}${_running} "	
	done
	echo "$(docker ps --format "{{.ID}}" | wc -l) containers running on host in total"
	echo "$(echo "${_containersToStop}" | wc -w) containers to be stopped during restore"
	_docker stop "${_containersToStop}"
fi
find ${_backupRestorTarget} -mindepth 2 -maxdepth 2 -print0 | xargs -0 -I {} rm -v -R {};
echo "Size $(du -sh ${_backupRestorTarget})"
sleep 3

_execFunctionOrFail "Restore backup ${_backupName}" "_backupRestore" "${_backupName} ${_backupRestorTarget}"
echo "Size $(du -sh ${_backupRestorTarget})"
sleep 3

_docker start "${_containersToStop}"
