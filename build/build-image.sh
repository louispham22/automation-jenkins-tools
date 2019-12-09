#!/bin/bash
set +ex

# arg 1 -> image name
# arg 2 -> image context
# arg 3 -> artifact base
# arg 4+ -> base version(s)

IMG_NAME=$1
IMG_CONTEXT=$2
URL_BASE=$3
shift 3

curl -o version.env -sL $URL_BASE/version.env

source version.env

#determine tag suffix(s)
SUFFIX=( "R${BUILD_GIT_SHORT}" );
labels=( "git.hash=${BUILD_GIT_COMMIT}" );

if [ -n "${BUILD_GIT_COMMITDATE}" ]; then
    labels+=( "git.commitdate=${BUILD_GIT_COMMITDATE}" )
fi

LATESTSUFFIX=()
[ -n "$BUILD_GIT_CHANGE" ] && {
    SUFFIX+=( "C${BUILD_GIT_CHANGE/\//.}" );
    labels+=( "git.change=${BUILD_GIT_CHANGE/\//.}" );
}
[ -n "$BUILD_GIT_BRANCH" ] && {
    branches=()    
    for branch in ${BUILD_GIT_BRANCH}; do
        if [ -n "$BUILD_GIT_COMMITDATE" ]; then
            LATESTSUFFIX+=( "B${branch/\//.}" )
        else
            SUFFIX+=( "B${branch/\//.}" )
        fi
        branches+=( "${branch/\//.}" );
    done;
    labels+=( "git.branch=$(echo ${branches[*]} | tr ' ' ',')" )
}
[ -n "$BUILD_GIT_TAG" ] && {
    tags=()    
    for tag in ${BUILD_GIT_TAG}; do
        SUFFIX+=( "T${tag/\//.}" )
        tags+=( "${tag/\//.}" );
    done;
    labels+=( "git.tag=$(echo ${tags[*]} | tr ' ' ',')" )
}

# now build and image for each given base
for fromtag in $@; do
    tags=""
    for tag in ${SUFFIX[@]}; do
        tags="$tags ${FROMPREFIX}${fromtag}_${tag}"
    done
    for tag in ${LATESTSUFFIX[@]}; do
        # pull image, check commitdate and only add if we are newer 
        docker pull ${DOCKERBUILD_REGISTRY:-registry.ps.porters.local:5000/}${IMG_NAME}:${FROMPREFIX}${fromtag}_${tag} && {
            currentdate=$(docker inspect ${DOCKERBUILD_REGISTRY:-registry.ps.porters.local:5000/}${IMG_NAME}:${FROMPREFIX}${fromtag}_${tag} | jq -r '.[].Config.Labels["git.commitdate"] // empty')
            # if not set or less than commit date, new entry will override
            echo -n "Current commit image date: " >&2
            date -u -d$currentdate '+%s' >&2
            echo -n "New commit date: " >&2
            date -u -d$BUILD_GIT_COMMITDATE '+%s' >&2


            
            if [ -z "$currentdate" ] || [ $(date -u -d$currentdate '+%s') -lt $(date -u -d${BUILD_GIT_COMMITDATE} '+%s') ]; then
                echo "new commit is newer, assinging tag ${tag}" >&2;
                tags="$tags ${FROMPREFIX}${fromtag}_${tag}";
            fi
        } || {
            tags="$tags ${FROMPREFIX}${fromtag}_${tag}";
        }
    done
    DOCKERBUILD_LABELS="${labels[*]}" DOCKERBUILD_FROMTAG=$fromtag $BUILD_WORKSPACE/tools/build/build.sh $IMG_NAME $IMG_CONTEXT $tags
done