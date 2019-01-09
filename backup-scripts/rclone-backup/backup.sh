# /bin/bash
# Backup script to any rclone remote
# Requires rclone to be configured and installed (checks are in place) 

set -u
VERSION="2.0"

# CONFIG #

# Name of server (leave it how it is to use the hostname of the server)
name="$(hostname)"

# Set your backup locations here (folders)
backup_locations=('/var/www' '/etc' '/home')

exclude=n # set to 'y' to enable exclusions
exclusions=('/var/www/somebigfolder' '/another/folder')

telegram=n # set to 'y' to enable telegram messages
telegram_chat_id=""
telegram_bot_token=""

pushover=n # set to 'y' to enable pushover messages
pushover_app_token=""
pushover_user_key=""

rclone_destination_name="b2" # the name of your rclone destination (viewable in .rclone.conf as [name] )

# END CONFIG #

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function send_message {
	echo "$1"
	if [ $telegram = "y" ]; then
		curl --header 'Content-Type: application/json' --data-binary '{"chat_id":"'"$telegram_chat_id"'","text":"<code>'"$1"'</code>","parse_mode":"html"}' --request POST https://api.telegram.org/bot${telegram_bot_token}/sendMessage >> /dev/null
	fi

  if [ $pushover = "y" ]; then
    curl -s --form-string "token=$pushover_app_token" --form-string "user=$pushover_user_key" --form-string "message=$1" https://api.pushover.net/1/messages.json >> /dev/null
  fi
}

function msg {
  echo -e "\e[38;5;3m# \e[38;5;80m$1 \e[38;5;3m> \e[38;5;82m$2\e[0m"
}

function msgred {
  echo -e "\e[38;5;3m#$RED $1 \e[38;5;3m> \e[38;5;82m$2\e[0m"
}

function pkgcheck {
  if [ $(dpkg-query -W -f='${Status}' $1 2>/dev/null | grep -c "ok installed") -eq 0 ];
  then
    msg "PKGCHECK" "Installing $1"
    apt-get install -y $1;
  fi
}

function redtext {
  echo -e "${RED}$1${NC}"
}
function greentext {
  echo -e "${GREEN}$1${NC}"
}

function install_rclone {
  msg "RCLONE INSTALL" "Installing rclone..."
  curl -O http://downloads.rclone.org/rclone-current-linux-amd64.zip
  unzip rclone-current-linux-amd64.zip
  cd rclone-*-linux-amd64
  cp rclone /usr/sbin/
  chown root:root /usr/sbin/rclone
  chmod 755 /usr/sbin/rclone
  mkdir -p /usr/local/share/man/man1
  cp rclone.1 /usr/local/share/man/man1/
  mandb 
  msg "RCLONE INSTALL" "Installed rclone."
  msg "RCLONE INSTALL" "If you don't already have a preexisting $(rclone config file) file, run 'rclone config'"
}

#Start script
if [[ $EUID -ne 0 ]]; then
   msgred "INFO" "You are not running this script as root; make sure you have access to all directories"
fi

rcloneexec=$(which rclone)

function check_rclone {
  if [ -z "$rcloneexec" ]; then
    msgred "FATAL" "rclone is not installed or not found"
    if [[ $EUID -ne 0 ]]; then
      msgred "FATAL" "Please install it and run again"
      msgred "FATAL" "Install here: http://rclone.org/install/"
      exit 1
    else
      msgred "FATAL" "Would you like to install it? (y/n)"
      read shouldinstall
      if [ "$shouldinstall" == "y" ]; then
        install_rclone

        rcloneexec=$(which rclone)
        check_rclone
      else
        msgred "FATAL" "Exiting"
        msgred "FATAL" "Install here: http://rclone.org/install/"
        exit 1
      fi
    fi
  else
    msg "INFO" "rclone executable found: $rcloneexec"
  fi
}

check_rclone

if [ -f ~/.config/rclone/rclone.conf ]; then
	msg "INFO" "rclone config found"
else
	echo ""
	msgred "FATAL" "No rclong config found - are you sure rclone is installed and initialized?"
	msgred "FATAL" "Sleeping for 6 seconds..."
	sleep 6
fi

msg "INFO" "Checking we have needed packages installed"
pkgcheck tar
echo ""
echo -e "${RED}tb-backup $VERSION${NC} - $(date)"
echo ""
msg "INFO" "Script starting"
echo ""

HOST=$name
TMPDIR="/tmp/tbbackup"
rm -r $TMPDIR
mkdir -p $TMPDIR
DATE=$(date +"%Y.%m.%d-%H:%M:%S")

send_message "[${name}] [$DATE] [BACKUP] [INFO] Starting backup"
msg "REMOTE" "Making needed folders..."
$rcloneexec mkdir ${rclone_destination_name}:/backup/$HOST/$DATE
msg "BACKUP" "Starting backups..."
msgred "WARN" "Please do not interrupt"
echo ""

excl_list=""
if [ $exclude == "y" ]; then
	msg "INFO" "Calculating exclusions..."
	for excl in "${exclusions[@]}"
	do
		excl_list="$excl_list --exclude=${excl} "
	done
fi

for loc in "${backup_locations[@]}"
do
  msg "BACKUP" "Starting backup $loc"

  # Generating name for the file
  echo "$loc" > .tbbackup_tmp
  sed -i 's/\//./g' .tbbackup_tmp
  if [ $loc == '/' ]
  then
    FILENAME="ROOT"
  else
    FILENAME=$(cat .tbbackup_tmp)
  fi
  rm .tbbackup_tmp
  TARNAME="$HOST-$DATE-$FILENAME.tar.gz"
  TARLOC="$TMPDIR/$TARNAME"

  echo "tar $excl_list -zcvf \"$TARLOC\" \"$loc\""
  tar $excl_list -zcvf "$TARLOC" "$loc"
  msg "BACKUP" "Tar'd $loc"
  msg "BACKUP" "Uploading $TARNAME"

  $rcloneexec --stats=10s --transfers=2 --checkers=15 move $TARLOC ${rclone_destination_name}:/backup/$HOST/$DATE
  msg "BACKUP" "Uploaded $TARNAME to remote: backup/$HOST/$DATE/$TARNAME"
done
echo ""
msg "INFO" "Script finished"
FINISH_DATE=$(date +"%Y.%m.%d-%H:%M:%S")

# Nicely formatting output list
OUT=$($rcloneexec ls ${rclone_destination_name}:/backup/$HOST/$DATE | awk '{print $2}' | awk '$1=$1' ORS=' ')

send_message "[${name}] [$FINISH_DATE] [BACKUP] [INFO] Finished backup: $OUT"

msg "CLEANUP" "Cleaning up temporary directories"
rm -r $TMPDIR
