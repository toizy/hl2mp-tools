#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	return
fi

INSTALL_PATH="$HOME/.config/systemd/user/"
UNITNAME="hl2mp-tools"
SERVICE_NAME="$INSTALL_PATH$UNITNAME.service"
TIMER_NAME="$INSTALL_PATH$UNITNAME.timer"
ARGUMENTS=""
WORKINGDIRECTORY="$SCRIPT_DIR"
USER=$(whoami)
FREQUENCY=""

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
	sed -i "s/%SCRIPT_PATH%/$SCRIPT_FULLNAME_FIXED/g" "$SERVICE_TARGET"
	sed -i "s/%ARGUMENTS%/$ARGUMENTS/g" "$SERVICE_TARGET"
	sed -i "s/%WORKINGDIRECTORY%/$WORKINGDIRECTORY_FIXED/g" "$SERVICE_TARGET"
	sed -i "s/%UNITNAME%/$UNITNAME/g" "$SERVICE_TARGET"
	sed -i "s/%FREQUENCY%/$FREQUENCY/g" "$TIMER_TARGET"
	sed -i "s/%UNITNAME%/$UNITNAME/g" "$TIMER_TARGET"
	# Move units to ~/.config/systemd/user/ directory
	echo -e "Moving unit files:"
	echo -e "  '$SERVICE_TARGET' > '$SERVICE_NAME'"
	if ! mv "$SERVICE_TARGET" "$SERVICE_NAME"; then
		echo -e "${RED}An error has occured while copying $SERVICE_TARGET to $SERVICE_NAME${NORMAL}"
	fi
	echo -e "  '$TIMER_TARGET' > '$TIMER_NAME'"
	if ! mv "$TIMER_TARGET" "$TIMER_NAME"; then
		echo -e "${RED}An error has occured while copying $TIMER_TARGET to $TIMER_NAME${NORMAL}"
	fi
	# Start timer
	echo -en "Starting $UNITNAME.timer... "
	if ! systemctl --user start "$UNITNAME.timer"; then
		echo -e "\n${RED}An error has occured while starting the timer${NORMAL}"
	else
		echo "Ok"
	fi
	# Enable timer
	echo -en "Enabling $UNITNAME.timer... "
	if ! systemctl --user enable "$UNITNAME.timer"; then
		echo -e "\n${RED}An error has occured while enablind the timer${NORMAL}"
	fi
	# Reload daemons
	echo -en "Reloading daemons... "
	if ! systemctl --user daemon-reload; then
		echo -e "\n${RED}An error has occured while reloading daemons${NORMAL}"
	else
		echo "Ok"
	fi
}>&1

function RemoveService() {
	echo -e "${BGRAY}--- Removing the service ---${NORMAL}"
	# Stop timer
	echo -n "Stopping the timer... "
	if ! systemctl --user stop "$UNITNAME.timer"; then
		echo -e "\n${RED}An error has occured while stopping the timer${NORMAL}"
	else
		echo "Ok"
	fi
	# Disable timer
	echo -n "Disabling the timer... "
	if ! systemctl --user disable "$UNITNAME.timer"; then
		echo -e "\n${RED}An error has occured while disabling the timer${NORMAL}"
	fi
	# Stop service
	echo -n "Stopping the service... "
	if ! systemctl --user stop "$UNITNAME.service"; then
		echo -e "\n${RED}An error has occured while stopping the service${NORMAL}"
	else
		echo "Ok"
	fi
	# Disable service
	echo -n "Disabling the service... "
	if ! systemctl --user disable "$UNITNAME.service"; then
		echo -e "\n${RED}An error has occured while disabling the service${NORMAL}"
	else
		echo "Ok"
	fi
	# Reload daemons
	echo -n "Reloadng daemons... "
	if ! systemctl --user daemon-reload; then
		echo -e "\n${RED}An error has occured while reloading daemons${NORMAL}"
	else
		echo "Ok"
	fi
	# Delete units
	echo "Deleting unit files:"
	if [[ -f "$SERVICE_NAME" ]]; then
		echo "  $SERVICE_NAME"

		if ! rm -f "$SERVICE_NAME"; then
			echo -e "${RED}An error has occured while deleting $SERVICE_NAME${NORMAL}"
		fi
	else
		echo "  $SERVICE_NAME - does not exists."
	fi
	if [[ -f "$TIMER_NAME" ]]; then
		echo "  $TIMER_NAME"
		
		if ! rm -f "$TIMER_NAME"; then
			echo -e "${RED}An error has occured while deleting $TIMER_NAME${NORMAL}"
		fi
	else
		echo "  $TIMER_NAME - does not exists."
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
	OUTPUT=$(systemctl --user status "$UNITNAME.timer" 2>/dev/null)
	if [[ ! $OUTPUT =~ " active " ]]; then
		RESULT=$RESULT"3"
	fi
	if [[ ! $OUTPUT =~ "; enabled; " ]]; then
		RESULT=$RESULT"4"
	fi
	echo $RESULT
}

# Check if ~/.config/systemd/user/ directory exists
echo -n "Checking the existence of the user's systemd service directory... "
if [[ ! -d $INSTALL_PATH ]]; then
	echo -en "\nDoes not exists, creating... "
	if ! mkdir -p" $INSTALL_PATH"; then
		echo -e "\n${RED}An error has occured while creating the directory $INSTALL_PATH ${NORMAL}. Terminating."
		return 1
	fi
	echo "Done."
else
	echo "Ok."
fi

# Check linger status for the user
echo "Current user: $USER"
echo -n "Lingering status for the user: "
LINGERING=$(ls /var/lib/systemd/linger)
if [[ $LINGERING =~ $USER ]]; then
	echo "Enabled"
else
	echo "Disabled"
	echo -n "Enabling user lingering for the user... "
	if ! loginctl enable-linger "$USER"; then
		echo -e "\n${RED}An error has occured while enabling lingering for the user $USER ${NORMAL}. Terminating."
		return 1
	fi
	echo "Done."
fi

# Get service and timer status
TIMER_STATUS=$(GetServiceStatus)
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
	ExecutionFrequency
	InstallService
elif [[ ${MENU_ITEMS[$ITEM]} == "$ITEM_REMOVE" ]]; then
	RemoveService
elif [[ ${MENU_ITEMS[$ITEM]} == "$ITEM_REINSTALL" ]]; then
	RemoveService
	BuildArguments
	ExecutionFrequency
	InstallService
fi