#!/bin/bash
#
# Step 1. get _all_ repos that match repo keyword.
# Step 2. for each of them get list of tags that match seach keyword
# Step 3. Dedup
# Step 4. Offer action command. Allow to view tags, view or add to list of images to delete; or to execute or cancel.
# Step 5. Execute (or cancel) then return to 2. (if not canceled)


if [ ${#*} -lt 1 ]; then
	echo "Usage: $0 <repoKeyword> [<imageKeyword>]"
	exit 1
fi

REPO=$1
KW=$2

REGISTRY=${REGISTRY:-registry.ps.porters.local:5000}

function printTags() {
	local i;
	local tag;
	i=0;
	for tag in ${tags[*]}; do
		echo "$i: $tag"
		i=$(( $i + 1 ))
	done
}


# step 1
repos=( $(curl -sL http://registry.ps.porters.local:5000/v2/_catalog -o - | jq -r '.repositories[]' 2>/dev/null |grep $REPO | sort ) );

if [ -z "${repos[*]}" ]; then echo "Repos not found"; exit; fi;

# step 2 entry point
while true; do
	# step 2
	tags=()
	for repo in ${repos[*]}; do 
		tags+=( $(curl -sL http://$REGISTRY/v2/${repo}/tags/list | jq -r .tags[] 2>/dev/null | grep "$KW" | sort) )
	done

	# step 3
	tags=( $(echo "${tags[*]}" | tr '[:space:]' "\n" | sort | uniq ) )
	
	# step 4

	printTags

	delete=();
	while true; do
		
		echo "Enter command: (number: add to delete list; p: print delete list; l: print numbers; d: execute delete; any other key to exit.) "	
		read -p "Command? " cmd;

		case $cmd in
			[0-9]*)
				if [[ "${tags[$cmd]}" = "${tags[0]}" ]] && [[ ! "0" = "$cmd" ]]; then
					echo "No such tag."
					exit 0;
				fi
				delete+=( ${tags[$cmd]} );
				;;
			[pP])
				echo ${delete[*]}
				;;
			[lL])
				printTags
				;;
			[dD])
				break
				;;
			*)
				break 2;
		esac
	done

	for tag in ${delete[*]}; do
		for repo in ${repos[*]}; do

			echo -n "Deleting $repo:$tag..."

			hash=$(curl -sIH "Accept: application/vnd.docker.distribution.manifest.v2+json" "http://$REGISTRY/v2/$repo/manifests/$tag"|grep Docker-Content-Digest:|cut -d" " -f2 | tr -d [:space:])
			if [ -z "$hash" ]; then
				echo "Not Found.";
				continue;
			fi
		
			curl -X DELETE -LH "Accept: application/vnd.docker.distribution.manifest.v2+json" http://$REGISTRY/v2/$repo/manifests/$hash

			echo "Deleted."
			echo
		done
	done
done

echo "Done"
