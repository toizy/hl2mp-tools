#!/bin/bash

if [[ -z $IS_ACTIVE ]]; then
	exit
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