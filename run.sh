#!/bin/bash

#--------------------------------------------------------------
# Description
# ...
#
#--------------------------------------------------------------

SCRIPT_DIR=$(dirname $(readlink -e $0))

IS_ACTIVE="TRUE"

source "$SCRIPT_DIR/helpers/log.sh"
source "$SCRIPT_DIR/helpers/colors.sh"
source "$SCRIPT_DIR/helpers/telegram.sh"
source "$SCRIPT_DIR/helpers/functions.sh"

#**************************************************************
# ARE ALL DEPENCIES ALREADY INSTALLED OR NOT?
#**************************************************************

# Checking depencies
echo -e "${BOLD}Checking dependencies... ${NORMAL}"

DEPENDENCIES=("zip")
PKG_INSTALLED=""
PKG_NOT_INSTALLED=""

for i in "${DEPENDENCIES[@]}"; do
	if [[ ! $(dpkg-query -s $i 2>/dev/null) ]]; then
		echo -en "Installing package ${BYELLOW}${i}${NORMAL}... "
		if [[ $(sudo apt-get install -q -y ${i}q &>/dev/null) ]]; then
			echo -e "ok"
			PKG_INSTALLED="$PKG_INSTALLED ${BYELLOW}${i}${NORMAL}"
		else
			echo -e "not installed"
			PKG_NOT_INSTALLED="$PKG_NOT_INSTALLED ${BYELLOW}${i}${NORMAL}"
		fi
	fi
done

if [[ ! -z $PKG_INSTALLED ]]; then
	echo -e "Following packages has been installed:$PKG_INSTALLED"
fi

if [[ ! -z $PKG_NOT_INSTALLED ]]; then
	echo -e "Following packages not installed:$PKG_NOT_INSTALLED"
	echo -e "Please install not installed packages manually. Now terminating."
	exit 1
fi

#**************************************************************
# DISPLAY USER MENU
#**************************************************************

echo -e "Select a config to execute:"

ARRAY=$(find $SCRIPT_DIR/servers/ -maxdepth 1 -name "*.config" -print)
COUNTER=0

for i in $ARRAY
do
	. $i
	echo -e [$(( $COUNTER + 1 ))]${BWHITE}"\t"${BWHITE}$CONFIG_DESCRIPTION${NORMAL}
	(( COUNTER++ ))
done

while :; do
	echo -n "Enter config ID: "
	read -r ITEM

	# Validation & range check
	[[ $ITEM =~ ^[0-9]+$ ]] || { echo -e "${BRED}Enter a valid number${NORMAL}"; continue; }
	(( ITEM > 0 && ITEM <= $COUNTER)) || { echo -e "${BRED}Enter a number in the range from 0 to $COUNTER${NORMAL}"; continue; }

	break
done

(( ITEM-- ))
COUNTER=0
FILENAME=""

for i in $ARRAY
do
	if [[ $COUNTER == $ITEM ]]; then
		FILENAME=$i
		break
	fi
	(( COUNTER++ ))
done

# Include the settings file
. $FILENAME

#**************************************************************
# EXECUTE WORKERS
#**************************************************************

RESULT=""
I=0

if [[ $WORKER_DEMO == "yes" ]]; then
	. $SCRIPT_DIR/workers/demos/go.sh
	RESULT=$RESULT'['$((++I))'] Demo packing done. '$WORKER_RESULT'%0A'
fi

if [[ $WORKER_LOGS == "yes" ]]; then
	. $SCRIPT_DIR/workers/logs/go.sh
	RESULT=$RESULT'['$((++I))'] Logs trimming and packing done.'$WORKER_RESULT'%0A'
fi

send_to_telegram "$RESULT"