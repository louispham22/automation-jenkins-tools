#!/bin/bash
#
# Register Cloudwatch Agent configs
#


usage() {
    cat - <<EOF
Usage: $0 [<options>]

Description:
  Publish cloudwatch agent configurations to SSM

  If a config exists, it will not be overwritten unless forced.

OPTIONS:
  -h          Show this help message.
  -f <config> Force publishing of given config. You may specify this option multiple times.
EOF
}

FORCE=""

while getopts ":hf:" opt; do
	case $opt in
		\?)
			echo "Ignoring unknown option -$OPTARG" >&2
			;;
		:)
			echo "Option -$OPTARG requires an argument" >&2
			;;
		h)
			usage;
			exit 0;
			;;
        f)
            FORCE="$FORCE $OPTARG"
			;;
	esac
done

shift $((OPTIND-1));

pushd $(dirname $0) >/dev/null

for config in $(ls -1 cloudwatch); do
    name=/AutoTest/CloudWatchAgent/${config%%.json}
    force=$(printf '%s\n' $FORCE | grep -P "^${config%%.json}$")
	echo "Setting SSM $name"
	version=$(aws ssm put-parameter --name $name --value "$(jq -c <cloudwatch/$config .)" --type String ${force:+--overwrite} 2>/dev/null | jq -r '.Version | @text');
	if [ -z "$version" ]; then
		echo "Not Written. Force '${config%%.json}' to override.";
	else
		echo "New Version: $version"
	fi
done

popd >/dev/null
