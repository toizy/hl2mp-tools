#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting logs packing job."

# Include settings file (passed as argument)
if [[ -z $1 ]]; then
	log "Config file ($1) does not exist. Terminating."
	exit 1	
fi

source $1

log "Using config ${BWHITE}$CONFIG_DESCRIPTION${NORMAL}"

# Create zip output dir if not exist
if ! [ -d $LOGS_ZIP_DIR ]; then
	mkdir -p $LOGS_ZIP_DIR
fi

COMMAND="find $LOGS_DIR -maxdepth 1 -name *.log -print"
TOTAL_COUNT=$(eval $COMMAND | wc -l)
TOTAL_SIZE=$(eval $COMMAND | xargs stat --format=%s | awk '{s+=$1} END {print s}')
COMPRESSED_SIZE=0
COUNTER=0
NOT_REMOVED_COUNT=0

for i in $(eval $COMMAND)
do
	if [[ -f "$i" ]]; then
		ZIP_FILENAME="${i##*/}".zip
		PERCENT=$(( ($COUNTER*1000/$TOTAL_COUNT+5)/10 ))
		logn "[$PERCENT%] Item: $((COUNTER + 1))/$TOTAL_COUNT\t"
		log $(nice -n 19 zip $ZIP_COMPRESSION_RATE "$LOGS_ZIP_DIR/$ZIP_FILENAME" "$i")
		ZIP_SIZE=$(stat -c %s "$LOGS_ZIP_DIR/$ZIP_FILENAME")
		COMPRESSED_SIZE=$((ZIP_SIZE + COMPRESSED_SIZE))
		FILESLEFT=$(($TOTAL_COUNT - $COUNTER))
		if (( FILESLEFT > LOGS_KEEP_COUNT )); then
			rm -fr $i
			if [[ $? == 0 ]]; then
				log "File ${i##*/} removed."
			else
				log "Error: file ${i##*/} can not be removed."
				((NOT_REMOVED_COUNT++))
			fi
		fi
		((COUNTER++))
	fi
done

# Update worker result
TOTAL_SIZE_H=$(numfmt --to iec --format %8.2f $TOTAL_SIZE)
COMPRESSED_SIZE_H=$(numfmt --to iec --format %8.2f $COMPRESSED_SIZE)

WORKER_RESULT="$TOTAL_COUNT files in total. Total size:$TOTAL_SIZE_H. Compressed size:$COMPRESSED_SIZE_H. $NOT_REMOVED_COUNT file(s) can not be removed."

log "Files count: ${BWHITE}$TOTAL_COUNT${NORMAL}, "\
	"total size: ${BWHITE}$TOTAL_SIZE_H${NORMAL}, "\
	"compressed size: ${BWHITE}$COMPRESSED_SIZE_H${NORMAL}"

# Trim 'console.log' file
log "Trimming console.log file"

# Create zip output dir if not exist
if ! [ -d $CONSOLE_LOG_ZIP_DIR ]; then
	mkdir -p $CONSOLE_LOG_ZIP_DIR
fi

ZIP_FILENAME=$CONSOLE_LOG_ZIP_DIR/$(date +"%b-%d-%Y %H:%M:%S").zip
log $(nice -n 19 zip -9 "$ZIP_FILENAME" "$CONSOLE_LOG_FILE")

if (( CONSOLE_LOG_LINES > 0 )); then
	tempfile=$(mktemp)
	tail --lines=$CONSOLE_LOG_LINES --silent "$CONSOLE_LOG_FILE" > "$tempfile"
	mv "$tempfile" "$CONSOLE_LOG_FILE"
	rm -fr $tempfile
	WORKER_RESULT=$WORKER_RESULT" console.log file is trimmed."
fi

log "Logs packing job finished."