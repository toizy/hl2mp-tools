#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting logs packing job."

list_and_pack_files $LOGS_DIR $LOGS_ZIP_DIR "*.log" $LOGS_KEEP_COUNT

# Trim 'console.log' file
log "Trimming console.log file"

# Create zip output dir if not exist
if ! [ -d $CONSOLE_LOG_ZIP_DIR ]; then
	mkdir -p $CONSOLE_LOG_ZIP_DIR
	check_success_or_exit $?
fi

# Zip the file
ZIP_FILENAME="$CONSOLE_LOG_ZIP_DIR/$(date +"%b-%d-%Y_%H:%M:%S").zip"
do_zip "$CONSOLE_LOG_FILE" "$ZIP_FILENAME"

# Trim it
if (( CONSOLE_LOG_LINES > 0 )); then
	tempfile=$(mktemp)
	tail --lines=$CONSOLE_LOG_LINES --silent "$CONSOLE_LOG_FILE" > "$tempfile"
	mv "$tempfile" "$CONSOLE_LOG_FILE"
	rm -fr $tempfile
	WORKER_RESULT=$WORKER_RESULT" console.log file is trimmed."
fi

log "Logs packing job finished."