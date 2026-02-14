#!/bin/bash



docker_manager() {
        local action="$1"
        local state_file="/tmp/borgetmenot_docker.state"

        if ! command -v docker &> /dev/null; then
                log WARN "Docker command not found."
        return 0
        fi

        if [[ "$action" == "stop" ]]; then
                local docker_id_name=$(docker ps --format "{{.ID}}:{{.Names}}")
                if [[ -z "$docker_id_name" ]]; then
                        log INFO "No running Docker containers to stop."
                        touch "$state_file"
                        return 0
                fi

                local sentence="Stopping"
                echo "$docker_id_name" > "$state_file"

        elif [[ "$action" == "start" ]]; then
                if [[ ! -f "$state_file" ]]; then
                        log WARN "No state file found at $state_file. No Docker container to start."
                        return 0
                fi

                local sentence="Starting"
        fi

        while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local d_id=$(echo "$line" | cut -d: -f1)
                local d_name=$(echo "$line" | cut -d: -f2)

                log INFO "$sentence Docker container: $d_name ($d_id)..."
                docker "$action" "$d_id" > /dev/null
        done < "$state_file"

        if [[ "$action" == "start" ]]; then
                rm "$state_file"
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

