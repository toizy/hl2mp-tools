#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	return
fi

INSTALL_PATH="/etc/systemd/system/"
UNITNAME="hl2mp-tools"
SERVICE_NAME="$INSTALL_PATH$UNITNAME.service"
TIMER_NAME="$INSTALL_PATH$UNITNAME.timer"
ARGUMENTS=""
WORKINGDIRECTORY="$SCRIPT_DIR"
USER=""
GROUP=""
FREQUENCY=""

if [[ ! -d $INSTALL_PATH ]]; then
	log_debug "Path $INSTALL_PATH does not exists. All the following steps will not be completed."
	return 1
fi

function ExecutionFrequency() {
	echo -e "${BGRAY}--- Frequency of execution ---${NORMAL}"
	local COUNT=4
	local INTERVALS=("hour" "day" "week" "month")
	local INTERVALS_STR=("hourly" "dayly" "weekly" "monthly")
	echo "Select the frequency of execution: "
	echo -e "1. ${BWHITE}Hourly${NORMAL}"
	echo -e "2. ${BWHITE}Daily${NORMAL}"
	echo -e "3. ${BWHITE}Weekly${NORMAL}"
	echo -e "4. ${BWHITE}Monthly${NORMAL}"
	while :; do
		read -r ANSWER
		# Validation & range check
		[[ $ANSWER =~ ^[0-9]+$ ]] || { echo -en "${BRED}Enter a valid number${NORMAL}: "; continue; }
		(( ANSWER > 0 && ANSWER <= COUNT )) || { echo -en "${BRED}Enter a number in the range from 1 to $COUNT: ${NORMAL}"; continue; }
		(( ANSWER-- ))
		echo -n "The service will start every ${INTERVALS[$ANSWER]}. Is it ok? "
		read -r ANSWER
		ANSWER=${ANSWER^^}
		if [[ $ANSWER == "Y" || $ANSWER == "" ]]; then
			FREQUENCY=${INTERVALS_STR[$ANSWER]}
			break
		fi
	done
}

function BuildArguments() {
	echo -e "${BGRAY}--- Command line arguments ---${NORMAL}"
	while :; do
		echo -n "Enter command line arguments for run.sh (or leave it empty): "
		read -r ARGUMENTS
		echo -n "Is this correct? '$ARGUMENTS' "
		read -r ANSWER
		ANSWER=${ANSWER^^}
		if [[ $ANSWER == "Y" || $ANSWER == "" ]]; then
			break
		fi
	done
}

