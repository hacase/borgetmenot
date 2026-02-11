#!/bin/bash

set -e
set -o pipefail
set -E


#=============================
# Config file
#=============================

CONFIG_FILE="/usr/local/bin/borgetmenot/borgetmenot_fujin.conf"
source "$CONFIG_FILE"


#=============================
# Client
#=============================

#MACHINE_NAME="thinkerp50"
#MACHINE_USER="taroot"

#BORG_PASSFILE="/home/taroot/something/donthackmepls/borg/borgetmenot_thinkerp50.txt"
#BACKUP_DIR="/home/${MACHINE_USER}/borgetmenot_files"
mkdir -p $BACKUP_DIR


#=============================
# Server
#=============================

#SERVER_IP="192.168.178.224"
#SERVER_USER="taroot"
#SERVER_NAME="raijin"

#REPO_BASE_PATH="/mnt/data/ALLBACKUP/BORGETMENOT/repos"
#REPO_PATH="$REPO_BASE_PATH/${MACHINE_NAME}"


#=============================
# SSH
#=============================

export BORG_REPO="ssh://${SERVER_NAME}${REPO_PATH}"


#=============================
# Logfile
#=============================

#LOGDIR="/var/log/borgetmenot"
mkdir -p $LOGDIR
#LOGFILE="$LOGDIR/borgetmenot_${MACHINE_NAME}.log"
#MAX_LOG_SIZE_MB=50

#START_INFO="Start borgetmenot."
#EXIT_INFO="Exit borgetmenot."
#ERROR_INFO="somewhere only we know"
#ERROR_MSG=$ERROR_INFO


#=============================
# Notification
#=============================

#NOTIFY_EMAIL="tarowtb@pm.me"
#MSMTP_ACCOUNT="proton"
#NOTIFY_METHOD="both"

#DISK_THRESHOLD_WARN=80
#DISK_THRESHOLD_CRITICAL=95

#=============================
# Hook
#=============================

run_hooks() {
	local cmd="$1"

	if type -t "$cmd" >/dev/null 2>&1; then
		"$cmd"
		return ${PIPESTATUS[0]}
	else
		LOG INFO "I don't have any hooks."
	fi
}


#=============================
# Borg config
#=============================

#BACKUP_PATHS=(
#	"/home/"
#	"/etc"
#	"/usr/local"
#	"/opt"
#	"/var/lib/systemd"
#	"/var/lib/NetworkManager"
#)

#KEEP_WITHIN="6H"
#KEEP_HOURLY=24
#KEEP_DAILY=14
#KEEP_WEEKLY=5
#KEEP_MONTHLY=6


#=============================
# Functions
#=============================

# ==== Cleanup ==== #

cleanup() {
	set +e

	log INFO "Cleaning up..."

	if [[ $TEST_MODE == false ]]; then
		title 'Captain Hook leaving'
		run_hooks POST_HOOKS
	fi

	log INFO "Unsetting passcommand..."
	unset BORG_PASSCOMMAND

	log INFO "$EXIT_INFO"
}


error_exit() {
	export ERROR_MSG="${1:-$ERROR_INFO}"
	local exit_code="${2:-1}"

	log ERROR "$ERROR_MSG"

	error_exit_email

	cleanup

	exit "$exit_code"
}


error_exit_email() {
	local last_line=$(grep -n "${START_INFO}" "$LOGFILE" 2>/dev/null | tail -1 | cut -d: -f1)
	local log_excerpt=$(tail -n +${last_line:-1} "$LOGFILE" 2>/dev/null || echo "Log not available.")	

	local email_body="Backup FAILED!

Date:       $(date)
Machine:    ${MACHINE_NAME}
Mode:       ${MODE}
Unit:       ${UNIT_NAME}
Repository: ${BORG_REPO}
Error:      ${ERROR_MSG}

========= LOG =========

${log_excerpt}

======================="

	notify "Backup FAILED: ${MACHINE_NAME}" "$email_body" "critical"
}


trap 'error_exit "Script interrupted (SIGINT)." 130' INT
trap 'error_exit "Script terminated (SIGTERM)." 142' TERM
trap 'error_exit "Connection lost (SIGHUP)." 129' HUP
trap 'error_exit "Command failed at line $LINENO" $?' ERR

exec 2> >(tee -a "$LOGFILE")


# ==== Overall ==== #

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_ARGS="$*"

if [[ -n "${INVOCATION_ID:-}" ]]; then
	MODE="systemd"
	UNIT_NAME="$(systemctl show -p Id --value "$INVOCATION_ID" 2>/dev/null)"
else
	MODE="manual"
	UNIT_NAME="shell"
fi


TEST_MODE=false
[ "$1" = "--test" ] || [ "$1" = "-t" ] && TEST_MODE=true


