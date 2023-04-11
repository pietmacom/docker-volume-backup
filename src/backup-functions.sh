#!/bin/sh -e

function _info {
  local _bold="\e[1m"
  local _reset="\e[0m"
  echo -e "\n${_bold}[INFO] $@${_reset}"
}

function _error {
  local _bold="\e[1m"
  local _red="\e[31m"
  local _reset="\e[0m"
  echo -e "\n${_bold}${_red}[ERROR]${_reset}${_bold} $@${_reset}" 1>&2
}

function yes_or_no {
    while true; do
        read -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}

function _dockerContainerFilter() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _filters=""
	for filter in "$@"
	do
		if [[ -z "${filter}" ]]; then continue; fi
		_filters="${_filters} --filter "${filter}""
	done
	
	if [[ ! -z "${_filters}" ]]; then
		docker container ls --format "{{.ID}}" --filter "status=running" ${_filters}
	fi
}

function _dockerContainerLabelValue() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _id="$1"
	local _labelName="$2"
	docker container ls --filter id=${_id} --format '{{.Label "${_labelName}"}}' | head -n 1
}

function _dockerContainerName() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _id="$1"	
	docker container ls --filter id=${_id} --format '{{.Names}}'
}

function _docker(){
	local _message="${1}" && shift
	local _action="${1}" && shift
	local _ids="$@"	
	
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	if [[ -z "${_ids}" ]]; then return 0; fi
	
	_info "${_message}"
	docker ${_action} ${_ids}
}

function _dockerExecLabel() {
	local _message="${1}"
	local _label="${2}"
	
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _ids="$(_dockerContainerFilter "label=${_label}" "${BACKUP_CUSTOM_LABEL}")"
	if [[ -z "${_ids}" ]]; then return 0; fi
	
	_info "${_message}"
	for _id in ${_ids}; do
		local _name="$(_dockerContainerName "${_id}")"
		local _cmd="$(_dockerContainerLabelValue "${_id}" "${_label}")"
		
		_info "Exec ${_label} Command For: ${_name}"
		echo docker exec -t ${_id} ${_cmd} # echo the command we're using, for debuggability
		eval docker exec -t ${_id} ${_cmd}
	done
}

function _exec() {
    local _infoMessage="${1}" && shift
	
	if [ -z "$@" ]; then return 0; fi

	_info "${_infoMessage}"
	echo $@
	eval $@
}

function _backupNumber() {
	local _fullEveryDays="$1"
	
	local _year=$(date '+%Y')
	local _dayOfYear=$(( $(date '+%j' | sed 's|^0*||') - 1 )) # Start with 0 so all numbers have the same count.
	local _fullInDays=$(( ${_dayOfYear} % ${_fullEveryDays} ))
	local _backupNumber=$(( (${_dayOfYear} - ${_fullInDays}) / ${_fullEveryDays}))
	echo ${_year}$(printf "%02d" "${_backupNumber}")
}

function _hasFunctionOrFail() {
	local _errorMessage=${1}
	local _functionName=${2}

	if _hasFunction "${_functionName}"; then return 0; fi # Found function

	_error "${_errorMessage}"
	exit 1
}

function _hasFunction() {
    local _functionName=${1}
    if [[ "$(LC_ALL=C type ${_functionName})" == *function ]]; 
		then return 0; 
		else return 1; 
	fi
}

function _execFunction() {
    local _infoMessage=${1} && shift
	local _functionName=${1} && shift
	
    if ! _hasFunction "${_functionName}"; then return 0; fi
	
	_info "${_infoMessage}"
	${_functionName} $@
}

function _execFunctionOrFail() {
    local _infoMessage=${1} && shift
	local _functionName=${1} && shift
	
	_hasFunctionOrFail "${_functionName} not implemented." "${_functionName}";
	
	_info "${_infoMessage}"
	${_functionName} $@
}

function _hasFunctionPrint() {
	local _functionName=${1}

	if _hasFunction "${_functionName}"; 
		then echo "Yes"
		else echo "No"
	fi
}

