#!/bin/bash

docker_manager() {
        local action="$1"

        if [[ "$action" == "stop" ]]; then
                export DOCKER_ID_NAME="$(docker ps --format "{{.ID}}:{{.Names}}")"
                local sentence="Stopping"
        else
                local sentence="Starting"
        fi

        if [[ -n "$DOCKER_ID_NAME" ]]; then
                log INFO "$sentence Docker container..."

                for d in $DOCKER_ID_NAME; do
                        local d_id=$(echo $d | cut -d: -f1)
                        local d_name=$(echo $d | cut -d: -f2)

                        log INFO "$d_name ($d_id)..."
                        docker "$action" "$d_id"
                done
        fi
}

init_saver() {
        log INFO "Saving init system & tools..."

        log INFO "Saving kernel parameters..."
        cat /proc/cmdline > ${BACKUP_DIR}/cmdline.txt

        if [[ -d /run/systemd/system ]]; then
                log INFO "Systemd detected."

                log INFO "Saving enabled services..."
                systemctl list-unit-files --state=enabled > ${BACKUP_DIR}/enabled_services.txt

                log INFO "Saving mkinitcpio.conf..."
                cat /etc/mkinitcpio.conf > ${BACKUP_DIR}/mkinitcpio.txt

        elif [[ -d /run/openrc ]] || [[ -x /sbin/openrc-run ]]; then
                log INFO "OpenRC detected."

                log INFO "Saving enabled services..."
                rc-update show > ${BACKUP_DIR}/enabled_services.txt

                log INFO "Saving mkinitfs.conf..."
                cat /etc/mkinitfs/mkinitfs.conf > ${BACKUP_DIR}/mkinitfs.txt
        else
                echo "Unknown PID1, nothing saved."
        fi
}

