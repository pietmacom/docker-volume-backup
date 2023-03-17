#!/bin/sh -e

source backup-functions.sh
source backup-environment.sh

echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

_backupTargetExplain
_backupStrategyExplain "${_backupStrategyNormalized}"
