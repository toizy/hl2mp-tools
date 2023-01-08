# Additional fond properties
BOLD='\033[1m'
DBOLD='\033[2m'
NBOLD='\033[22m'
UNDERLINE='\033[4m'
NUNDERLINE='\033[4m'
BLINK='\033[5m'
NBLINK='\033[5m'
INVERSE='\033[7m'
NINVERSE='\033[7m'
BREAK='\033[m'
NORMAL='\033[0m'

# Font colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'

# Font colors (bold)
BDEF='\033[0;39m'
BGRAY='\033[1;30m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BMAGENTA='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

# Background colors
BGBLACK='\033[40m'
BGRED='\033[41m'
BGGREEN='\033[42m'
BGBROWN='\033[43m'
BGBLUE='\033[44m'
BGMAGENTA='\033[45m'
BGCYAN='\033[46m'
BGGRAY='\033[47m'
BGDEF='\033[49m'

reset_color(){
	tput sgr0
}