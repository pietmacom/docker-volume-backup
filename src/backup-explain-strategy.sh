#!/bin/sh -e

source backup-functions.sh

BACKUP_STRATEGY="${${1}:-0*10d}"
_backupStrategyNormalized="$(_backupStrategyNormalize "${BACKUP_STRATEGY}")"
echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

_backupStrategyExplain "${_backupStrategyNormalized}"
