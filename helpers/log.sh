#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# SCRIPT_DIR from main script will be also available here,
# because we include this script from main
readonly LOG_ENABLED=true
readonly LOG_SEPARATED_FILES=false
readonly LOG_DIR=$SCRIPT_DIR/logs

source "$SCRIPT_DIR/helpers/colors.sh"

if [[ -z $SCRIPT_DIR ]]; then
	echo "SCRIPT_DIR variable is not defined."
	exit 1
fi

if ! [[ -d $LOG_DIR ]]; then
	mkdir -p $LOG_DIR
fi

_log() {
	if [[ $# > 0 && $LOG_ENABLED ]]; then
		local TODAY=$(date +"%b-%d-%Y")
		local LOG_FILENAME="$LOG_DIR/$TODAY.txt"
		if $LOG_SEPARATED_FILES; then
			LOG_FILENAME="$LOG_DIR/$TODAY.$0.txt"
		fi
		DATETIME=$(date +"%H:%M:%S")
		ARG="-e"
		if [[ $1 == "true" ]]; then
			ARG="-en"
		fi
		shift
		echo $ARG "$*"
		echo $ARG "$DATETIME $*" | sed -e 's/\x1b\[[0-9;]*m//g' >> $LOG_FILENAME
	fi
}

# log normally
log() {
	_log "false" $*
}

# log with no caret return
logn() {
	_log "true" $*
}

# Traces call stack and shows text messages
log_debug() {
	local MSG="${BGREEN}[DEBUG] ${BGRAY}Relative path: [ ${BYELLOW}$SCRIPT_DIR/${NORMAL}${BGRAY} ]. Call stack:${NORMAL}\n"
	local i
	local SRC_PATH=""
	for (( i=${#FUNCNAME[*]}-1; i>=1; i-- )); do
		SRC_PATH=$(realpath --relative-to="$SCRIPT_DIR" "${BASH_SOURCE[$i]}")
		MSG="$MSG\t${BGRAY}Function: [ ${BYELLOW}${FUNCNAME[$i]}${BGRAY} ] "
		MSG=$MSG"File: [ ${BYELLOW}$SRC_PATH${BGRAY} ] "
		MSG=$MSG"Line: [ ${BYELLOW}${BASH_LINENO[$i-1]}${BGRAY} ]\n"
	done
	MSG=$MSG"\t${BGRAY}Messsage: [ ${BYELLOW}$*${BGRAY} ]${NORMAL}"
	log $MSG
}