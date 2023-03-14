#!/bin/sh -e

BACKUP_DEFINITION="^(i*[0-9]+)(\*[0-9]+d*)?$"

function _info {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[INFO] $@$reset\n"
}

function _error {
  bold="\033[1m"
  reset="\033[0m"
  echo -e "\n$bold[ERROR] $@$reset\n" 1>&2
}

function _dockerContainerFilter() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _filters=""
	for label in "$@"
	do
		if [[ -z "${label}" ]]; then continue; fi
		_filters="${_filters} --filter "${label}""
	done
	
	if [[ ! -z "${_filters}" ]];
	then
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
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _action="$1"
	local _ids="$2"	
	if [[  -z "${_ids}"  ]]; then return 0; fi

	_info "${_action} containers"
	docker ${_action} "${_ids}"
}

function _dockerExecLabel() {
	if [ ! -S "$DOCKER_SOCK" ]; then return 0; fi
	
	local _label="$1"
	for id in $(_dockerContainerFilter "label=${_label}" "${BACKUP_CUSTOM_LABEL}"); do
		name="$(_dockerContainerName "$id")"
		cmd="$(_dockerContainerLabelValue "${id}" "${_label}")"
		_info "Exec ${_label} command for: $name"
		echo docker exec -t $id $cmd # echo the command we're using, for debuggability
		eval docker exec -t $id $cmd
	done
}

function _exec() {
    local _infoMessage="${1}"
	local _command="${2}"
	
	if [ ! -z "${_command}" ];
	then
	  _info "${_infoMessage}"
	  echo "${_command}"
	  eval ${_command}
	fi
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


	if ! _hasFunction "${_functionName}";
	then 
		_error "${_errorMessage}"
		exit 1
	fi
}

function _hasFunction() {
    local _functionName=${1}
    if [[ "$(LC_ALL=C type ${_functionName})" == *function ]]; 
		then return 0; 
		else return 1; 
	fi
}

function _execFunction() {
    local _infoMessage=${1}
	local _functionName=${2}
	shift 2
	
    if _hasFunction "${_functionName}";
    then
		_info "${_infoMessage}"
		${_functionName} $@
    fi
}

function _execFunctionOrFail() {
    local _infoMessage=${1}
	local _functionName=${2}
	shift 2
	
    if _hasFunction "${_functionName}";
    then
		_info "${_infoMessage}"
		${_functionName} $@
	else
		_error "${_functionName} not implemented."
		exit 1
    fi
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
	for _definition in ${_backupStrategy}
	do
		if [[ ! "${_definition}" =~ ${BACKUP_DEFINITION} ]];
		then
			_error "Strategy definition incorrect [${_definition}]."
			_error "Allowed defintions:"
			for _example in "1" "1*7" "1*7d" "i1" "i1*7" "i1*7d"; do _error "\t${_example}"; done
			exit 1
		fi

		local _iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
		local _retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
		if [[ -z "${_retention}" ]];
		then
			_retention="?"
		fi

		_backupStrategyNormalized="$(echo "${_backupStrategyNormalized}" | sed -r "s|\? $|${_iteration} |")${_iteration}*${_retention} "
	done
	_backupStrategyNormalized=$(echo "${_backupStrategyNormalized}" | sed -r "s| $||")

	if [[ "${_backupStrategyNormalized}" == *"\\?" ]];
	then
		_error "Strategy is broken: Missing last retention rule [${_backupStrategyNormalized}]."
		exit 1
	fi
	echo "${_backupStrategyNormalized}"
}

function _backupStrategyExplain() {
	local _backupStrategyNormalized="$1"

	echo -e "Explained backup strategy:"
	_backupStrategyIterationDays=""
	_backupStrategyRetentionDays=""
	_backupStrategyBackupCount="0"
	for _definition in ${_backupStrategyNormalized}
	do
		_iteration=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\1|g")
		_retention=$(echo "${_definition}" | sed -r "s|${BACKUP_DEFINITION}|\2|g" | sed 's|^\*||')
		_iterationNumber="$(echo "${_iteration}" | sed 's|^i||')"
		_retentionNumber="$(echo "${_retention}" | sed 's|d$||')"

		# _backupStrategyIterationDays
		if [[ -z "${_backupStrategyIterationDays}" ]];
			then _backupStrategyIterationDays="${_iterationNumber}"
			else _backupStrategyIterationDays="$(( ${_backupStrategyIterationDays} * ${_iterationNumber} ))"
		fi
		
		# _backupStrategyRetentionDays
		if [[ -z "${_backupStrategyRetentionDays}" ]]; then
			_backupStrategyRetentionDays="${_retentionNumber}"			
		elif [[ "${_retention}" == *"d" ]]; then
			_backupStrategyRetentionDays=$(( ${_backupStrategyRetentionDays} + ${_retentionNumber} ))
		else 
			_backupStrategyRetentionDays="$(( ${_backupStrategyRetentionDays} * ${_retentionNumber} ))"			
		fi

		echo -n -e "\t${_definition}\t=> Backup "
		if [[ "${_iteration}" == "i"* ]]; then
			echo -n "- changes - ";
		fi

		if [[ "${_iterationNumber}" == "0" ]];
			then echo -n "every run "
			else echo -n "every ${_backupStrategyIterationDays}. days "
		fi

		echo -n "and keep "
		if [[ ! "${_retention}" == *"d" ]]; then
			echo -n "last ${_retentionNumber} "

		fi
		echo -n "backups for ${_backupStrategyRetentionDays} days "

		if [[ "${_iterationNumber}" == "0" ]]; then echo -n -e "\n" && continue; fi # Can't count manualy scheduled backups
		
		_backupsCount="0"
		if [[ "${_iteration}" == "i"* ]]; then
			_backupsCount="1"
		elif [[ "${_retention}" == *"d" ]]; then
			_backupsCount="$(((${_retentionNumber} / ${_iterationNumber})))"
			if [[ $((${_retentionNumber} % ${_iterationNumber})) -gt 0 ]]; then $((_backupsCount++)); fi
		else
			_backupsCount="${_retentionNumber}"
		fi
		echo "(${_backupsCount} Backups)"
		_backupStrategyBackupCount="$((${_backupStrategyBackupCount} + ${_backupsCount}))"
	done
	echo
	
	if [[ "${_backupStrategyBackupCount}" == "0" ]]; then return 0; fi # Can't count manualy scheduled backups
	
	echo -e "Examples for storage usage for whole period:"
	for _example in "10" "100" "1024" "10240" "20480" "40960" "81920" "102400"
	do
		_backupSize="$((${_example} * ${_backupStrategyBackupCount}))"
		echo -n -e "\t${_backupStrategyBackupCount} Backups * "
		if [[ ${_example} -lt 1024 ]]; then echo -n "${_example} MB";
		elif [[ ${_example} -lt 1024000 ]]; then awk "BEGIN { printf \"%.0f GB\", (${_example}/1024) }";
	    else awk "BEGIN { printf \"%.0f TB\", (${_example}/1024/1024) }";
		fi
		echo -n -e " \t=> "

		echo -n "${_backupSize} MB"
		if [[ ${_backupSize} -gt 100 ]]; then awk "BEGIN { printf \" / %.2f GB\", (${_backupSize}/1024) }"; fi
		if [[ ${_backupSize} -gt 10240 ]]; then awk "BEGIN { printf \" / %.2f TB\", (${_backupSize}/1024/1024) }"; fi
		echo -n -e "\n"
	done
	echo
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