function _backupTargetDescribe() {
	echo -e "Describe supported actions by backup target [${BACKUP_TARGET}]:"
	echo -e "\tTest connection\t\t\t\t\t$(_hasFunctionPrint "_backupTestConnection")"
	echo -e "\tPre-Upload Command\t\t\t\t$(_hasFunctionPrint "_backupPreUploadCommand")"
	echo -e "\tPost-Upload Command\t\t\t\t$(_hasFunctionPrint "_backupPostUploadCommand")"
	echo -e "\tBackup Archive On-The-Fly\t\t\t$(_hasFunctionPrint "_backupArchiveOnTheFly")"
	echo -e "\tBackup Encrypted Archive On-The-Fly\t\t$(_hasFunctionPrint "_backupArchiveEncryptedOnTheFly")"
	echo -e "\tBackup Incremental\t\t\t\t$(_hasFunctionPrint "_backupIncremental")"
	echo -e "\tBackup Archive\t\t\t\t\t$(_hasFunctionPrint "_backupArchive")"
	echo -e "\tBackup Encrypted Archive\t\t\t$(_hasFunctionPrint "_backupArchiveEncrypted")"
	echo -e "\tRotate Incremental Backup\t\t\t$(_hasFunctionPrint "_backupRemoveIncrementalPrevious")"
	echo -e "\tRotate Backups By Quantity\t\t\t$(_hasFunctionPrint "_backupRemoveArchiveOldest")"
	echo -e "\tRotate Backups By Age\t\t\t\t$(_hasFunctionPrint "_backupRemoveArchiveOlderThanDays")"
	echo -e "\tList Backups For Restore\t\t\t$(_hasFunctionPrint "_backupRestoreListFiles")"
	echo -e "\tRestore Backups\t\t\t\t\t$(_hasFunctionPrint "_backupRestore")"
	echo -e "\tBackup Encrypted Docker Images On-The-Fly\t$(_hasFunctionPrint "_backupImagesEncryptedOnTheFly")"
	echo -e "\tBackup Docker Images On-The-Fly\t\t\t$(_hasFunctionPrint "_backupImagesOnTheFly")"
	echo -e "\tRemove Deleted Docker Images\t\t\t$(_hasFunctionPrint "_backupRemoveImages")"
	echo
}

# Selfrelated. Backups can be copied/moved from previous rule.
#_backupStrategy="1 7 4 12*2"
#_backupStrategy="i1 7 4 12*2"
#_backupStrategy="i1*20d 7 6*2"
#_backupStrategy="0*20d"
#_backupStrategy="1 7*2"
#_backupStrategy="i1 7*4 13*4"
function _backupStrategyNormalize() {
	local _backupStrategy="$1"	
	
	local _backupStrategyNormalized=""	
	for _definition in ${_backupStrategy}; do
		if [[ ! "${_definition}" =~ ${BACKUP_STRATEGY_DEFINITION} ]];
		then
			_error "Strategy definition incorrect [${_definition}].\nAllowed defintions:\n\t1\n\t1*7\n\t1*7d\n\ti1\n\ti1*7\n\ti1*7d"
			exit 1
		fi

		local _iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\1|g")
		local _retention=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\2|g" | sed 's|^\*||')
		local _iterationNumber="$(echo "${_iteration}" | sed 's|^i||')"
		
		if [[ -z "${_retention}" ]];
		then
			_retention="?"
		fi

		_backupStrategyNormalized="$(echo "${_backupStrategyNormalized}" | sed -r "s|\? $|${_iterationNumber} |")${_iteration}*${_retention} "
	done
	_backupStrategyNormalized=$(echo "${_backupStrategyNormalized}" | sed -r "s| $||")

	if [[ "${_backupStrategyNormalized}" == *"\\?" ]]; then
		_error "Strategy is broken: Missing last retention rule [${_backupStrategyNormalized}]."
		exit 1
	fi
	echo "${_backupStrategyNormalized}"
}

function _backupStrategyValidate() {
	local _backupStrategyNormalized="$1"
	
	for _definition in ${_backupStrategyNormalized}; do
		_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\1|g")
		_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\2|g" | sed 's|^\*||')
		
		if [[ "${_iteration}" == "i"* ]]; then 
			_hasFunctionOrFail "_backupIncremental not Implemented by backup target [${BACKUP_TARGET}]" "_backupIncremental";	
		elif [[ "${BACKUP_ONTHEFLY}" == "true" ]]; then
			if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ];
				then _hasFunctionOrFail "_backupArchiveEncryptedOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchiveEncryptedOnTheFly";			
				else _hasFunctionOrFail "_backupArchiveOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchiveOnTheFly";			
			fi
		else
			if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ];
				then _hasFunctionOrFail "_backupArchiveEncrypted not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchiveEncrypted";
				else _hasFunctionOrFail "_backupArchive not Implemented by backup target [${BACKUP_TARGET}]" "_backupArchive";
			fi
		fi

		if [[ "${_iteration}" == "i"* ]]; then # incremental backups maintain only one directory per _retentionDays
			_hasFunctionOrFail "_backupRemoveIncrementalPrevious not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveIncrementalPrevious"		
		elif [[ "${_retention}" == *"d" ]]; then 
			_hasFunctionOrFail "_backupRemoveArchiveOlderThanDays not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOlderThanDays"
		else
			_hasFunctionOrFail "_backupRemoveArchiveOldest not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveArchiveOldest"
		fi
	done

	if [[ "${BACKUP_IMAGES}" == "true" ]]; then
		if [ ! -z "${BACKUP_ENCRYPT_PASSPHRASE}" ];
			then _hasFunctionOrFail "_backupImagesEncryptedOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupImagesEncryptedOnTheFly"
			else _hasFunctionOrFail "_backupImagesOnTheFly not Implemented by backup target [${BACKUP_TARGET}]" "_backupImagesOnTheFly"
		fi
		_hasFunctionOrFail "_backupRemoveImages not Implemented by backup target [${BACKUP_TARGET}]" "_backupRemoveImages"
	fi
}

