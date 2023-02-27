#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""
log "Starting rsync syncronization job."

function RSyncLocalToRemote() {
	RSYNC_CMD="-"

	if CheckYesNoFlag $RSYNC_PROGRESS; then
		RSYNC_CMD=$RSYNC_CMD'P'
	fi
	if CheckYesNoFlag $RSYNC_USECRC; then
		RSYNC_CMD=$RSYNC_CMD'c'
	fi
	if CheckYesNoFlag $RSYNC_PRESERVETIME; then
		RSYNC_CMD=$RSYNC_CMD't'
	fi
	if CheckYesNoFlag $RSYNC_HUMANREADABLE; then
		RSYNC_CMD=$RSYNC_CMD'h'
	fi
	if CheckYesNoFlag $RSYNC_RECURSE; then
		RSYNC_CMD=$RSYNC_CMD'r'
	fi
	if CheckYesNoFlag $RSYNC_DELETE; then
		RSYNC_CMD=$RSYNC_CMD' --delete'
	fi
	if CheckYesNoFlag $RSYNC_DELETE_SOURCE; then
		RSYNC_CMD=$RSYNC_CMD' --remove-source-files'
	fi
	if [[ -n $RSYNC_CUSTOM_RULES ]]; then
		RSYNC_CMD=$RSYNC_CMD $RSYNC_CUSTOM_RULES
	fi

	if [[ $RSYNC_CMD == "-" ]]; then
		log_debug "RSync flags are empty"
		return 0
	fi

	RSYNC_CMD=$RSYNC_CMD" --info=stats2"

	local STR_SENT=""
	local STR_RECEIVED=""
	local STR_TOTALSIZE=""

	# shellcheck disable=SC2086
	RSYNC_OUTPUT=$(rsync $RSYNC_CMD --bwlimit="$RSYNC_BANDWIDTH" -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i '"$REMOTE_KEY"' -p '"$REMOTE_PORT"'' "$REMOTE_FROM" "$REMOTE_USER"@"$REMOTE_HOST":"$REMOTE_TO")
	if [[ $RSYNC_OUTPUT =~ (Total bytes sent: [0-9]+\.*[0-9]*[K,M,G,T]*) ]]; then
		STR_SENT=${BASH_REMATCH[0]}
	fi
	if [[ $RSYNC_OUTPUT =~ (Total bytes received: [0-9]+\.*[0-9]*[K,M,G,T]*) ]]; then
		STR_RECEIVED=${BASH_REMATCH[0]}
	fi
	if [[ $RSYNC_OUTPUT =~ (Total file size: [0-9]+\.*[0-9]*[K,M,G,T]*) ]]; then
		STR_TOTALSIZE=${BASH_REMATCH[0]}
	fi
	STR_SENT=${STR_SENT//: /: <b>}
	STR_RECEIVED=${STR_RECEIVED//: /: <b>}
	STR_TOTALSIZE=${STR_TOTALSIZE//: /: <b>}
	STR_SENT=$STR_SENT'</b>'
	STR_RECEIVED=$STR_RECEIVED'</b>'
	STR_TOTALSIZE=$STR_TOTALSIZE'</b>'
	WORKER_RESULT="$WORKER_RESULT$STR_SENT; $STR_RECEIVED; $STR_TOTALSIZE. "
}>/dev/tty

RSyncLocalToRemote

log "Rsync job finished."