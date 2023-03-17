#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

_backupLog="${1}"
if [[ -z "${BACKUP_NOTIFICATION_URL}" ]]; then
	exit 0
fi

if [[ -z "${DOCKER_SOCK}" ]]; then
	echo "Notifications are send by the containrrr/shoutrrr container in Docker environment only."
	exit 1
fi

_info "Send notification"
if docker run -t --rm containrrr/shoutrrr send --url "${BACKUP_NOTIFICATION_URL}" --message "$(cat "${_backupLog}" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2};?)?)?[mGK]//g")";
	then echo "Notification has been send."
	else echo "Notification couldn't be send."
fi

