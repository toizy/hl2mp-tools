#!/bin/bash

# Preventing direct script invocation
if [ ${0##*/} == ${BASH_SOURCE[0]##*/} ]; then 
    echo "WARNING"
    echo "This script is not meant to be executed directly!"
    echo "Use this script only by sourcing it."
    echo ""
    exit 1
fi

function send_to_telegram()
{
	if [[ -z $TELEGRAM_BOT_TOKEN || -z $TELEGRAM_CHATID ||\
		-z $TELEGRAM_USERID || -z $TELEGRAM_USERNAME ||\
		-z $CONFIG_DESCRIPTION ]]; then
		log "One or more of LOCAL_TELEGRAM* variables are not set. Terminating."
		exit 1
	fi
	local CR='%0A%0A'
	local GREETING='HL2DM-Tools report'
	local MSG='<a href="tg://user?id='$TELEGRAM_USERID'">@'$TELEGRAM_USERNAME'</a> <b>'$CONFIG_DESCRIPTION'</b>'$CR$GREETING$CR$*
	curl -s -o /dev/null \
	--data "parse_mode=HTML" \
	--data "text=$MSG" \
	--data "chat_id=$TELEGRAM_CHATID" \
	'https://api.telegram.org/bot'$TELEGRAM_BOT_TOKEN'/sendMessage'
}