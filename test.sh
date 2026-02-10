#!/bin/bash


detect_init() {
    if [ -d /run/systemd/system ]; then
        echo "systemd"
    else
        echo "openrc"
    fi
}

INIT_SYSTEM=$(detect_init)
echo $INIT_SYSTEM
