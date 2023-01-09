#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# The function searches for the files with the certain extension
# in the source directory, compresses them and puts in the 
# target directory. Keeps only the specified number of source files.
# Arguments:
# $1 - source path
# $2 - destination path
# $3 - file extension ('*.log', '*.dem' etc.)
# $4 - num of files to be kept
list_and_pack_files() {
	local SOURCE_PATH=$1
	local DESTINATION_PATH=$2
	local EXT=$3
	local KEEP_COUNT=$4
	
	# Create zip output dir if not exist
	if ! [ -d $DESTINATION_PATH ]; then
		mkdir -p $DESTINATION_PATH
	fi

	local ZIP_FILENAME=""
	local PERCENT=0
	local ZIP_SIZE=0
	local FILESLEFT=0
	local COMMAND="find $SOURCE_PATH -maxdepth 1 -name $EXT -print"
	local TOTAL_COUNT=$(eval $COMMAND | wc -l)
	local TOTAL_SIZE=$(eval $COMMAND | xargs stat --format=%s | awk '{s+=$1} END {print s}')
	local COMPRESSED_SIZE=0
	local COUNTER=0
	local NOT_REMOVED_COUNT=0

	for i in $(eval $COMMAND)
	do
		if [[ -f "$i" ]]; then
			ZIP_FILENAME="${i##*/}".zip
			PERCENT=$(( ($COUNTER*1000/$TOTAL_COUNT+5)/10 ))
			logn "[$PERCENT%] Item: $((COUNTER + 1))/$TOTAL_COUNT\t"
			log $(nice -n 19 zip $ZIP_COMPRESSION_RATE "$DESTINATION_PATH/$ZIP_FILENAME" "$i")
			ZIP_SIZE=$(stat -c %s "$DESTINATION_PATH/$ZIP_FILENAME")
			COMPRESSED_SIZE=$((ZIP_SIZE + COMPRESSED_SIZE))
			FILESLEFT=$(($TOTAL_COUNT - $COUNTER))
			if (( FILESLEFT > KEEP_COUNT )); then
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
	local TOTAL_SIZE_H=$(numfmt --to iec --format %8.2f $TOTAL_SIZE)
	local COMPRESSED_SIZE_H=$(numfmt --to iec --format %8.2f $COMPRESSED_SIZE)

	WORKER_RESULT="$TOTAL_COUNT files in total. Total size:$TOTAL_SIZE_H. Compressed size:$COMPRESSED_SIZE_H. $NOT_REMOVED_COUNT file(s) can not be removed."

	log "Files count: ${BWHITE}$TOTAL_COUNT${NORMAL}, "\
		"total size: ${BWHITE}$TOTAL_SIZE_H${NORMAL}, "\
		"compressed size: ${BWHITE}$COMPRESSED_SIZE_H${NORMAL}"
}