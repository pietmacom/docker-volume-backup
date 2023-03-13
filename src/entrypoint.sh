#!/bin/sh

# Exit immediately on error
set -e

# Write cronjob env to file, fill in sensible defaults, and read them back in
export BACKUP_STRATEGY="${BACKUP_STRATEGY:-1*10d}"
export BACKUP_CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 9 * * *}"
env | sed 's/=/="/;s/$/"/' > backup.env

source backup-functions.sh
_backupStrategyNormalized="$(_backupStrategyNormalize "${BACKUP_STRATEGY}")"
_cronScheduleNormalized="$(_backupCronNormalize "${BACKUP_STRATEGY}" "${BACKUP_CRON_SCHEDULE}")"

echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

echo -n -e "Normalized Cron definition:\n\t${_cronScheduleNormalized}" \
    && if [[ ! "${_cronScheduleNormalized}" == "${BACKUP_CRON_SCHEDULE}" ]]; then echo -n -e " (given: ${BACKUP_CRON_SCHEDULE})\n"; else echo -n -e "\n"; fi
echo

_backupStrategyExplain "${BACKUP_STRATEGY}"

# Add our cron entry, and direct stdout & stderr to Docker commands stdout
echo "Installing cron.d entry: docker-volume-backup"
echo "${_cronScheduleNormalized} /root/backup.sh > /proc/1/fd/1 2>&1" >> /var/spool/cron/crontabs/root

# Let cron take the wheel
echo "Starting cron in foreground with expression: ${_cronScheduleNormalized}"
crond -f
