#!/bin/bash

set -e
set -o pipefail
set -E

echo ""
CONFIG_FILE="/usr/local/bin/borgetmenot/conf/borgetmenot_$(hostname).conf"
echo $CONFIG_FILE

read -r -p "Enter config file (y/N): " CHANGE_CONFIG
if [[ "$CHANGE_CONFIG" =~ ^[yY]$ ]]; then
	read -e -p "Enter config file path: " NEW_CONFIG
	export CONFIG_FILE="$NEW_CONFIG"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "Error: Configuration file '$CONFIG_FILE' not found."
	exit 1
fi

echo ""

echo "Loading configuration from $CONFIG_FILE..."
source "$CONFIG_FILE"
echo "Config file loaded."


echo "Setting up..."

export BORG_REPO="ssh://${SERVER_NAME}${REPO_PATH}"
export BORG_PASSCOMMAND="cat $BORG_PASSFILE"

echo "Done."

echo ""

echo $REPO_PATH
read -r -p "Enter borg repo (y/N): " CHANGE_REPO
if [[ "$CHANGE_REPO" =~ ^[Yy]$ ]]; then
	read -r -p "Enter repo path: " NEW_PATH
	export BORG_REPO="$NEW_PATH"
fi

echo ""

echo "Enter borg arguments"
read -e -p "borg " BORG_ARGS


echo "Executing borg command..."

borg $BORG_ARGS
