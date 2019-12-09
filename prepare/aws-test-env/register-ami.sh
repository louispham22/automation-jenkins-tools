#!/bin/bash
#
# Register AMIs for needed instances
#

usage() {
    cat - <<EOF
Usage: $0 [<options>]

Description:
  Register AMIs for needed instances

OPTIONS:
  -h             Show this help message.
  -d <version>   The version of the docker server ami to use.
EOF
}


while getopts ":hd:" opt; do
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
        d)
            DockerServer="$OPTARG"
			;;
	esac
done

shift $((OPTIND-1));

if [ ! -z "$DockerServer" ]; then
    ami=$(aws ec2 describe-images --filters Name=state,Values=available Name=tag:Name,Values=docker-server Name=tag:Version,Values=$DockerServer \
            | jq -r '.Images[] as $image | {id: $image.ImageId, tags: ( reduce $image.Tags[] as $tag ({}; . * {($tag.Key):$tag.Value}))} | .tags.Build + "-" + .tags.Build + " " + .id' \
            | sort -rns | head -1 | cut -d" " -f2)
    #echo "$ami"
    #aws ec2 describe-images --filters Name=state,Values=available Name=tag:Name,Values=docker-server Name=tag:Version,Values=$DockerServer

    aws ssm put-parameter --name '/AutoTest/DockerServer/Ami' --type String --overwrite --value "$ami"
fi