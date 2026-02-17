#!/bin/bash

set -e
set -o pipefail
set -E


read -e -p "Enter config file path: " CONFIG_FILE

if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Configuration file '$CONFIG_FILE' not found."
	exit 1
fi


echo "Loading configuration from $CONFIG_FILE..."
source "$CONFIG_FILE"
echo "Config file loaded."


echo "Setting up..."

export BORG_REPO="ssh://${SERVER_NAME}${REPO_PATH}"
export BORG_PASSCOMMAND="cat $BORG_PASSFILE"

echo "Done."


echo "Enter borg arguments"
read -e -p "borg " BORG_ARGS


echo "Executing borg command..."

borg $BORG_ARGS
