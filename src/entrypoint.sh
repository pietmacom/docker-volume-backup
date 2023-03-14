#!/bin/sh -e

env | sed 's/=/="/;s/$/"/' > backup.env # Write cronjob env to file, fill in sensible defaults, and read them back in

source backup-environment.sh
source backup-functions.sh

echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

echo -n -e "Normalized Cron definition:\n\t${_cronScheduleNormalized}" \
    && if [[ ! "${_cronScheduleNormalized}" == "${BACKUP_CRON_SCHEDULE}" ]]; then echo -n -e " (given: ${BACKUP_CRON_SCHEDULE})\n"; else echo -n -e "\n"; fi
echo

_backupStrategyExplain "${_backupStrategyNormalized}"

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup"
echo "${_cronScheduleNormalized} /root/backup.sh > /proc/1/fd/1 2>&1" >> /var/spool/cron/crontabs/root

# Let cron take the wheel
echo "Starting cron in foreground with expression: ${_cronScheduleNormalized}"
crond -f
