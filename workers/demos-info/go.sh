#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting demo gathering info job."

extract_demo_info "$DEMOS_DIR" "$DEMOS_INFO_DIR" "*.dem"