#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
fi

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting disk space checks."
###################################

function ConvertThresholdToBytes() {
	local value=$1
	local prefix="${value: -1}"
	local len="${#value}"
	len=$(( len - 1 ))
	local size="${value:0:$len}"
	case $prefix in
		"K")
			size=$(( size * 1024 ))
			;;

		"M")
			size=$(( size * 1048576 ))
			;;

		"G")
			size=$(( size * 1073741824 ))
			;;

		*)
			size=$(( size * 1073741824 ))
			;;
	esac

	echo $size
}

function run_space_checks {
	local DEFAULT_FREESPACE="1G"
	local FILE_SYSTEM=()
	local SPACE_TOTAL=()
	local SPACE_USED=()
	local SPACE_AVAIL=()
	local MOUNT_POINT=()
	local SPACE_THRESHOLD=()
	local NEED_CHECK=()
	local ARRAY_LENGTH=0

	# Store info about each disk
	while read tmp1 tmp2 tmp3 tmp4 tmp5 tmp6 tmp7
	do
		# Match only physical devices
		if [[ $tmp1 =~ '/dev/' ]]; then
			FILE_SYSTEM+=( "$tmp1" )
			SPACE_TOTAL+=( $((tmp2 * 1024)) )
			SPACE_USED+=( $((tmp3 * 1024)) )
			SPACE_AVAIL+=( $((tmp4 * 1024)) )
			MOUNT_POINT+=( "$tmp6" )
			if [[ $tmp7 == '/' ]]; then
				NEED_CHECK+=( "1" )
			else
				NEED_CHECK+=( "0" )
			fi
			SPACE_THRESHOLD+=( "$DEFAULT_FREESPACE" )
			(( ARRAY_LENGTH++ ))
		fi
	done <<< "$(df -k)"

	# Read check list from config, correct the threshold value
	for (( I=0; I<${#DISK_CHECKLIST[@]}; I++ ))
	do
		FOUND=0
		DRIVEPATH=${DISK_CHECKLIST[I]%%:*}
		THRESHOLD=$(ConvertThresholdToBytes "${DISK_CHECKLIST[I]##*:}")
		for (( X=0; X<ARRAY_LENGTH; X++ ))
		do
			if [[ $DRIVEPATH == "${FILE_SYSTEM[X]}" ]]; then
				SPACE_THRESHOLD[X]=$THRESHOLD
				NEED_CHECK[X]="1"
				(( FOUND++ ))
				break
			fi
		done
		
		if [[ $FOUND == 0 ]]; then
			log "Disk '${DISK_CHECKLIST[I]}' not found. Check the config (DISK_CHECKLIST array)."
		fi
	done

	local AVAILABLE=""
	local USED=""
	local TOTAL=""
	local MESSAGE=""

	for (( I=0; I<ARRAY_LENGTH; I++ ))
	do
		if [[ ${NEED_CHECK[I]} == 0 ]]; then
			continue
		fi

		AVAILABLE=$(numfmt --to iec --format %8.2f "${SPACE_AVAIL[I]}")
		USED=$(numfmt --to iec --format %8.2f "${SPACE_USED[I]}")
		TOTAL=$(numfmt --to iec --format %8.2f "${SPACE_TOTAL[I]}")

		if (( SPACE_AVAIL[I] < SPACE_THRESHOLD[I] )); then
			MESSAGE=$MESSAGE"<b>Low space:</b>"
		else
			MESSAGE=$MESSAGE"<b>OK:</b>"
		fi

		MESSAGE="$MESSAGE ${FILE_SYSTEM[I]} (${MOUNT_POINT[I]}): Available:<b>$AVAILABLE</b>, Used:<b>$USED</b>, Total:<b>$TOTAL</b> "
	done

	WORKER_RESULT=$WORKER_RESULT$MESSAGE
}

run_space_checks

log "Disk space checks are done."