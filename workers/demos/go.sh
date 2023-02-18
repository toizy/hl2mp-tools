#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting demo packing job."

list_and_pack_files "$DEMOS_DIR" "$DEMOS_ZIP_DIR" "*.dem" "$DEMOS_KEEP_COUNT"