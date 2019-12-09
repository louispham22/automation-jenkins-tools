#!/bin/bash

if [ $# -lt 1 ]; then
	(>&2 echo "Usage: $(basename $0) <dnsgroup> <env> [<env> .. ]")
	exit 1
fi

IPVARPREFIX=${IPVARPREFIX:-IP_}
URLVARPREFIX=${URLVARPREFIX:-URL_}
DNSGROUP=$1
VARS=( ${@:2} )

IPVARS=$(echo ${VARS[*]} | tr '[:space:]' '\n' | grep -e "^${IPVARPREFIX}")
URLVARS=$(echo ${VARS[*]} | tr '[:space:]' '\n' | grep -e "^${URLVARPREFIX}")

IPS=($($(dirname $0)/get-available-ips.sh $DNSGROUP $(echo $IPVARS | wc -w))) || { echo "could not get ips" >&2; exit 1; }

cnt=0
for var in ${IPVARS[*]}; do
	echo "$var=${IPS[$cnt]}";
    export $var=${IPS[$cnt]}
	cnt=$(( $cnt + 1 ))
done

for var in ${URLVARS[*]}; do
    echo "$var=$(echo ${PDOCKER_URLGROUP}-${var#$URLVARPREFIX} | tr '[:upper:]_' '[:lower:]-')";
    export $var=$(echo ${PDOCKER_URLGROUP}-${var#$URLVARPREFIX} | tr '[:upper:]_' '[:lower:]-')
done

### Update DNS
echo "Updating DNS:" >&2
$(dirname $0)/update-dns.sh >&2
