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

_docker exec -it --rm containrrr/shoutrrr --url "${BACKUP_NOTIFICATION_URL}" --message "$(cat "${_backupLog}")"

