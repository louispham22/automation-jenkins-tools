#!/bin/bash
#
# 1. get list of tags in repository
# 2. for each tag get digest hash
# 3. group by digest hash
# 4. Offer action command. Allow to view tags, view or add to list of images to delete; or to execute or cancel.
# 5. Execute (or cancel) then return to 1. (if not canceled)


if [ ${#*} -lt 1 ]; then
	echo "Usage: $0 <docker-repo>"
	exit 1
fi

REPO=$1

REGISTRY=${REGISTRY:-registry.ps.porters.local:5000}

function printTags {
	local entry;
	local tagblock;
	local i;

	i=0;
	for entry in ${tags[*]}; do
		tagblock=${entry#*+};
		tagblock=${tagblock#*+};
		echo "$i: ${tagblock//+/, }"
		i=$(( $i + 1 ))
	done	
}

while true; do
	# step 1.
	tags=( $(curl -sL http://$REGISTRY/v2/$REPO/tags/list | jq -r .tags[] | sort) )

	# step 2.
	hashs=()
	for tag in ${tags[*]}; do
		hashs+=( "$(curl -sIH "Accept: application/vnd.docker.distribution.manifest.v2+json" "http://$REGISTRY/v2/$REPO/manifests/${tag}"|grep Docker-Content-Digest:|cut -d" " -f2 | tr -d [:space:])+$tag" )
	done

	# step 3.
	hashs=( $(echo "${hashs[*]}" | tr '[:space:]' "\n" | sort ) )

echo ${hashs[*]}|tr '[:space:]' '\n' > debug.txt

	tags=()
	phash=""
	taglist=""
	for hash in ${hashs[*]}; do
		if [[ $phash == ${hash%+*} ]]; then
			taglist="$taglist+${hash#*+}"
		else
			if [ -n "$taglist" ]; then
				tags+=( $taglist );
			fi
			phash=${hash%+*}
			taglist="${hash#*+}+$hash"
		fi
	done
	if [ -n "$taglist" ]; then
		tags+=( $taglist );
	fi
	tags=( $(echo "${tags[*]}" | tr '[:space:]' "\n" | sort ) )

	#step 4.
	printTags

	delete=();
	while true; do
		
		echo "Enter command: (number: add to delete list; p: print delete list; l: print numbers; d: execute delete; any other key to exit.) "	
		read -p "Command? " cmd;

		case $cmd in
			[0-9]*)
				if [[ "${tags[$cmd]}" = "${tags[0]}" ]] && [[ ! "0" = "$cmd" ]]; then
					echo "No such tag."
					exit 1;
				fi
				delete+=( ${tags[$cmd]} );
				;;
			[pP])
				echo "Planning delete the following:"
				for entry in ${delete[*]}; do
					tagblock=${entry#*+};
					tagblock=${tagblock#*+};
					echo ${tagblock//+/, }
				done
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

	# step 5.
	for entry in ${delete[*]}; do
		tagblock=${entry#*+}
		hash=${tagblock%%+*}
		tagblock=${tagblock#*+}
		echo -n "Deleting ${tagblock//+/, }..."

		curl -X DELETE -LH "Accept: application/vnd.docker.distribution.manifest.v2+json" http://$REGISTRY/v2/$REPO/manifests/$hash

		echo "Deleted."
	done
	echo
done

echo "Done"
