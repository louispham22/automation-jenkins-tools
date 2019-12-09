#!/bin/bash

if [ ${#*} -lt 1 ]; then
	echo "Usage: $0 <repoKeyword> [<imageKeyword>]"
	exit 1
fi

REPO=$1
KW=$2

REGISTRY=${REGISTRY:-registry.ps.porters.local:5000}

repos=( $(curl -sL http://registry.ps.porters.local:5000/v2/_catalog -o - |jq -r '.repositories[]'|grep $REPO | sort ) );

if [ -z "${repos[*]}" ]; then echo "Repos not found"; exit; fi;
echo "Using: ${repos[0]} for listing and deleting from ${repos[*]}"

while true; do
	tags=( $(curl -sL http://$REGISTRY/v2/${repos[0]}/tags/list | jq -r .tags[] | grep "$KW" | sort) )

	i=0;
	for tag in ${tags[*]}; do
		echo "$i: $tag"
		i=$(( $i + 1 ))
	done
	
	read -p "Delete? " target;

	if [[ "${tags[$target]}" = "${tags[0]}" ]] && [[ ! "0" = "$target" ]]; then
		echo "No such tag."
		exit 0
	fi

	for repo in ${repos[*]}; do
	
		echo "Deleting $repo:${tags[$target]}"

		hash=$(curl -sIH "Accept: application/vnd.docker.distribution.manifest.v2+json" "http://$REGISTRY/v2/$repo/manifests/${tags[$target]}"|grep Docker-Content-Digest:|cut -d" " -f2 | tr -d [:space:])
		if [ -z "$hash" ]; then
			echo "Not Found.";
			continue;
		fi
	
		curl -X DELETE -LH "Accept: application/vnd.docker.distribution.manifest.v2+json" http://$REGISTRY/v2/$repo/manifests/$hash

		echo "Deleted."
		echo
	done
done

echo "Done"
