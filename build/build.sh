#!/bin/bash
set -e

# DOCKERBUILD_ENVWHITELIST - white list of envs to use as build arguments
# DOCKERBUILD_REGISTRY - if not specified, will use default
# DOCKERBUILD_FROMTAG - if specified, will replace the tag of the :from image
# DOCKERBUILD_BUILDARG - build arguments
# DOCKERBUILD_LABELS - space separated list of build labels
# DOCKERBUILD_LABELS_[0-9] - build labels with spaces
# DOCKERBUILD_NOCACHE - if set to non block value, the cache is disabled
#
# usage: build.sh <name> <context> [[<tag> [<tag> ... ]]

if [ $# -lt 2 ]; then
	echo "Usage: $0 <name> <contextPath> [<tag> .. ]";
	exit 1;
fi

if [ -z "$DOCKERBUILD_REGISTRY" ]; then
	DOCKERBUILD_REGISTRY="registry.ps.porters.local:5000/"
elif [ "off" = "$DOCKERBUILD_REGISTRY" ]; then
	DOCKERBUILD_REGISTRY=""
fi

ctx=$2;
dockerfile=$ctx/Dockerfile
if [ -n "$DOCKERBUILD_FROMTAG" ]; then
	newdockerfile=$dockerfile.${DOCKERBUILD_FROMTAG}
	sed -e '/^FROM.*\// s/\(\/[^:]*\):.*/\1/' -e '/^FROM[^/]*$/ s/:.*//' -e "/^FROM/ s/$/:${DOCKERBUILD_FROMTAG}/" $dockerfile > $newdockerfile;
	dockerfile=$newdockerfile
fi

tags="${@:3}"
[ -z "$tags" ] && tags=latest;

cmd="docker build --force-rm";

if [ -n "$DOCKERBUILD_NOCACHE" ]; then
	cmd="$cmd --no-cache"
fi

for tag in $tags; do
	cmd="$cmd -t ${DOCKERBUILD_REGISTRY}${1}:$tag";
done

for env in $DOCKERBUILD_ENVWHITELIST; do
	cmd="$cmd --build-arg $env=${!env}";
done

for arg in $DOCKERBUILD_BUILDARG; do
	cmd="$cmd --build-arg $arg"
done

if [ -n "$DOCKERBUILD_LABELS" ]; then
	for label in $DOCKERBUILD_LABELS; do
		cmd="$cmd --label ${label}"
	done
fi
env |grep '^DOCKERBUILD_LABELS_[0-9]*=' -o | grep -o '[^=]*' | while read labelvar; do
	if [ -n "${!labelvar}" ]; then
		cmd="$cmd --label \"${!labelvar}\""
	fi
done

cmd="$cmd -f $dockerfile $ctx"
$cmd || exit 1;

if [ -n "$DOCKERBUILD_REGISTRY" ]; then
	for tag in $tags; do
		docker push ${DOCKERBUILD_REGISTRY}${1}:$tag || exit 1
	done;
fi