function _backupStrategyDescribe() {
	local _backupStrategyNormalized="$1"

	echo -e "Describe backup strategy:"
	local _backupStrategyIterationDays=""
	local _backupStrategyBackupCount="0"
	for _definition in ${_backupStrategyNormalized}; do
		local _iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\1|g")
		local _retention=$(echo "${_definition}" | sed -r "s|${BACKUP_STRATEGY_DEFINITION}|\2|g" | sed 's|^\*||')
		local _iterationNumber="$(echo "${_iteration}" | sed 's|^i||')"
		local _retentionNumber="$(echo "${_retention}" | sed 's|d$||')"

		# _backupStrategyIterationDays
		if [[ -z "${_backupStrategyIterationDays}" ]];
			then _backupStrategyIterationDays="${_iterationNumber}"
			else _backupStrategyIterationDays="$(( ${_backupStrategyIterationDays} * ${_iterationNumber} ))"
		fi
		
		# _retentionDays - Always individual per definition
		local _retentionDays="$(( ${_backupStrategyIterationDays} * ${_retentionNumber} ))"
		if [[ "${_retention}" == *"d" ]]; then
			_retentionDays=$(( ${_backupStrategyIterationDays} + ${_retentionNumber} ))
		fi
		
		echo -n -e "\t${_definition}\t=> Backup "
		if [[ "${_iteration}" == "i"* ]]; then
			echo -n "- changes - ";
		fi

		if [[ "${_iterationNumber}" == "0" ]]; 
			then echo -n "every run " # manualy scheduled backups
			else echo -n "every ${_backupStrategyIterationDays}. days "
		fi

		echo -n "and keep "
		if [[ ! "${_retention}" == *"d" ]]; then
			echo -n "last ${_retentionNumber} "
		fi
		if [[ ! "${_retentionDays}" == "0" ]]; then # manualy scheduled backups retain by days or a number of files
			echo -n "backups for ${_retentionDays} days "
		fi
		
		local _backupsCount="0"
		if [[ "${_iteration}" == "i"* ]]; then
			_backupsCount="1"
		elif [[ "${_retention}" == *"d" ]]; then
			if [[ "${_iterationNumber}" == "0" ]]; then continue; fi # Can't predict the number of manualy scheduled backups by days
			
			_backupsCount="$(((${_retentionNumber} / ${_iterationNumber})))"
			if [[ $((${_retentionNumber} % ${_iterationNumber})) -gt 0 ]]; then $((_backupsCount++)); fi
		else
			_backupsCount="${_retentionNumber}"
		fi
		echo "(${_backupsCount} copies)"
		_backupStrategyBackupCount="$((${_backupStrategyBackupCount} + ${_backupsCount}))"
	done
	echo
	
	if [[ "${_backupStrategyBackupCount}" == "0" ]]; then return 0; fi # Can't calculate with 0
	
	echo -e "Example for storage usage over whole period:"
	for _example in "10" "100" "1024" "10240" "20480" "40960" "81920" "102400"
	do
		echo -n -e "\t"
		_backupStrategyStorageUsageDescribe "${_example}"	
	done
	echo
	
	if [[ "${BACKUP_STRATEGY_DESCRIBE_STORAGEUSAGE_PRESENT}" == "true" ]]; then
		echo -e "Present storage usage over whole period:"
		echo -n -e "\t"
		_backupStrategyStorageUsageDescribe "$(du -slm ${BACKUP_SOURCES} | cut -f 1)"	
		echo
	fi
}

function _backupStrategyStorageUsageDescribe() {
		local _volumesSize="$1" # Size in kilobytes
		echo -n -e "${_backupStrategyBackupCount} Backups * "
		if [[ ${_volumesSize} -lt 1024 ]]; then echo -n "${_volumesSize} MB";
		elif [[ ${_volumesSize} -lt 1024000 ]]; then awk "BEGIN { printf \"%.0f GB\", (${_volumesSize}/1024) }";
		else awk "BEGIN { printf \"%.0f TB\", (${_volumesSize}/1024/1024) }";
		fi
		echo -n -e " \t=> "

		local _copiesSize="$((${_volumesSize} * ${_backupStrategyBackupCount}))"
		echo -n "${_copiesSize} MB"
		if [[ ${_copiesSize} -gt 100 ]]; then awk "BEGIN { printf \" / %.2f GB\", (${_copiesSize}/1024) }"; fi
		if [[ ${_copiesSize} -gt 10240 ]]; then awk "BEGIN { printf \" / %.2f TB\", (${_copiesSize}/1024/1024) }"; fi
		echo -n -e "\n"
}

#_cron="5 9 *   *   *"
#_cron="5 9 * * *"
#_cron="5 9 1 2 3"
function _backupCronNormalize() {
	local _backupStrategyNormalized="$1"
	local _cronSchedule="$2"
	
	local _cronNormalized="$(echo "${_cronSchedule}" | tr '\t' ' '| sed "s|[ ][ ]*| |g")"
	if [[ ! "${_cronNormalized}" == *" * * *" ]] \
		&& [[ ! "${_backupStrategyNormalized}" == "0"* ]];
	then
		_cronNormalized="$(echo "${_cronNormalized}" |  cut -d ' ' -f 1,2) * * *"
	fi
	echo "${_cronNormalized}"
}
