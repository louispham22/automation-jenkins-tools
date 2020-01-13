#!/bin/bash
set +ex

# arg 1 -> image name
# arg 2 -> image context
# arg 3+ -> base version(s)

IMG_NAME=$1
IMG_CONTEXT=$2

BASE_TAGS=${@[2:]}
if [ -z "$BASE_TAGS" ]; then
	BASE_TAGS=( "latest" );
fi

# revision detection

pushd $IMG_CONTEXT;

BUILD_GIT_COMMIT=$(git rev-parse HEAD)
BUILD_GIT_SHORT=$(git rev-parse --short HEAD)

#Tag detection
tags=( $(git tag -l --contains $BUILD_GIT_COMMIT) )
for tag in ${tagsS[*]}; do
	[ -n "$tag" ] && [[ "$BUILD_GIT_COMMIT" != "$(git rev-parse $tag)" ]] && continue || BUILD_GIT_TAG="${BUILD_GIT_TAG} $tag"
done

#Branch detection
: ${BUILD_GIT_BRANCH:=$(git ls-remote | grep $BUILD_GIT_COMMIT | grep -v HEAD |grep heads | cut -d'/' -f3 |tr '\n' ' ')}

#Change detection
BUILD_GIT_CHANGE=$(git ls-remote | grep $BUILD_GIT_COMMIT | grep -v HEAD | grep 'changes' | cut -d'/' -f 4,5)

popd;

cat - > version.env <<EOF
BUILD_GIT_COMMIT=$BUILD_GIT_COMMIT
BUILD_GIT_SHORT=$BUILD_GIT_SHORT
BUILD_GIT_TAG=$BUILD_GIT_TAG
BUILD_GIT_BRANCH=$BUILD_GIT_BRANCH
BUILD_GIT_CHANGE=$BUILD_GIT_CHANGE
EOF

#determine tag suffix(s)
SUFFIX=( "R${BUILD_GIT_SHORT}" );

[ -n "$BUILD_GIT_CHANGE" ] && SUFFIX+=( "C${BUILD_GIT_CHANGE/\//.}" )
[ -n "$BUILD_GIT_BRANCH" ] && {
    for branch in ${BUILD_GIT_BRANCH}; do
        SUFFIX+=( "B${branch/\//.}" )
    done;
}
[ -n "$BUILD_GIT_TAG" ] && {
    for branch in ${BUILD_GIT_TAG}; do
        SUFFIX+=( "T${branch/\//.}" )
    done;
}

# now build and image for each given base
for fromtag in ${BASE_TAGS[@]}; do
    tags=""
    for tag in ${SUFFIX[@]}; do
		if [[ $fromtag == "latest" ]]; then
			tags="$tags ${tag}"
		else
        	tags="$tags ${fromtag}_${tag}"
		fi
    done
    DOCKERBUILD_FROMTAG=$fromtag $BUILD_WORKSPACE/tools/build/build.sh $IMG_NAME $IMG_CONTEXT $tags
done