title() {
	local msg="$1"
	local char="${2:-=}"

	local term_width=$(tput cols 2>/dev/null || echo 76)
	local log_width=40
	local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"


	if [ -t 1 ]; then
		printf '%*s\n' "$term_width" '' | tr ' ' "$char"
		printf "   %s\n" "$msg"
		printf '%*s\n' "$term_width" '' | tr ' ' "$char"
	fi


	{
		printf "$timestamp"
		printf '%*s\n' "$log_width" '' | tr ' ' "$char"
		printf "   %s\n" "$msg"
		printf '%*s\n' "$log_width" '' | tr ' ' "$char"
	} >> "$LOGFILE"
}


prebackup_check() {
	log INFO "Running pre-backup checks..."


	log INFO "Checking connection to $SERVER_NAME ($SERVER_IP)..."
	if ! ping -c 1 -W 5 "$SERVER_IP" &> /dev/null; then
		error_exit "Server $SERVER_IP not reachable."
	fi
	log INFO "Server reachable."


	log INFO "Testing SSH connection..."
	if ! ssh -o ConnectTimeout=5 ${SERVER_NAME} "echo OK" &> /dev/null; then
		error_exit "SSH connection failed."
	fi
	log INFO "SSH connection working."


	log INFO "Testing repository access..."
	if ! run_borg list &> /dev/null;then
		error_exit "Repository access failed."
	fi
	log INFO "Repository accessible."


	log INFO "Checking disk space on backup server..."
	local remote_usage=$(ssh $SERVER_NAME \
		"df /mnt/data | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "unknown")

	if [ "$remote_usage" != "unknown" ]; then
		log INFO "Backup server disk usage: ${remote_usage}%."
		if  [ "$remote_usage" -gt 80 ]; then
			log WARN "Backup server disk space critical: ${remote_usage}%."
		fi
	fi


	log INFO "Pre-backup checks completed."
}


# ==== Logging ==== #

log() {
	local level="${1:-INFO}"
	local msg="$2"
	local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"

	echo "${timestamp} ${level}: ${msg}"
	echo "${timestamp} ${level}: ${msg}" >> "$LOGFILE"
}


rotate_log() {
	if [ -f "$LOGFILE" ]; then
		local size_mb=$(du -m "$LOGFILE" 2>/dev/null | cut -f1)
		if [ "$size_mb" -gt "$MAX_LOG_SIZE_MB" ]; then
			log INFO "Log file size ${size_mb}MB exceeds ${MAX_LOG_SIZE_MB}MB, rotating..."
			mv "$LOGFILE" "$LOGFILE.$(date +%Y%m%d_%H%M%S)"
			# Keep last 5 old logs
			ls -t "${LOGFILE}".* 2>/dev/null | tail -n +6 | xargs -r rm -f
		fi
	fi
}


# ==== Notify ==== #

send_email() {
	log INFO "Sending notification via email..."

	local subject="$1"
	local body="$2"	
	local user_home=$(getent passwd "$MACHINE_USER" | cut -d: -f6)

	if ! command -v msmtp &> /dev/null; then
        	log WARN "msmtp is not installed."
        	return 1
	fi

	if [ ! -f "$user_home/.msmtprc" ]; then
        	log ERROR "$user_home/.msmtprc not found."
        	return 1
	fi


	if echo -e "Subject: ${subject}\n\n${body}" | \
		msmtp -C "$user_home/.msmtprc" -a "$MSMTP_ACCOUNT" "$NOTIFY_EMAIL" 2>&1 | tee -a "$LOGFILE"; then
		
		log INFO "Email notification sent to $NOTIFY_EMAIL."
		return 0
	else
		log WARN "Email notification failed."
		return 1
	fi
}


send_desktop() {
	log INFO "Sending notification to desktop..."

	local msg="$1"
	local urgency="${2:-normal}"

	if ! command -v notify-send &> /dev/null; then
		log WARN "ERROR: notify-send is not installed."
		return 1
	fi

	
	local real_user="${SUDO_USER:-$MACHINE_USER}"
	local real_user_id=$(id -u "$real_user" 2>/dev/null) || return 1
	local dbus_addr="unix:path=/run/user/${real_user_id}/bus"
	

	sudo -u "$real_user" \
		DBUS_SESSION_BUS_ADDRESS="$dbus_addr" \
		notify-send -u "$urgency" "borgetmenot: ${MACHINE_NAME}" "$msg" 2>/dev/null || true

	log INFO "Desktop notification sent."
}


notify() {
	log INFO "Sending notification: $NOTIFY_METHOD..."

	local subject="$1"
	local body="$2"
	local urgency="${3:-normal}"


	case "$NOTIFY_METHOD" in
		email)
			send_email "$subject" "$body"
			;;
		desktop)
			send_desktop "$body" "$urgency"
			;;
		both)
			send_email "$subject" "$body"
			send_desktop "$body" "$urgency"
			;;
		none)
			log INFO "Notification disabled."
			;;
	esac
}


