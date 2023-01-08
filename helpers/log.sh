#!/bin/bash

# Preventing direct script invocation
if [ ${0##*/} == ${BASH_SOURCE[0]##*/} ]; then 
    echo "WARNING"
    echo "This script is not meant to be executed directly!"
    echo "Use this script only by sourcing it."
    echo ""
    exit 1
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