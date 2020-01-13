#!/bin/bash
if [ $# -lt 2 ]; then
       (>&2 echo "Usage: $(basename $0) <name> <config.yml> [ <config.yml> .. ]");
       exit 1;
fi

: ${DOCKERKEYS:=$HOME/.docker}

workspace=$(dirname $0)

CONF=( ${@:2} )
NAME=$1
export DNSGROUP=${DNSGROUP:-hrbc}
export DNS=${DNS:-192.168.11.16}
export URLVARPREFIX=${URLVARPREFIX:-URL_}
export IPVARPREFIX=${IPVARPREFIX:-IP_}

if [ -d $DOCKERKEYS/$DNSGROUP ]; then
	export DOCKER_CERT_PATH=$DOCKERKEYS/$DNSGROUP
	if [ -f $DOCKERKEYS/$DNSGROUP/docker.env ]; then
		source $DOCKERKEYS/$DNSGROUP/docker.env
	fi
fi

: ${COMPOSE_PATH:=$(readlink -f $WORKSPACE/cluster)}

function resolveConfig()
{
	local file=$1
	[ -f "$file" ] && { echo $file; return; }
	[ -f "${file}.yml" ] && { echo "${file}.yml"; return; }
	for p in $(echo $COMPOSE_PATH | tr ':' ' '); do
		[ -f "${p}/${file}" ] && { echo "${p}/$file"; return; }
		[ -f "${p}/${file}.yml" ] && { echo "${p}/${file}.yml"; return; }
	done
	return	
}

# Resolve configs
for i in $(seq 0 $(( ${#CONF[@]} - 1))); do
	conf="${CONF[$i]}"
	file=$(resolveConfig $conf);
	[ -f "$file" ] || { echo "Could not resolve config file $conf." >&2; exit 1; }
	CONF[$i]="$file";
done

### check cluster of same name is not running
echo "Checking for running clusters:"
echo -n "Cluster [$NAME]... "
if [ -n "$(docker ps -f "label=com.docker.compose.project=${NAME//[-_]}" -q)" ]; then
	echo "Found."
else
	echo "Not Found."
	exit
fi

### Check all variables are have values set
echo "Checking Env Variables:"
vars=$(eval "grep -ohe \"\\\${[^}]*}\" ${CONF[@]}"| grep -o '[^${}]*' | tr ' ' '\n' | grep -v -e "^$URLVARPREFIX" -e "^$IPVARPREFIX" | sort | uniq);
vardef=""
for var in $vars; do
	echo -n "Env[$var]... "
	if [ -n "${!var}" ]; then
		echo "Ok."
		vardef="$vardef $var=${!var}"
	else
		echo "Missing. Using blank string."
		vardef="$vardef $var="
	fi
done
export $vars

### get urls
echo "Generating URLS:"
urls=$($workspace/extract-and-get-url-vars.sh $NAME ${CONF[@]})
if [ $? -ne 0 ]; then
	echo "Error! Could not generate URLS."
	echo 1
else
	echo "$urls";
	export $urls
fi

### get ips
for var in $urls; do
	urlvar=${var%=*}
	export IP_${urlvar#URL_}=
done

### Update DNS
echo "Updating DNS:"
$workspace/update-dns.sh

### get ips
for var in $urls; do
	urlvar=${var%=*}
	export IP_${urlvar#URL_}=127.0.0.1
done

### deploy cluster
echo "Executing compose:"
env|grep 'DOCKER_'
cmd="docker-compose -p $NAME";
for f in ${CONF[*]}; do
	cmd="$cmd -f $f"
done

cmddown="$cmd down -v --remove-orphans --rmi local"

echo "# $cmddown"
$cmddown