run_borg() {
	local borg_base_cmd=()

	if command -v systemd-inhibit >/dev/null 2>&1; then
		borg_base_cmd+=(
			systemd-inhibit
			--what=sleep:idle
			--who="Borg Backup"
			--why="I wont let you sleep"
		)
	fi

	borg_base_cmd+=(
		borg
		--lock-wait 600
	)

	"${borg_base_cmd[@]}" "$@" 2>&1 | tee -a "$LOGFILE"
	return ${PIPESTATUS[0]}
}


#=============================
# Backup
#=============================

main () {
	rotate_log


	title "Starting backup at $(date)"

	log INFO "Backup started..."
	prebackup_check

	log INFO "Creating backup archive..."
	if ! run_borg create \
		--compression auto,lz4 \
		--stats \
		--exclude-caches \
		--checkpoint-interval 120 \
		::${MACHINE_NAME}_{now:%Y-%m-%d_%H-%M-%S} \
		"${BACKUP_PATHS[@]}" \
		\
		`# User data` \
		--exclude 'home/*/Downloads' \
		--exclude 'home/*/.cache' \
		--exclude 'home/*/.local/share/Trash' \
		--exclude '*/.snapshots' \
		--exclude '/.snapshots' \
		--exclude 'home/*/.snapshots' \
		\
		`# Python and other environments` \
		--exclude '**/venv' \
		--exclude '**/.venv' \
		--exclude '**/virtualvenv' \
		--exclude '**/.virtualvenv' \
		--exclude '**/env' \
		--exclude '**/__pycache__' \
		--exclude '*.pyc' \
		--exclude '*.pyo' \
		--exclude 'home/*/.local/lib/python*/site-packages' \
		--exclude 'home/*/.cache/pip' \
		--exclude 'home/*/micromamba' \
		--exclude 'home/*/.micromamba' \
		--exclude 'home/*/miniforge3' \
		--exclude 'home/*/.miniforge3' \
		--exclude 'home/*/.conda' \
		--exclude 'home/*/.mamba' \
		\
		`# applications` \
		--exclude 'home/*/.thunderbird' \
		--exclude 'home/*/.mozilla/firefox/*/cache2' \
		--exclude 'home/*/.config/chromium/*/Cache' \
		--exclude 'home/*/.config/Code/Cache' \
		--exclude 'home/*/.config/Code/CachedData' \
		\
		`# other` \
		--exclude 'home/*/.rustup' \
		--exclude 'home/*/.cargo/registry' \
		--exclude 'var/cache' \
		--exclude 'var/tmp' \
		--exclude 'tmp' \
		--exclude '*/node_modules' \
		--exclude '*.o' \
		--exclude '*.so' \
		--exclude '*.a'; then

		error_exit "Backup creation failed."
	fi
	title "Backup completed successfully at $(date)"
	log INFO "Backup created successfully."


	log INFO "Verifying latest backup integrity..."
	if ! run_borg check --last 1; then
		error_exit "Backup verification failed."
	fi	
	log INFO "Backup verification passed."


	log INFO "Pruning old backups..."
	if ! run_borg prune \
		--list \
		--stats \
		--keep-within "$KEEP_WITHIN" \
		--keep-hourly "$KEEP_HOURLY" \
		--keep-daily "$KEEP_DAILY" \
		--keep-weekly "$KEEP_WEEKLY" \
		--keep-monthly "$KEEP_MONTHLY"; then

		log WARN "Prune completed with warnings."
	else
		log INFO "Prune completed."
	fi


	if [ "$(date +%u)" -eq 7 ]; then
		if [ "$(date +%H)" -eq 12 ]; then
			log INFO "Sunday maintenance..."

			log INFO "Compacting repository..."
			if ! run_borg compact; then
				log WARN "Compact completed with warnings."
			else
				log INFO "Compact completed."
			fi


			log INFO "Running full integrity check (this may take a while)..."
			if ! run_borg check --verify-data; then
				error_exit "Full integrity check failed."
			fi
			log INFO "Full integrity check passed."
		fi
	fi
}


#=============================
# Test
#=============================


