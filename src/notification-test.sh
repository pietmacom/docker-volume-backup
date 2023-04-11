#!/bin/sh -e

source backup-environment.sh

if [[ -z "${BACKUP_NOTIFICATION_URL}" ]]; then
	exit 0
fi

_info "Send test notification"
if [[ -z "${DOCKER_SOCK}" ]]; then
	echo "Notifications can be send in Docker environment only."
	exit 1
fi

${BACKUP_NOTIFICATION_PREPARE_COMMAND}
docker run -t --rm containrrr/shoutrrr send --url "${BACKUP_NOTIFICATION_URL}" --message "Test Message arrived! - $(date)"		