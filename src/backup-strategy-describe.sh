#!/bin/sh -e

source backup-environment.sh

_backupTargetDescribe

echo -n -e "Normalized backup strategy definition:\n\t${_backupStrategyNormalized}"\
    && if [[ ! "${_backupStrategyNormalized}" == "${BACKUP_STRATEGY}" ]]; then echo -n -e " (given: ${BACKUP_STRATEGY})\n"; else echo -n -e "\n"; fi
echo

_backupStrategyDescribe "${_backupStrategyNormalized}"
