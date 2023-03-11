#!/bin/bash

#set -o nounset  # Exit when a script tries to use undeclared variables
#set -o errexit  # Exit when a command fails

# Constants
readonly URL_DISK_API="https://cloud-api.yandex.net:443/v1"
readonly URL_DISK_INFO="$URL_DISK_API/disk"
readonly URL_RESOURCE="$URL_DISK_INFO/resources"
readonly URL_UPLOAD="$URL_RESOURCE/upload?path=app:/"
#readonly URL_RESINFO="$URL_DISK_API/?path=app:/"
readonly URL_CREATEDIR="$URL_RESOURCE?path=app:/"
readonly URL_USER_INFO="https://login.yandex.ru/info"

YD_INTERNAL_TOKEN=""

# Current date and time as a timestamp
readonly DT_NOW=$(date +%s)

# Outdated files will be deleted after $EXPIRATION number of days
EXPIRATION="1"
EXPIRATION=$(( DT_NOW - EXPIRATION * 60 ))
#date -d @$EXPIRATION

# Bash 4.2+ ?
# https://yandex.ru/dev/disk/api/reference/capacity.html
declare -A YANDEX_DISK_INFO
YANDEX_DISK_INFO[total_space]=-1
YANDEX_DISK_INFO[used_space]=-1
YANDEX_DISK_INFO[free_space]=-1

function ParseJSON() {
	local RESULT=''
	REGEX="(\"$1\":[\"]?)([^\",\}]+)([\"]?)"
	[[ $2 =~ $REGEX ]] && RESULT=${BASH_REMATCH[2]}
	echo "$RESULT"
}

function GetError() {
	ParseJSON 'error' "$1"
}

