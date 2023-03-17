#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

_backupLog="${1:-/var/log/docker-volume-backup.log}"
if [[ -z "${BACKUP_NOTIFICATION_URL}" ]]; then
	exit 0
fi

_info "Send log"
if [[ -z "${DOCKER_SOCK}" ]]; then
	echo "Notifications can be send in Docker environment only."
	exit 1
fi

if [[ ! -e "${_backupLog}" ]]; then
	echo "Log not found [${_backupLog}]"
	exit 1
fi

if docker run -t --rm containrrr/shoutrrr send --url "${BACKUP_NOTIFICATION_URL}" --message "$(cat "${_backupLog}" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")";
	then echo "Successfull"
	else echo "Failed"
fi

