#!/bin/bash

CURSORPOS=()

# Do we need to read the status when calling ParseDemoInfo()?
READ_DEMO_STATUS=0

# ParseDemoInfo() result
declare -A DEMO_INFO

# ------------------------------------------------------
# Converts bytes to a string in a human-readable form
#
# $1 - A value in bytes
# ------------------------------------------------------
function BytesToString()
{
	echo $(numfmt --to iec --format %8.2f $1)
}

# ------------------------------------------------------
# Converts string to bytes
#
# $1 - A value in string
# ------------------------------------------------------
function StringToBytes()
{
	echo $(numfmt --from=iec $1)
}

# Checks first argument for error. If it's not equal 0, log it and terminate
# Arguments:
# $1 - Error code given by $?:
#	ls /home/notexistingdir
#	check_success_or_exit $?
#	will return code 2 and trigger logging + script termination
function check_success_or_exit() {
	if [[ -z $1 ]]; then
		log_debug "No arguments passed."
		exit 1
	fi
	if [[ $1 != 0 ]]; then
		log_debug "Error occured: $1. Terminating."
		exit 2
	fi
}

# Validation & range check
# $1 - Input
# $2 - Lower bound of the range
# $3 - Higher bound of the range
function check_input () {
	if [[ $# -gt 0 && $# -lt 4 ]]; then
		local INPUT=$1
		local LOWER=$2
		local HIGHER=$3
		[[ $INPUT =~ ^[0-9]+$ ]] || { echo -en "${BRED}Enter a valid number${NORMAL}: ">/dev/tty; echo "1"; return; }
		(( INPUT > 0 && INPUT <= HIGHER)) || { echo -en "${BRED}Enter a number in the range from $LOWER to $HIGHER${NORMAL}: ">/dev/tty; echo "2"; return; }
		echo ""
	else
		echo "3";
	fi
}

# Run enabled workers for a config.
# Arguments:
#	$1 - config filename
function run_workers() {
	if [[ ! -f $1 ]]; then
		return 1
	fi
	. "$1"
	local WORKERS_RESULT=""
	local STEP=0
	if CheckYesNoFlag "$WORKER_DEMO"; then
		. "$SCRIPT_DIR/workers/demos/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Demo packing is done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_DEMO_INFO"; then
		. "$SCRIPT_DIR/workers/demos-info/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Demo info gathering is done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_LOGS"; then
		. "$SCRIPT_DIR/workers/logs/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Logs trimming and packing is done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_LOGS_SM"; then
		. "$SCRIPT_DIR/workers/sourcemod-logs/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Sourcemod logs packing is done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_SYNC"; then
		. "$SCRIPT_DIR/workers/rsync/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Syncing is done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_DISK"; then
		. "$SCRIPT_DIR/workers/disk/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Disk space checks are done. '$WORKER_RESULT'%0A'
	fi
	if CheckYesNoFlag "$WORKER_YANDEX_DISK"; then
		. "$SCRIPT_DIR/workers/yandex-disk/go.sh"
		WORKERS_RESULT=$WORKERS_RESULT'['$((++STEP))'] Yandex.Disk task is done. '$WORKER_RESULT'%0A'
	fi
	send_to_telegram "$WORKERS_RESULT"
}

# Helper function that compresses a file. It's used in some other functions like 'list_and_pack_files'
# Arguments:
# $1 - Input file
# $2 - Output file
function do_zip() {
	local NICE_CMD=""
	local FILE_IN=$1
	local FILE_OUT=$2

	# Check for spaces in the FILE_OUT (to prevent 'zip warning: name not matched') 
	if [[ $FILE_OUT =~ [[:space:]] ]]; then
		log_debug "There are spaces in the path. The result may be incorrect."
	fi

	if [[ $ZIP_USE_NICE ]]; then
		NICE_CMD="nice -n $ZIP_NICE_VALUE"
	fi
	# TODO Avoid eval
	log "$(eval "$NICE_CMD" zip "$ZIP_COMPRESSION_RATE" "$FILE_OUT" "$FILE_IN")"
}

# The function searches for the files with the certain extension
# in the source directory, compresses them and puts in the 
# target directory. Keeps only the specified number of source files.
# Arguments:
# $1 - source path
# $2 - destination path
# $3 - file extension ('*.log', '*.dem' etc.)
# $4 - num of files to be kept
function list_and_pack_files() {
	local SOURCE_PATH=$1
	local DESTINATION_PATH=$2
	local NAMEMASK=$3
	local KEEP_COUNT=$4

	# Create zip output dir if not exist
	if ! [ -d "$DESTINATION_PATH" ]; then
		mkdir -p "$DESTINATION_PATH"
		check_success_or_exit $?
	fi

	local ZIP_FILENAME=""
	local PERCENT=0
	local ZIP_SIZE=0
	local FILESLEFT=0
	local TOTAL_COUNT=0
	local TOTAL_SIZE=0
	local COMPRESSED_SIZE=0
	local COUNTER=0
	local NOT_REMOVED_COUNT=0
	local COMMAND="find $SOURCE_PATH -maxdepth 1 -name $NAMEMASK -print"
	TOTAL_COUNT=$(eval "$COMMAND" | wc -l)
	if (( TOTAL_COUNT > 0 )); then
		TOTAL_SIZE=$(eval "$COMMAND" | xargs stat --format=%s | awk '{s+=$1} END {print s}')
	
		for i in $(eval "$COMMAND")
		do
			if [[ -f "$i" ]]; then
				ZIP_FILENAME="${i##*/}".zip
				PERCENT=$(( (COUNTER*1000/TOTAL_COUNT+5)/10 ))
				logn "[$PERCENT%] Item: $((COUNTER + 1))/$TOTAL_COUNT\t"
				do_zip "$i" "$DESTINATION_PATH/$ZIP_FILENAME"
				ZIP_SIZE=$(stat -c %s "$DESTINATION_PATH/$ZIP_FILENAME")
				COMPRESSED_SIZE=$((ZIP_SIZE + COMPRESSED_SIZE))
				FILESLEFT=$((TOTAL_COUNT - COUNTER))
				if (( FILESLEFT > KEEP_COUNT )); then
					if rm -fr "$i"; then
						log "File ${i##*/} removed."
					else
						log "Error: file ${i##*/} can not be removed."
						((NOT_REMOVED_COUNT++))
					fi
				fi
				((COUNTER++))
			fi
		done
	fi

	# Update worker result
	local TOTAL_SIZE_H=""
	TOTAL_SIZE_H=$(BytesToString "$TOTAL_SIZE")

	local COMPRESSED_SIZE_H=""
	COMPRESSED_SIZE_H=$(BytesToString $COMPRESSED_SIZE)

	WORKER_RESULT="$TOTAL_COUNT files in total. Total size:$TOTAL_SIZE_H. Compressed size:$COMPRESSED_SIZE_H. $NOT_REMOVED_COUNT file(s) can not be removed."

	log "Files count: ${BWHITE}$TOTAL_COUNT${NORMAL}, "\
		"total size: ${BWHITE}$TOTAL_SIZE_H${NORMAL}, "\
		"compressed size: ${BWHITE}$COMPRESSED_SIZE_H${NORMAL}"
}

# Sends a text message to a Telegram group via BotAPI
# Arguments:
# $* - Text message
# The function uses internal TELEGRAM_ and CONFIG_DESCRIPTION variables defined in the config file.
function send_to_telegram()
{
	if [[ -z $TELEGRAM_BOT_TOKEN || -z $TELEGRAM_CHATID ||\
		-z $TELEGRAM_USERID || -z $TELEGRAM_USERNAME ||\
		-z $CONFIG_DESCRIPTION ]]; then
		log_debug "One or more of arguments are not set. Terminating."
		exit 1
	fi
	if [[ -z $* ]]; then
		log_debug "No arguments passed."
		exit 1
	fi
	local CR='%0A%0A'
	local GREETING='HL2DM-Tools report'
	local MSG='<a href="tg://user?id='$USERID'">@'$USERNAME'</a> <b>'$CONFIG_DESCRIPTION'</b>'$CR$GREETING$CR$*
	curl -s -o /dev/null \
	--data "parse_mode=HTML" \
	--data "text=$MSG" \
	--data "chat_id=$TELEGRAM_CHATID" \
	'https://api.telegram.org/bot'"$TELEGRAM_BOT_TOKEN"'/sendMessage'
}

# Are the all dependencies installed? If not, install them!
function check_dependencies()
{
	echo -e "${BOLD}Checking dependencies... ${NORMAL}"

	DEPENDENCIES=("zip")
	PKG_INSTALLED=""
	PKG_NOT_INSTALLED=""

	for i in "${DEPENDENCIES[@]}"; do
		if [[ ! $(dpkg-query -s "$i" 2>/dev/null) ]]; then
			echo -en "Installing package ${BYELLOW}${i}${NORMAL}... "
			if [[ $(sudo apt-get install -q -y "${i}" &>/dev/null) ]]; then
				echo -e "ok"
				PKG_INSTALLED="$PKG_INSTALLED ${BYELLOW}${i}${NORMAL}"
			else
				echo -e "not installed"
				PKG_NOT_INSTALLED="$PKG_NOT_INSTALLED ${BYELLOW}${i}${NORMAL}"
			fi
		fi
	done

	if [[ -n $PKG_INSTALLED ]]; then
		echo -e "Following packages has been installed:$PKG_INSTALLED"
	fi

	if [[ -n $PKG_NOT_INSTALLED ]]; then
		echo -e "Following packages not installed:$PKG_NOT_INSTALLED"
		echo -e "Please install not installed packages manually. Now terminating."
		exit 1
	fi
}

function CheckYesNoFlag() {
	local FLAG="${1,,}"
	case $FLAG in
		"yes"|"y"|"1"|"+"|"true"|"enable"|"enabled"|"active"|"activated")
			return 0
			#echo "0"
		;;
		*)
			return 1
			#echo "1"
		;;
	esac
}