# ------------------------------------------------------
# Upload a file to Yandex.Disk.
#
# $1 Full local file path
# $2 Remote file path relative to the Yandex app folder
# ------------------------------------------------------
function UploadFile() {
	local JSON_OUTPUT=''
	local JSON_ERROR=''
	local UPLOAD_URL=''

	# Ask Yandex.Disk for an upload link
	JSON_OUTPUT=$(curl -s -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "${URL_UPLOAD}$2")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' ]]; then
		log "URL for the '$1' was not received Error: $JSON_ERROR"
		return 1
	fi

	UPLOAD_URL=$(ParseJSON 'href' "$JSON_OUTPUT")

	# If the link was successfully received...
	if [[ $UPLOAD_URL != '' ]]; then
		# ...upload it!
		JSON_OUTPUT=$(curl -s -T "$1" -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$UPLOAD_URL")
		JSON_ERROR=$(GetError "$JSON_OUTPUT")

		# Error handling
		if [[ $JSON_ERROR != '' ]]; then
			log "File '$1' is not uploaded. Error: $JSON_ERROR"
		else
			log "File '$1' is successfully uploaded to Yandex.Disk"
			return 0
		fi
	else
		log "URL for the '$1' is empty."
	fi
}

# ------------------------------------------------------
# Get the email of the Yandex account user.
# ------------------------------------------------------
function GetEmail()
{
	local JSON_OUTPUT=''
	local JSON_ERROR=''

	JSON_OUTPUT=$(curl -s -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$URL_USER_INFO")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' ]]; then
		log "Could not retrieve email info. Error: $JSON_ERROR"
	fi
	if [[ $JSON_OUTPUT =~ (\"default_email\": \".*\",) ]]; then
		JSON_OUTPUT=${BASH_REMATCH[0]}
		JSON_OUTPUT=${JSON_OUTPUT//\"default_email\": /}
		JSON_OUTPUT=${JSON_OUTPUT//\"/}
		JSON_OUTPUT=${JSON_OUTPUT//,/}
		echo "$JSON_OUTPUT"
	fi
}

# ------------------------------------------------------
# Create a directory on Yandex.Disk.
# If the directory has been successfully created or
# already exists, returns 'OK'.
#
# $1 - The path to the directory on Yandex.Disk
# ------------------------------------------------------
function CreateDir()
{
	local JSON_OUTPUT=''
	local JSON_ERROR=''

	JSON_OUTPUT=$(curl -s -X PUT -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "${URL_CREATEDIR}$1")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' && $JSON_ERROR != 'DiskPathPointsToExistentDirectoryError' ]]; then
		log "Directory '$1' is not created. Error: $JSON_ERROR"
	else
		echo 'OK'
	fi
}

# ------------------------------------------------------
# Get common information about Yandex.Disk 
# like disk usage
# ------------------------------------------------------
function GetYandexDiskInfo()
{
	local JSON_OUTPUT=''
	local JSON_ERROR=''

	JSON_OUTPUT=$(curl -s -X GET -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$URL_DISK_INFO")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' ]]; then
		log "Could not get Yandex.Disk info. Error: $JSON_ERROR"
	else
		if [[ $JSON_OUTPUT =~ (\"total_space\":[0-9]+) ]]; then
			YANDEX_DISK_INFO[total_space]=${BASH_REMATCH[0]//\"total_space\":/}
		fi
		if [[ $JSON_OUTPUT =~ (\"used_space\":[0-9]+) ]]; then
			YANDEX_DISK_INFO[used_space]=${BASH_REMATCH[0]//\"used_space\":/}
		fi

		YANDEX_DISK_INFO[free_space]=$(( YANDEX_DISK_INFO[total_space] - YANDEX_DISK_INFO[used_space] ))
	fi
}

#FILENAMES=()

function DeleteFile()
{
	local JSON_OUTPUT=''
	local JSON_ERROR=''
	local FILENAME=$1
	local PERM_DEL='false'
	## TODO Don't do this every time
	CheckYesNoFlag "${YD[DELETE_PERMANENTLY]}" && PERM_DEL='true'

	JSON_OUTPUT=$(curl -s -X DELETE -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$URL_RESOURCE/?path=$FILENAME&permanently=$PERM_DEL&fields=size,_embedded.items.size")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' ]]; then
		log "Could not delete the file '$1'. Error: $JSON_ERROR"
	fi
}

NEED_TERMINATE=false
LEVEL_OF_NESTING='0'

function EnumAndClean()
{
	if [[ $NEED_TERMINATE == true ]]; then
		return 1
	fi

	local JSON_OUTPUT=''
	local JSON_ERROR=''
	local FILEPATH=$1
	local TIME_END=${2:--1}
	local TIME_NOW=''
	local IS_DIR_EMPTY=''
	local PATHS=()
	local TYPES=()
	local INDEX=0

	TIME_NOW=$(date +%s)

	if (( TIME_END > -1 && TIME_END <= TIME_NOW )); then
		log "The maximum task execution time has been reached."
		NEED_TERMINATE=true
		return 1
	fi

	log "Entering directory $FILEPATH"
	
	# TODO --connect-timeout -m/max-time
	JSON_OUTPUT=$(curl -s -X GET -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$URL_RESOURCE/?path=$FILEPATH'qwe'&limit=${YD[DELETION_LIMIT]}&sort=created&fields=_embedded.items.path,_embedded.items.created,_embedded.items.size,_embedded.items.type")
	JSON_ERROR=$(GetError "$JSON_OUTPUT")

	if [[ $JSON_ERROR != '' ]]; then
		if (( LEVEL_OF_NESTING > 0 )); then
			log "Could not get resource info for '$FILEPATH'. Error: $JSON_ERROR"
		else
			NEED_TERMINATE=true
		fi
		return 1
	fi

	# We have reached the nesting level equal to 0, which means we are in the root directory
	# of the application. We also didn't get any nested objects, that means the directory 
	# is empty and we have to terminate.
	# shellcheck disable=SC2207
	PATHS=( $(grep -Po '(?<="path":")[^"]*' <<< "$JSON_OUTPUT") )
	if [[ ${#PATHS[@]} == "0" && $LEVEL_OF_NESTING == "0" ]]; then
		NEED_TERMINATE=true
		return 0
	fi

	LEVEL_OF_NESTING=$(( LEVEL_OF_NESTING + 1 ))
	
	# shellcheck disable=SC2207
	CREATED=( $(grep -Po '(?<="created":")[^"]*' <<< "$JSON_OUTPUT") )
	TIMESTAMP=()
	for I in "${CREATED[@]}"
	do
		TIMESTAMP+=( "$(date -d "$I" +"%s")" )
	done

	# shellcheck disable=SC2207
	TYPES=( $(grep -Po '(?<="type":")[^"]*' <<< "$JSON_OUTPUT") )
	INDEX=0
	for I in "${TYPES[@]}"
	do
		if [[ $I == 'dir' ]]; then
			EnumAndClean "${PATHS[INDEX]}" "$2"
			JSON_OUTPUT=$(curl -s -X GET -H "Authorization: OAuth $YD_INTERNAL_TOKEN" "$URL_RESOURCE/?path=${PATHS[INDEX]}&limit=$LIMIT&sort=created&fields=_embedded.items.path,_embedded.items.created,_embedded.items.size,_embedded.items.type")
			IS_DIR_EMPTY=$(grep -Po '(?<="items":)[[]]' <<< "$JSON_OUTPUT")
			if [[ -n $IS_DIR_EMPTY ]]; then
				log "Deleting empty directory ${PATHS[INDEX]}"
				DeleteFile "${PATHS[INDEX]}"
			fi
		else
			if (( TIMESTAMP[INDEX] < EXPIRATION )); then
				log "Outdated file: '${PATHS[INDEX]}', deleting..."
				DeleteFile "${PATHS[INDEX]}"
			fi
		fi
		(( ++INDEX ))
	done
	
	LEVEL_OF_NESTING=$(( LEVEL_OF_NESTING - 1 ))
}

function IsDiskLowSpaced()
{
	local MIN_SPACE=''
	MIN_SPACE=$(StringToBytes "${YD[MINIMUM_DISK_SPACE]}")
	GetYandexDiskInfo
	if (( YANDEX_DISK_INFO[free_space] > MIN_SPACE )); then
		return 1
	else
		return 0
	fi
}

function DiskCleanUp()
{
	NEED_TERMINATE=false
	LEVEL_OF_NESTING='0'

	local INITIAL_FREE_SPACE='-1'
	local TIME_NOW=''
	local INITIAL_FREE_SPACE=''
	local MIN_SPACE=''
	local END_OF_EXECUTION=''
	TIME_NOW=$(date +%s)
	END_OF_EXECUTION=$(( TIME_NOW + YD[MAX_EXECUTION_TIME] ))

	GetYandexDiskInfo

	INITIAL_FREE_SPACE=${YANDEX_DISK_INFO[free_space]}

	if [[ -n ${YD[MINIMUM_DISK_SPACE]} ]]; then
		MIN_SPACE=$(StringToBytes "${YD[MINIMUM_DISK_SPACE]}")
	fi

	while :
	do
		if [[ -z $MIN_SPACE ]]; then
			log "Cleaning up outdated files on Yandex.Disk"
		else
			if (( YANDEX_DISK_INFO[free_space] < MIN_SPACE )); then
				log "Not enough disk space on account '$EMAIL' ($(BytesToString "${YANDEX_DISK_INFO[free_space]}"))"
			else
				break 
			fi
		fi	

		if (( END_OF_EXECUTION <= TIME_NOW )) ; then
			log "The maximum task execution time has been reached."
			break
		fi

		log "Trying to clean up old files."
		EnumAndClean "app:/${YD[APP_FOLDER]}" "$END_OF_EXECUTION"

		GetYandexDiskInfo
		log "Freed: $(BytesToString "$(( YANDEX_DISK_INFO[free_space] - INITIAL_FREE_SPACE ))")"

		[[ $NEED_TERMINATE == true ]] && break
	done
}