function BuildUserAndGroup() {
	echo -e "${BGRAY}--- User and group ---${NORMAL}"
	while :; do
		echo -n "Enter user and group like admin:main (or leave it empty): "
		read -r USERANDGROUP
		USER=${USERANDGROUP%%:*}
		GROUP=${USERANDGROUP##*:}
		echo -n "Is this correct? USER: '$USER' GROUP: '$GROUP'"
		read -r ANSWER
		ANSWER=${ANSWER^^}
		if [[ $ANSWER == "Y" || $ANSWER == "" ]]; then
			break
		fi
	done
}

function InstallService() {
	echo -e "${BGRAY}--- Installing the service ---${NORMAL}"
	#TODO more echo messages!
	# Local unit names
	local SERVICE_TARGET="$SCRIPT_DIR/install-service/systemd-service"
	local TIMER_TARGET="$SCRIPT_DIR/install-service/systemd-timer"
	# Copy templates to local units
	cp "$SCRIPT_DIR/install-service/template.service" "$SERVICE_TARGET"
	cp "$SCRIPT_DIR/install-service/template.timer" "$TIMER_TARGET"
	# Replace placeholders in the local units
	SCRIPT_FULLNAME_FIXED="${SCRIPT_FULLNAME//\//\\/}"
	WORKINGDIRECTORY_FIXED="${WORKINGDIRECTORY//\//\\/}"
	echo $SCRIPT_FULLNAME - $SCRIPT_FULLNAME_FIXED
	echo $WORKINGDIRECTORY - $WORKINGDIRECTORY_FIXED
	sed -i "s/%SCRIPT_PATH%/$SCRIPT_FULLNAME_FIXED/g" "$SERVICE_TARGET"
	sed -i "s/%ARGUMENTS%/$ARGUMENTS/g" "$SERVICE_TARGET"
	sed -i "s/%WORKINGDIRECTORY%/$WORKINGDIRECTORY_FIXED/g" "$SERVICE_TARGET"
	sed -i "s/%UNITNAME%/$UNITNAME/g" "$SERVICE_TARGET"
	sed -i "s/%FREQUENCY%/$FREQUENCY/g" "$TIMER_TARGET"
	sed -i "s/%UNITNAME%/$UNITNAME/g" "$TIMER_TARGET"
	# Move units to /etc/systemd/system/ directory
	echo -e "Moving unit files:"
	echo -e "  '$SERVICE_TARGET' > '$SERVICE_NAME'"
	if ! mv "$SERVICE_TARGET" "$SERVICE_NAME"; then
		echo -e "${RED}An error has occured while making symlink to $SERVICE_NAME from $SERVICE_TARGET${NORMAL}"
	fi
	echo -e "  '$TIMER_TARGET' > '$TIMER_NAME'"
	if ! mv "$TIMER_TARGET" "$TIMER_NAME"; then
		echo -e "${RED}An error has occured while making symlink to $TIMER_NAME from $TIMER_TARGET${NORMAL}"
	fi
	# Start timer
	echo -e "Starting $UNITNAME.timer"
	if ! systemctl start "$UNITNAME.timer"; then
		echo -e "${RED}An error has occured while starting the timer${NORMAL}"
	fi
	# Enable timer
	echo -e "Enabling $UNITNAME.timer"
	if ! systemctl enable "$UNITNAME.timer"; then
		echo -e "${RED}An error has occured while enablind the timer${NORMAL}"
	fi
	# Reload daemons
	echo -e "Reloading daemons"
	if ! systemctl daemon-reload; then
		echo -e "${RED}An error has occured while reloading daemons${NORMAL}"
	fi
}>&1

function RemoveService() {
	echo -e "${BGRAY}--- Removing the service ---${NORMAL}"
	# Stop timer
	echo "Stopping the timer"
	if ! systemctl stop "$UNITNAME.timer"; then
		echo -e "${RED}An error has occured while stopping the timer${NORMAL}"
	fi
	# Disable timer
	echo "Disabling the timer"
	if ! systemctl disable "$UNITNAME.timer"; then
		echo -e "${RED}An error has occured while disabling the timer${NORMAL}"
	fi
	# Stop service
	echo "Stopping the service"
	if ! systemctl stop "$UNITNAME.service"; then
		echo -e "${RED}An error has occured while stopping the service${NORMAL}"
	fi
	# Disable service
	echo "Disabling the service"
	
	if ! systemctl disable "$UNITNAME.service"; then
		echo -e "${RED}An error has occured while disabling the service${NORMAL}"
	fi
	# Reload daemons
	echo "Reloadng daemons"
	if ! systemctl daemon-reload; then
		echo -e "${RED}An error has occured while reloading daemons${NORMAL}"
	fi
	# Delete units
	echo "Deleting unit files:"
	if [[ -f "$SERVICE_NAME" ]]; then
		echo "  $SERVICE_NAME"
		if ! rm -f "$SERVICE_NAME"; then
			echo -e "${RED}An error has occured while deleting $SERVICE_NAME${NORMAL}"
		fi
	fi
	if [[ -f "$TIMER_NAME" ]]; then
		echo "  $TIMER_NAME"
		
		if ! rm -f "$TIMER_NAME"; then
			echo -e "${RED}An error has occured while deleting $TIMER_NAME${NORMAL}"
		fi
	fi
}>&1

function GetServiceStatus() {
	RESULT=""
	if [[ ! -f $SERVICE_NAME ]]; then
		RESULT=$RESULT"1"
	fi
	if [[ ! -f $TIMER_NAME ]]; then
		RESULT=$RESULT"2"
	fi
	OUTPUT=$(systemctl status "$UNITNAME.timer")
	if [[ ! $OUTPUT =~ " active " ]]; then
		RESULT=$RESULT"3"
	fi
	if [[ ! $OUTPUT =~ "; enabled; " ]]; then
		RESULT=$RESULT"4"
	fi
	echo $RESULT
}

# Get service and timer status
TIMER_STATUS=$(GetServiceStatus)
echo "$TIMER_STATUS"
echo -e "${BGRAY}--- Current status of hl2mp-tools timer ---${NORMAL}"
echo -en "Service unit: "
if [[ $TIMER_STATUS =~ "1" ]]; then
	echo -e "\t${BRED}Not exists${NORMAL}"
else
	echo -e "\t${BGREEN}Exists${NORMAL}"
fi
echo -en "Timer unit: "
if [[ $TIMER_STATUS =~ "2" ]]; then
	echo -e "\t${BRED}Not exists${NORMAL}"
else
	echo -e "\t${BGREEN}Exists${NORMAL}"
fi
echo -en "Timer activity: "
if [[ $TIMER_STATUS =~ "3" ]]; then
	echo -e "${BRED}Not active${NORMAL}"
else
	echo -e "${BGREEN}Active${NORMAL}"
fi
echo -en "Timer enabled: "
if [[ $TIMER_STATUS =~ "4" ]]; then
	echo -e "\t${BRED}No${NORMAL}"
else
	echo -e "\t${BGREEN}Yes${NORMAL}"
fi

ITEM_INSTALL="Install the service"
ITEM_REMOVE="Remove the service"
ITEM_REINSTALL="Reinstall the service"

MENU_ITEMS=()

# Inform the user
if [[ $TIMER_STATUS != "" ]]; then
	if [[ $TIMER_STATUS != "1234" ]]; then
		echo -e "The timer is configured incorrectly."
		MENU_ITEMS+=("$ITEM_REINSTALL")
		MENU_ITEMS+=("$ITEM_REMOVE")
	else
		echo -e "The timer is not configured."
		MENU_ITEMS+=("$ITEM_INSTALL")
	fi
else
	echo -e "The timer is properly configured and active."
	MENU_ITEMS+=("$ITEM_REINSTALL")
	MENU_ITEMS+=("$ITEM_REMOVE")
fi

# Build menu
COUNT=${#MENU_ITEMS[@]}
for (( I=0; I<COUNT; I++ ))
do
	echo -e "[$(( I + 1 ))]\t${BWHITE}${MENU_ITEMS[I]}${NORMAL}"
done

echo -en "Select an option: "

while :; do
	read -r ITEM
	# Check input bounds
	CHECK=$(check_input "$ITEM" "1" "$COUNT")
	if [[ $CHECK == "" ]]; then
		break
	fi
done

(( ITEM-- ))

if [[ ${MENU_ITEMS[$ITEM]} == "$ITEM_INSTALL" ]]; then
	BuildArguments
	BuildUserAndGroup
	ExecutionFrequency
	InstallService
elif [[ ${MENU_ITEMS[$ITEM]} == "$ITEM_REMOVE" ]]; then
	RemoveService
elif [[ ${MENU_ITEMS[$ITEM]} == "$ITEM_REINSTALL" ]]; then
	RemoveService
	BuildArguments
	BuildUserAndGroup
	ExecutionFrequency
	InstallService
fi