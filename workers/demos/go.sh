#!/bin/bash

# Preventing direct script invocation
if [ ${0##*/} == ${BASH_SOURCE[0]##*/} ]; then 
    echo "WARNING"
    echo "This script is not meant to be executed directly!"
    echo "Use this script only by sourcing it."
    echo ""
    exit 1
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting demo packing job."

# Include settings file (passed as argument)
if [[ -z $1 ]]; then
	log "Config file ($1) does not exist. Terminating."
	exit 1	
fi

source $1

log "Using config ${BWHITE}$CONFIG_DESCRIPTION${NORMAL}"

# Create zip output dir if not exist
if ! [ -d $DEMOS_ZIP_DIR ]; then
	mkdir -p $DEMOS_ZIP_DIR
fi

COMMAND="find $DEMOS_DIR -maxdepth 1 -name *.dem -print"
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
		log $(nice -n 19 zip -9 "$DEMOS_ZIP_DIR/$ZIP_FILENAME" "$i")
		ZIP_SIZE=$(stat -c %s "$DEMOS_ZIP_DIR/$ZIP_FILENAME")
		COMPRESSED_SIZE=$((ZIP_SIZE + COMPRESSED_SIZE))
		FILESLEFT=$(($TOTAL_COUNT - $COUNTER))
		if (( FILESLEFT > DEMOS_KEEP_COUNT )); then
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
log "Demo packing job finished."