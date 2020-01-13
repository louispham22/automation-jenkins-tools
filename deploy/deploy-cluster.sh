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
	if [[ ! ${CLUSTER_UPDATE:-false} == "true" ]]; then
		exit 1;
	fi
	echo "Update allowed."
else
	echo "Not Found."
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

### check images are present
# get images with registry used in cluster
images=$(eval "echo \"$(grep -he "image" ${CONF[@]} | sed -e 's/.*"\([^"]*\)".*/\1/')\" | sort | uniq | grep ':[0-9]*/'")

# loop over image, querying registry for images and thier tags
echo "Checking for images in Cluster:"
for image in $images; do
	reg=${image%%/*};
	nameWithTag=${image#*/};
	name=${nameWithTag%%:*};
	test $nameWithTag = $name && tag="latest" || tag=${nameWithTag#*:}

	echo -n "Image[$image]... "
	if [[ "$(curl -sL http://$reg/v2/$name/tags/list | jq -r .tags[] 2>/dev/null)" =~ "$tag" ]]; then
		echo "Found.";
	else
		echo "Not Found";
		exit 1
	fi
done

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
echo "Getting Available IPs:"
ips=$($workspace/extract-and-get-ip-vars.sh $DNSGROUP ${CONF[@]});
if [ $? -ne 0 ]; then
	echo "Error! Could not retrieve enough IPs."
	echo "They are probably all in use, try shutting down some public clusters."
	exit 1
else
	echo "$ips";
	export $ips;
fi

### Update DNS
echo "Updating DNS:"
$workspace/update-dns.sh

### deploy cluster
echo "Executing compose:"
env|grep 'DOCKER_'
cmd="docker-compose -p $NAME";
for f in ${CONF[*]}; do
	cmd="$cmd -f $f"
done

cmdpull="$cmd pull"
cmdup="$cmd up -d"

echo "# $cmdpull"
$cmdpull

echo "# $cmdup"
$cmdup

if [ -n "$Scale" ]; then 
	cmdscale="$cmd scale $Scale"
	cmdrestart="$cmd restart"
	
	echo "# $cmdscale"
	$cmdscale
	echo "# $cmdrestart"
	$cmdrestart
fi

### export variables
echo "Exporting variables used to version.env."
echo "$urls $ips $vardef NAME=$NAME DNSGROUP=$DNSGROUP URLVARPREFIX=$URLVARPREFIX IPVARPREFIX=$IPVARPREFIX" | tr ' ' '\n' >> version.env
echo "Done."

### get container version info
echo ""> container_versions.env
for container in $(docker ps  -f "label=com.docker.compose.project=${NAME//[-_]}" --format '{{.ID}}:{{.Label "com.docker.compose.service"}}'); do
	id=$(echo $container | cut -d':' -f1)
	name=$(echo $container | cut -d':' -f2)
	echo "*** $name ***" >> container_versions.env
	docker exec $id sh -c 'cat /etc/pinit/env.d/00_*version.env' >> container_versions.env
	echo '' >> container_versions.env
done

if [ -n "$POSTDEPLOY" ] && [ -f "$workspace/postdeploy-$POSTDEPLOY.sh" ]; then
	source $workspace/postdeploy-$POSTDEPLOY.sh;
fi
