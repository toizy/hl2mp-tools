#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	return
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run on behalf of the superuser." 
    exit 1
fi

INSTALL_PATH="/etc/systemd/system/"
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
    local SYSTEM_SERVICE_PATH="/etc/systemd/system/$UNITNAME.service"
    local SYSTEM_TIMER_PATH="/etc/systemd/system/$UNITNAME.timer"
    # Copy templates to system units directory
    sudo cp "$SCRIPT_DIR/install-service/template.service" "$SERVICE_TARGET"
    sudo cp "$SCRIPT_DIR/install-service/template.timer" "$TIMER_TARGET"
    # Replace placeholders in the system units
    SCRIPT_FULLNAME_FIXED="${SCRIPT_FULLNAME//\//\\/}"
    WORKINGDIRECTORY_FIXED="${WORKINGDIRECTORY//\//\\/}"
    sudo sed -i "s/%SCRIPT_PATH%/$SCRIPT_FULLNAME_FIXED/g" "$SERVICE_TARGET"
    sudo sed -i "s/%ARGUMENTS%/$ARGUMENTS/g" "$SERVICE_TARGET"
    sudo sed -i "s/%WORKINGDIRECTORY%/$WORKINGDIRECTORY_FIXED/g" "$SERVICE_TARGET"
    sudo sed -i "s/%UNITNAME%/$UNITNAME/g" "$SERVICE_TARGET"
    sudo sed -i "s/%FREQUENCY%/$FREQUENCY/g" "$TIMER_TARGET"
    sudo sed -i "s/%UNITNAME%/$UNITNAME/g" "$TIMER_TARGET"
    # Move units to system directory
    echo -e "Moving unit files:"
    echo -e "  '$SERVICE_TARGET' > '$SYSTEM_SERVICE_PATH'"
    if ! sudo mv "$SERVICE_TARGET" "$SYSTEM_SERVICE_PATH"; then
        echo -e "${RED}An error has occurred while copying $SERVICE_TARGET to $SYSTEM_SERVICE_PATH${NORMAL}"
    fi
    echo -e "  '$TIMER_TARGET' > '$SYSTEM_TIMER_PATH'"
    if ! sudo mv "$TIMER_TARGET" "$SYSTEM_TIMER_PATH"; then
        echo -e "${RED}An error has occurred while copying $TIMER_TARGET to $SYSTEM_TIMER_PATH${NORMAL}"
    fi
    # Start timer
    echo -en "Starting $UNITNAME.timer... "
    if ! sudo systemctl start "$UNITNAME.timer"; then
        echo -e "\n${RED}An error has occurred while starting the timer${NORMAL}"
    else
        echo "Ok"
    fi
    # Enable timer
    echo -en "Enabling $UNITNAME.timer... "
    if ! sudo systemctl enable "$UNITNAME.timer"; then
        echo -e "\n${RED}An error has occurred while enabling the timer${NORMAL}"
    fi
    # Reload daemons
    echo -en "Reloading daemons... "
    if ! sudo systemctl daemon-reload; then
        echo -e "\n${RED}An error has occurred while reloading daemons${NORMAL}"
    else
        echo "Ok"
    fi
}>&1

function RemoveService() {
    echo -e "${BGRAY}--- Removing the service ---${NORMAL}"
    # Stop timer
    echo -n "Stopping the timer... "
    if ! sudo systemctl stop "$UNITNAME.timer"; then
        echo -e "\n${RED}An error has occurred while stopping the timer${NORMAL}"
    else
        echo "Ok"
    fi
    # Disable timer
    echo -n "Disabling the timer... "
    if ! sudo systemctl disable "$UNITNAME.timer"; then
        echo -e "\n${RED}An error has occurred while disabling the timer${NORMAL}"
    fi
    # Stop service
    echo -n "Stopping the service... "
    if ! sudo systemctl stop "$UNITNAME.service"; then
        echo -e "\n${RED}An error has occurred while stopping the service${NORMAL}"
    else
        echo "Ok"
    fi
    # Disable service
    echo -n "Disabling the service... "
    if ! sudo systemctl disable "$UNITNAME.service"; then
        echo -e "\n${RED}An error has occurred while disabling the service${NORMAL}"
    else
        echo "Ok"
    fi
    # Reload daemons
    echo -n "Reloading daemons... "
    if ! sudo systemctl daemon-reload; then
        echo -e "\n${RED}An error has occurred while reloading daemons${NORMAL}"
    else
        echo "Ok"
    fi
    # Delete units
    echo "Deleting unit files:"
    if [[ -f "$SYSTEM_SERVICE_PATH" ]]; then
        echo "  $SYSTEM_SERVICE_PATH"
        if ! sudo rm -f "$SYSTEM_SERVICE_PATH"; then
            echo -e "${RED}An error has occurred while deleting $SYSTEM_SERVICE_PATH${NORMAL}"
        fi
    else
        echo "  $SYSTEM_SERVICE_PATH - does not exist."
    fi
    if [[ -f "$SYSTEM_TIMER_PATH" ]]; then
        echo "  $SYSTEM_TIMER_PATH"
        if ! sudo rm -f "$SYSTEM_TIMER_PATH"; then
            echo -e "${RED}An error has occurred while deleting $SYSTEM_TIMER_PATH${NORMAL}"
        fi
    else
        echo "  $SYSTEM_TIMER_PATH - does not exist."
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