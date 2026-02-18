#!/bin/bash

set -e
set -o pipefail
set -E


MACHINE_NAME="raijin"
MACHINE_USER="taroot"

NOTIFY_EMAIL="tarowtb@pm.me"
MSMTP_ACCOUNT="gmail"

REPO_ALLBACKUP="/mnt/data/ALLBACKUP"
REPO_DIR="${REPO_ALLBACKUP}/BORGETMENOT/repos"

MIRROR_BASE="/mnt/IMGREEN"
MIRROR_ALLBACKUP="${MIRROR_BASE}/ALLBACKUP"
MIRROR_DIR="${MIRROR_ALLBACKUP}/BORGETMENOT/repos"

LOGFILE="/var/log/borgetmenot/borgetmenot_${MACHINE_NAME}.log"
mkdir -p "$(dirname "$LOGFILE")"
MAX_LOG_SIZE_MB=50

ERROR_INFO="somewhere only we know"

START_INFO="Initiate mirroring ALLBACKUP..."
END_INFO="Exit mirroring ALLBACKUP."


SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_ARGS=("$@")

if [[ -n ${INVOCATION_ID:-} ]]; then
        MODE="systemd"
        UNIT_NAME="$(systemctl show -p ID --value "$INVOCATION_ID" 2>/dev/null || echo unknown)"
elif [[ -n ${CRON_PID:-} ]]; then
        MODE="cron"
        UNIT_NAME="cron"
elif [[ -n ${RC_SVCNAME:-} ]]; then
        MODE="openrc"
        UNIT_NAME="$RC_SVCNAME"
else
        MODE="manual"
        UNIT_NAME="shell"
fi


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


error_exit() {
        export ERROR_MSG="${1:-$ERROR_INFO}"
        local exit_code="${2:-1}"

        log ERROR "$ERROR_MSG"

        error_exit_email

        exit "$exit_code"
}

trap 'error_exit "Command failed at line $LINENO" $?' ERR


error_exit_email() {
        local last_line=$(grep -n "${START_INFO}" "$LOGFILE" 2>/dev/null | tail -1 | cut -d: -f1)
        local log_excerpt=$(tail -n +${last_line:-1} "$LOGFILE" 2>/dev/null || echo "Log not available.")

        local email_body="Mirror FAILED!

Date:       $(date)
Machine:    ${MACHINE_NAME}
Mode:       ${MODE}
Unit:       ${UNIT_NAME}
Error:      ${ERROR_MSG}

========= LOG =========

${log_excerpt}

======================="

        send_email "Mirror FAILED: ${MACHINE_NAME}" "$email_body"
}


rotate_log

title "MIRROR"
log INFO "${START_INFO}"

log INFO "Date: $(date)"
log INFO "Machine: ${MACHINE_NAME}"
log INFO "Mode: ${MODE}"
log INFO "Unit name: ${UNIT_NAME}"


all_idle=true

set +e
for repo in "$REPO_DIR"/*; do
        if [[ ! -d "$repo" ]]; then
                continue
        fi

        repo_name=$(basename "$repo")

        if borg with-lock "$repo" --lock-wait 0 -- true; then
                log INFO "$repo_name is idle"
        else
                log INFO "$repo_name is not idle"
                all_idle=false
        fi
done
set -e


if $all_idle; then
        log INFO "All repos are idle."
        log INFO "Running rsync..."

        rsync -aHAx \
                --numeric-ids \
                --delete \
                --delete-delay \
                --stats \
                --human-readable \
                --exclude 'lock.*' \
                "${REPO_ALLBACKUP}" "${MIRROR_BASE}" 2>&1 | tee -a "$LOGFILE"
else
        log INFO "At least one repo is busy."
fi


log INFO "${END_INFO}"
title "END MIRROR"