run_test() {
	title "Test mode at $(date)"

	TEST_DIR="/tmp/borg_test_${MACHINE_NAME}_$$"
	mkdir -p "$TEST_DIR"

	log INFO "Creating test files: $TEST_DIR..."
	for i in {1..100}; do
		dd if=/dev/urandom of="$TEST_DIR/test_file_${i}.bin" bs=1K count=$((RANDOM % 100 + 1)) 2>/dev/null

		echo "Test file ${i} created at $(date)" > "$TEST_DIR/test_file_${i}.txt"
		echo "Machine: ${MACHINE_NAME}" >> "$TEST_DIR/test_file_${i}.txt"
		echo "Random data: $(openssl rand -hex 32)" >> "$TEST_DIR/test_file_${i}.txt"
	done
	
	mkdir -p "$TEST_DIR/subdir1/subdir2/subdir3"
	for i in {1..20}; do
		dd if=/dev/urandom of="$TEST_DIR/subdir1/subdir2/subdir3/nested_${i}.bin" bs=1K count=50 2>/dev/null
	done
	log INFO "Created test files."


	log INFO "Testing notification..."
	if [ "$NOTIFY_METHOD" = "desktop" ] || [ "$NOTIFY_METHOD" = "both" ]; then
		if command -v notify-send &> /dev/null; then
			if ! send_desktop "TEST Desktop notification: ${MACHINE_NAME}" "normal"; then
				log WARN "Desktop notification test... FAILED"
			else
				log INFO "Desktop notification... OK"
			fi		
		else
			log WARN "notify-send not available, skipping desktop notification test."
		fi
	fi

	if command -v msmtp &> /dev/null; then
		local test_email_body="Backup test started on ${MACHINE_NAME}

Date: $(date)
Test directory: ${TEST_DIR}

Heyo, test email from ozaki via borgetmenot worked!"

		if ! send_email "Backup Test: ${MACHINE_NAME}" "$test_email_body"; then
			log WARN "Email notification test... FAILED"
		else
			log INFO "Email notification test... OK"
		fi
	else
		log WARN "msmtp not available, skipping email notification test."
	fi


	prebackup_check
	log INFO "Prebackup-Check... OK"


	log INFO "Creating test backup..."
	if ! run_borg create \
		--stats \
		--compression lz4 \
		::"${MACHINE_NAME}-TEST-{now:%Y-%m-%d_%H-%M-%S}" \
		"$TEST_DIR"; then

		rm -rf "$TEST_DIR"
		error_exit "Test backup creation... FAILED"
	fi
	log INFO "Test backup creation... OK"


	log INFO "Verifying test backup..."
	TEST_ARCHIVE=$(run_borg list 2>/dev/null | grep "${MACHINE_NAME}-TEST" | tail -1 | awk '{print $1}')

	if [ -z "$TEST_ARCHIVE" ]; then
		rm -rf "$TEST_DIR"
		log WARN "Test backup verification... FAILED"
		error_exit "Test backup not found in repository."
	fi
	log INFO "Test backup verified: $TEST_ARCHIVE"
	log INFO "Test backup verification... OK"


	log INFO "Cleaning up test backup from repository..."
	if run_borg delete ::"$TEST_ARCHIVE" 2>&1 | tee -a "$LOGFILE"; then
		log INFO "Test backup archive cleaned from repository."
	else
		log WARN "Failed to delete test archive."
	fi


	log INFO "Cleaning up test directory..."
	rm -rf "$TEST_DIR"

	if [ -d "$TEST_DIR" ]; then
		log WARN "Test directory still exists: $TEST_DIR"
	else
		log INFO "Test directory removed."
	fi


	log INFO "All tests passed at $(date)."

	log INFO "Check log file for details:"
	echo ""
	log INFO "   cat $LOGFILE"
	echo ""

	return 0
}


#=============================
# MAIN
#=============================

log INFO "$START_INFO"


# ==== Check ==== #

title "BORGETMENOT Backup for $MACHINE_NAME"

log INFO "Loaded $CONFIG_FILE."

if [ "$EUID" -ne 0 ]; then
	log ERROR "Please run as root."
	exit 1
fi


log INFO "Loading borg passphrase..."
if [ -f "$BORG_PASSFILE" ]; then
	export BORG_PASSCOMMAND="cat $BORG_PASSFILE"
	log INFO "Borg passphrase loaded."
else
	error_exit "Borg passphrase file $BORG_PASSFILE not found."
fi


log INFO "Mode: $MODE"
log INFO "Unit name: $UNIT_NAME"

# ==== Entry Point ==== #

if [ "$TEST_MODE" = true ]; then
	run_test
else
	title "Captain Hook is here"
	run_hooks PRE_HOOKS

	main
fi


cleanup


title "Exit backup"


#=============================
# Notification Desktop
#=============================

if [ "$NOTIFY_METHOD" = "desktop" ] || [ "$NOTIFY_METHOD" = "both" ]; then
	send_desktop "Backup completed successfully on $MACHINE_NAME at $(date)."
fi


exit 0
