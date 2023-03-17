#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

_backupLog="/var/log/docker-volume-backup.log"
if ! set -o pipefail && /root/backup.sh 2>&1 | tee "${_backupLog}"; then
	if [[ -z "${BACKUP_NOTIFICATION_URL}" ]]; then
		exit 0
	fi

	_info "Send log"
	if [[ -z "${DOCKER_SOCK}" ]]; then
		echo "Notifications can be send in Docker environment only."
		exit 1
	fi

	docker run -t --rm containrrr/shoutrrr send --url "${BACKUP_NOTIFICATION_URL}" --message "$(cat "${_backupLog}" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")"		
fi

