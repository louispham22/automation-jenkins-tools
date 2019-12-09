#!/bin/bash
if [ $# -lt 2 ]; then
	(>&2 echo "Usage: $(basename $0) <dnsgroup> <config> [<config> .. ]")
	exit 1
fi

IPVARPREFIX=${IPVARPREFIX:-IP_}
DNSGROUP=$1
CONFIGS=( ${@:2} )

VARS=$(grep -ohe "\${${IPVARPREFIX}[^}]*}" ${CONFIGS[*]}| grep -o '[^${}]*' | tr ' ' '\n' | sort | uniq );
IPS=($($(dirname $0)/get-available-ips.sh $DNSGROUP $(echo $VARS | wc -w))) || { echo "could not get ips"; exit 1; }

cnt=0
for var in $VARS; do
	echo "$var=${IPS[$cnt]}";
	cnt=$(( $cnt + 1 ))
done