function GetCursorPosition()
{
	local POS=''
	local TMP=''
	exec < /dev/tty
	TMP=$(stty -g)
	stty raw -echo min 0
	echo -en "\033[6n" > /dev/tty
	IFS=';' read -r -d R -a POS
	stty "$TMP"
	CURSORPOS[0]=$((${POS[0]:2} - 2))
	CURSORPOS[1]=$((POS[1] - 1))
}

function RestoreCursorPos()
{
	tput cup "${CURSORPOS[0]}" "${CURSORPOS[1]}"
}

# Parse .dem file
# Arguments
# $* - Path to a file
function parse_demo_info()
{
	local filename="$1"
	local basename
	local header

	# File name without path and extention
	basename="$(basename "$filename" .dem)"
	# Extracting the date and time from the file name
	if [[ $basename =~ ^.*([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{4})-(.*)$ ]]; then
		DEMO_INFO["datetime"]="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]:0:2}:${BASH_REMATCH[4]:2}"
	else
		echo "Bad file format: $filename" >&2
		return 1
	fi

	# Is file extentions valid?
	if [[ ${filename##*.} != "dem" ]]; then
		log "Bad file extension: $basename" >&2
		return 1
	fi

	# Read and check file header
	header=$(dd status=none if="$filename" bs=1 count=8 | grep -a -o -P "[^\x00]+")
	DEMO_INFO["Header"]=$header
	if [[ $header != "HL2DEMO" ]]; then
		log "Bad file header: $basename" >&2
		return 1
	fi

	# Block by block read
	{
		# Below I'm using tr -d ' ' to delete opening spaces (don't know how to tune 'od' command =\)
		# Advise me if you know...
		DEMO_INFO["dem_prot"]=$(tail -c +9 "$filename" | dd status=none bs=4 count=1 2>/dev/null | od -An -t u4 | tr -d ' ')
		DEMO_INFO["net_prot"]=$(tail -c +13 "$filename" | dd status=none bs=4 count=1 2>/dev/null | od -An -t u4 | tr -d ' ')

		DEMO_INFO["host_name"]=$(tail -c +17 "$filename" | head -c 260 | tr -d '\0')
		DEMO_INFO["client_name"]=$(tail -c +277 "$filename" | head -c 260 | tr -d '\0')
		DEMO_INFO["map_name"]=$(tail -c +537 "$filename" | head -c 260 | tr -d '\0[:space:]')
		DEMO_INFO["gamedir"]=$(tail -c +797 "$filename" | head -c 260 | tr -d '\0[:space:]')

		
		DEMO_INFO["time"]=$(tail -c +1057 "$filename" | dd status=none bs=1 count=4 2>/dev/null | od -t f4 -An | tr -d ' ')
		DEMO_INFO["ticks"]=$(tail -c +1061 "$filename" | dd status=none bs=1 count=4 2>/dev/null | od -An -t u4 | tr -d ' ')
		DEMO_INFO["frames"]=$(tail -c +1065 "$filename" | dd status=none bs=1 count=4 2>/dev/null | od -An -t u4 | tr -d ' ')
		DEMO_INFO["tickrate"]=$(awk -v ticks="${DEMO_INFO["ticks"]}" -v time="${DEMO_INFO["time"]}" 'BEGIN { printf "%.0f", ticks / time }')
	} < <(tail -n +2 "$filename" | tr -d '\0' | head -n 9)

	# Recorded by a server or client? (IP:PORT)
	if [[ ${DEMO_INFO["host_name"]} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
		DEMO_INFO["type"]=0 # RIE
	else
		DEMO_INFO["type"]=1 # TV
	fi

	# Status exists?
	if [[ "$READ_DEMO_STATUS" -eq 1 && ${DEMO_INFO["type"]} -ne 1 ]]; then
		if grep -q -F -e $'\x00status\x00' "$filename"; then
			DEMO_INFO["status_present"]=1
		else
			DEMO_INFO["status_present"]=0
		fi
	else
		DEMO_INFO["status_present"]=0
	fi
}

function extract_demo_info() {
	local SOURCE_PATH=$1
	local DESTINATION_PATH=$2
	local NAMEMASK=$3

	# Create output dir if not exist
	if ! [ -d "$DESTINATION_PATH" ]; then
		mkdir -p "$DESTINATION_PATH"
		check_success_or_exit $?
	fi

	local JSON_CONTENT=""
	local PERCENT=0
	local COUNTER=0
	local COMMAND="find $SOURCE_PATH -maxdepth 1 -name $NAMEMASK -print"
	TOTAL_COUNT=$(eval "$COMMAND" | wc -l)
	if (( TOTAL_COUNT > 0 )); then
		TOTAL_SIZE=$(eval "$COMMAND" | xargs stat --format=%s | awk '{s+=$1} END {print s}')
	
		for i in $(eval "$COMMAND")
		do
			if [[ -f "$i" ]]; then
				INFO_FILENAME="${i##*/}".json
				parse_demo_info "$i"

				# Dump info as JSON
				JSON_CONTENT="{"$'\n'
				for key in "${!DEMO_INFO[@]}"; do
					JSON_CONTENT+="  \"$key\": \"${DEMO_INFO[$key]}\","$'\n'
				done
				# Remove the last comma and add a closing parenthesis
				JSON_CONTENT="${JSON_CONTENT%,*}"$'\n'"}"
				
				if ! echo "$JSON_CONTENT" > "$DESTINATION_PATH/$INFO_FILENAME"; then
					exit_code=$?
					case $exit_code in
						1)
							log "Error: Permission denied while writing JSON file for $i\n";;
						2)
							log "Error: No such file or directory while writing JSON file for $i\n";;
						*)
							log "Error: Failed to write JSON file for $i (Exit code: $exit_code)\n";;
					esac
				fi

				PERCENT=$(( (COUNTER*1000/TOTAL_COUNT+5)/10 ))
				logn "[$PERCENT%] Item: $((COUNTER + 1))/$TOTAL_COUNT\t	$i $INFO_FILENAME\n"

				((COUNTER++))
			fi
		done
	fi

	# Update worker result
	WORKER_RESULT="$TOTAL_COUNT files in total."

	log "Files count: ${BWHITE}$TOTAL_COUNT${NORMAL}"
}