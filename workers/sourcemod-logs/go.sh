#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting sourcemod logs packing job."

list_and_pack_files "$LOGS_SM_DIR" "$LOGS_SM_ZIP_DIR" "*.log" "$LOGS_SM_KEEP_COUNT"

log "Logs packing job finished."