#!/bin/bash
#
# Get Available IPs for a dynamic grouping
#
# Usage: get-available-ips.sh <group-name> <ips-needed>
#
# output: list of ips, one per line.
# on error a non-0 exit code and an error message.
#
# error codes:
#   1: unknown error - probably missing dependancy
#   2: invalid usage
#   3: not enough ips availabel
# 
# Depends: jq, nslookup (bind-utils)
#
# Env Variables
#  DNS - the IP of the DNS server to use
#  DOCKER_ARG - addional args to pass to docker command, such as hostname, etc.
#
if [ $# -lt 2 ]; then
	(>&2 echo "Usage: $(basename $0) <group-name> <ips-needed>")
	exit 2
fi

NAME=$1
COUNT=$2

GROUP=$(nslookup dynamic-$NAME.ps ${DNS:-192.168.11.16}|grep Name -A1|grep Address|cut -d":" -f2|sort|uniq)
CONTAINERS=$(docker ${DOCKER_ARG} ps -f label=porters.dynamic-group=$NAME -q)
if [ -n "$CONTAINERS" ]; then
	LIVE=$(docker ${DOCKER_ARG} inspect $CONTAINERS | jq -r ".[].NetworkSettings.Ports[][]?.HostIp"|sort|uniq|grep -v null)
	DIFF=$(echo $GROUP $LIVE | tr ' ' '\n' | sort | uniq -u)
	AVAILABLE=$(echo $DIFF $GROUP | tr ' ' '\n' | sort | uniq -D | uniq)
else
	AVAILABLE=$GROUP
fi

[ $(echo $AVAILABLE| wc -w) -lt $COUNT ] && echo "Not enough ips" && exit 3

echo $AVAILABLE | tr ' ' '\n' | sort | head -n $COUNT
