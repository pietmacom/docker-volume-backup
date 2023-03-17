#!/bin/sh -e

export DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}" # Enable docker environment
env | sed 's/=/="/;s/$/"/' > backup.env # Write cronjob env to file, fill in sensible defaults, and read them back in


source backup-functions.sh
source backup-environment.sh

_info "Validate settings"
if [[ ! -z "${BACKUP_NOTIFICATION_URL}" ]] \
	&& ! docker info 2>&1 > /dev/null; then
	echo "Can't connect to docker [${DOCKER_SOCK}]"
	echo "Notifications are send by the containrrr/shoutrrr container and depend on Docker."
	exit 1
fi


_info "Validate backup strategy"
_backupTargetExplain

echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

echo -n -e "Normalized Cron definition:\n\t${_cronScheduleNormalized}" \
    && if [[ ! "${_cronScheduleNormalized}" == "${BACKUP_CRON_SCHEDULE}" ]]; then echo -n -e " (given: ${BACKUP_CRON_SCHEDULE})\n"; else echo -n -e "\n"; fi
echo

_backupStrategyExplain "${_backupStrategyNormalized}"
_backupStrategyValidate "${_backupStrategyNormalized}"


_info "Schedule backups"
echo "Installing cron.d entry: docker-volume-backup"
echo "${_cronScheduleNormalized} /root/backup-cronjob.sh > /proc/1/fd/1 2>&1" > /var/spool/cron/crontabs/root # Add our cron entry, and direct stdout & stderr to Docker commands stdout

echo "Starting cron in foreground with expression: ${_cronScheduleNormalized}" # Let cron take the wheel
crond -f
find 