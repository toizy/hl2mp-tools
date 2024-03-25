#!/bin/bash

#--------------------------------------------------------------
# HL2MP-TOOLS
#
# Description:
# This is a script that maintains sourc-based servers like hl2dm
# or cstrike: deletes logs, archives demos, uploads backups and 
# demos to a remote (web)server etc.
#--------------------------------------------------------------

SCRIPT_FULLNAME=$(readlink -e "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_FULLNAME")
CONFIG_ARRAY=()

# IS_ACTIVE indicates to all includes that we are in progress!
IS_ACTIVE=true

SCRIPT_STANDALONE=false

#**************************************************************
# PARSE COMMAND LINE ARGUMENTS
#**************************************************************
POSITIONAL_ARGS=()
CONFIG_IDS=()

while [[ $# -gt 0 ]]
do
	case $1 in
		-h|--help)
			echo "Usage: numfmt [OPTION]"
			echo "  -h, --help		print this text"
			echo "  -c, --config		string separated by spaces. Defines the ID of the config to execute. If this parameter is omitted, the script will execute all available configs."
			echo "  -s, --standalone	run the script in standalone mode. It will process all enabled configs."
			exit
			;;
		-s|--standalone)
			SCRIPT_STANDALONE=true
			shift # past argument
			;;
		-c|--config)
			CONFIG_IDS+=("$2")
			shift # past argument
			shift # past value
			;;
		-*)
			echo "Unknown option $1"
			exit 1
			;;
		*)
			POSITIONAL_ARGS+=("$1") # save positional arg
			shift # past argument
			;;
	esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters

# Includes
. "$SCRIPT_DIR/helpers/functions.sh"
. "$SCRIPT_DIR/helpers/log.sh"
. "$SCRIPT_DIR/helpers/colors.sh"

# Check and install dependencies
check_dependencies

# Build a list of configs
echo -e "${BWHITE}Building a list of available configs${NORMAL}"
CONFIG_ARRAY=()
CONFIG_FILES_FOUND=$(find "$SCRIPT_DIR/servers/" -maxdepth 1 -name "*.config" -print)
COUNTER=0

for I in $CONFIG_FILES_FOUND
do
	. "$I"
	INLIST=true
	# Is the config specified in the parameters?
	if (( ${#CONFIG_IDS[@]} > 0 )); then
		for X in "${CONFIG_IDS[@]}"
		do
			if [[ $X =~ $CONFIG_ID ]]; then
				break
			fi
		done
		INLIST=false
	fi
	# if enabled and explicitly defined, then add to array.
	if CheckYesNoFlag "$CONFIG_ENABLED"; then
		if [[ $INLIST == true ]]; then
			if [[ $SCRIPT_STANDALONE == false ]]; then
				echo -e "[$(( COUNTER + 1 ))]${BWHITE}\t${BWHITE}$CONFIG_DESCRIPTION${NORMAL}"
			fi
			CONFIG_ARRAY+=("$I")
			(( COUNTER++ ))
		fi
	fi
done

# No configs to execute. Exit.
if (( ${#CONFIG_ARRAY[@]} == 0 )); then
	log "${YELLOW}No configs found. Terminating.${NORMAL}"
	exit 1
fi

if [[ $SCRIPT_STANDALONE == false ]]; then
	# User controlled mode
	echo -en "Select a config to execute (Or type 'cfg' to install/uninstall service): "
	# Read user input
	while :; do
		read -r ITEM

		if [[ ${ITEM,,} == "cfg" ]]; then
			. install-service/install-service.sh
			exit
		fi
		# Check input bounds
		CHECK=$(check_input "$ITEM" "1" $COUNTER)
		if [[ $CHECK == "" ]]; then
			break
		fi
	done

	(( ITEM-- ))
	FILENAME=${CONFIG_ARRAY[ITEM]}

	# Execute workers
	if [[ -z $FILENAME ]]; then
		log_debug "FILENAME var is empty!"
	else
		run_workers "$FILENAME"
	fi
else
	# Standalone mode (running by the systemd timer)
	for (( I=0; I<${#CONFIG_ARRAY[@]}; I++ ))
	do
		. "${CONFIG_ARRAY[I]}"
		echo "Using config: ${config_array[I]} ($CONFIG_DESCRIPTION)"
		run_workers "${CONFIG_ARRAY[I]}"
	done
fi