#!/bin/bash

source "conf/borgetmenot_thinkerp50.conf"

echo "${MIRROR_PATH}"

if [[ -v MIRROR_PATH ]]; then
	echo set
	echo $MIRROR_PATH
else
	echo ih
fi
