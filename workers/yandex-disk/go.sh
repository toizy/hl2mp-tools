#!/bin/bash

# shellcheck disable=SC1091
. "$SCRIPT_DIR/workers/yandex-disk/include/functions.sh"

# Reset WORKER_RESULT var
WORKER_RESULT=""

log "Starting Yandex.Disk job."

# Массив токенов
#
# https://yandex.ru/dev/id/doc/ru/concepts/ya-oauth-intro
#
# 1. Заходим на https://oauth.yandex.ru/client/new
#   - Создать приложение
#   - Redirect URI (нажимаем на поле, выбираем "Подставить URI для отладки")
#   - Название приложения (например, hl2mp-tools). На диске появится папка с тем же именем в папке "Приложения".
#   - Выбираем значок (.bmp, .png, .jpg, НЕ .ico)
#   - Отмечаем "Вебсервисы"
#   - В поле "Доступ к данным" выбираем доступ к адресу электронной почты
#   - В поле "Доступ к данным" вводим "cloud_api:" и выбираем "Доступ к папке приложения" и "Доступ к информации о диске"
#   - В поле "Почта для связи" вводим свою почту
# Создаём приложение
# Далее копируем Client ID и подставляем в ссылку https://oauth.yandex.ru/authorize?response_type=token&client_id=ID, входим под своим аккаунтом
# и получаем токен, который копируем и вставляем ниже. Код выдаётся минимум на год, если перестанет работать, то получаем новый и правим скрипт.
# Обращаем внимание на пробел в после каждого элемента, он обязателен!
TOKENS=()
EMAIL=""

# Assign tokens
# shellcheck disable=SC2206
TOKENS=( ${YD[TOKENS]} )

# Shuffle the array of tokens
# shellcheck disable=SC2207
TOKENS=( $(shuf -e "${TOKENS[@]}") )

# Get random token from $TOKENS array
TOKENS_LEN="${#TOKENS[@]}"
YD_INTERNAL_TOKEN=${TOKENS[$CURRENT_TOKEN]}

ALL_DONE=false
CURRENT_TOKEN=0
for (( I=0; I<TOKENS_LEN; I++ ))
do
	# shellcheck disable=SC2034
	YD_INTERNAL_TOKEN="${TOKENS[$I]}"
	# Get user email
	EMAIL=$(GetEmail)
	log "===============================	"
	log "Account $EMAIL selected."
	DiskCleanUp
	if IsDiskLowSpaced; then
		log "There's still not enough free space on Yandex.Disk (account $EMAIL). Moving on to the next token."
		continue
	else
		ALL_DONE=true
		break
	fi
done

if [[ $ALL_DONE == false ]]; then
	echo "Couldn't clear enough space. Check your Yandex.Disk."
	return 1
fi

log "Cleaning is successfully completed."

# Creating a directory in the app path
if [[ -n $REMOTE_BASE_PATH ]]; then
	RESULT=$(CreateDir "$REMOTE_BASE_PATH")
	if [[ $RESULT != "OK" ]]; then
		EchoLogger "An error occurred during the 'CreateDir' function call: $RESULT"
		EchoLogger "Terminating."
		return 1
	fi
fi

# Creating root directories in the app folder
DTFNAME=$(date +"%d-%m-%Y %H:%M")
CreateDir "${YD[APP_FOLDER]}" > /dev/null
CreateDir "${YD[APP_FOLDER]}/${DTFNAME}" > /dev/null

# Building list of files to upload
CMD_RESULT=$(find "$PACKED_DIR" -regextype posix-egrep -regex "${YD[UPLOAD_TYPES]}" -print)
FILES_COUNT=$(wc -l <<< "$CMD_RESULT")
COUNTER=0
for I in $CMD_RESULT
do
	# Имя файла без пути
	LOCALFILENAME="${I}"
	REMOTEFILENAME="${LOCALFILENAME//$PACKED_DIR/}"
	REMOTEFILENAME="${YD[APP_FOLDER]}/${DTFNAME}${REMOTEFILENAME}"

	# Just an additional check for a double slash (due to a possible user input error)
	if [[ $REMOTEFILENAME =~ ([/]{2,2}) ]]; then
		REMOTEFILENAME=${REMOTEFILENAME//\/\//}
	fi

	if [[ -d "$LOCALFILENAME" ]]; then
		echo "Creating directory $REMOTEFILENAME"
		CreateDir "$REMOTEFILENAME" > /dev/null
	else
		logn "Uploading $REMOTEFILENAME ... "
		if UploadFile "$LOCALFILENAME" "$REMOTEFILENAME"; then
			log " -> Ok"
			COUNTER=$(( COUNTER + 1 ))
		else
			log " -> Failed"
		fi
	fi
done

WORKER_RESULT="$WORKER_RESULT $FILES_COUNT items were processed, $COUNTER uploaded."

log "Yandex.Disk job finished."