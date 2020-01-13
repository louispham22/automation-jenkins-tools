#!/bin/bash
set -e

if [ $# -lt 2 ]; then
	(>&2 echo "Usage: $(basename $0) <urlgroup> <config> [<config> .. ]")
	exit 1
fi

URLVARPREFIX=${URLVARPREFIX:-URL_}
GROUP=$1
CONFIGS=${@:2}

VARS=$(grep -hoe "\${${URLVARPREFIX}[^}]*}" $CONFIGS| grep -o '[^${}]*' | tr ' ' '\n' | sort | uniq );

for var in $VARS; do
	echo "$var=$(echo $GROUP-${var#$URLVARPREFIX} | tr '[:upper:]_' '[:lower:]-')";
done

