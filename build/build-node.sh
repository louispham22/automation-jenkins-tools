#!/bin/bash

# arg 1 -> folder name
# arg 2 -> output folder. defaults to pwd
set -e

[ -n "$1" ] || {
    echo "Usage $0 <git checkout> <output dir> " >&2
    exit 1
}

OUT=$2
: ${OUT:=$(pwd)}

pushd "$1" > /dev/null 2>&1

PACKAGE_NAME=$(jq -r '.name' < package.json)
PACKAGE_VERSION=$(jq -r '.version' < package.json)

if [ -d projects ]; then
    pushd projects 1>&2
    for proj in $(ls -1); do
        if [ -d $proj ]; then
            pushd $proj 1>&2
            npm i 1>&2
            popd 1>&2
        fi
    done
    popd 1>&2
fi
npm i 1>&2
gulp deploy 1>&2

[ -f dist/${PACKAGE_NAME}-${PACKAGE_VERSION}.zip ] && ext=zip || ext=tar.gz
cp dist/${PACKAGE_NAME}-${PACKAGE_VERSION}.$ext $OUT

BUILD_GIT_COMMIT=$(git rev-parse HEAD)
BUILD_GIT_SHORT=$(git rev-parse --short HEAD)
BUILD_GIT_COMMITDATE=$(date -u -Iseconds -d$(git log -n 1 --pretty=format:%cI))

#Tag detection
: ${BUILD_GIT_TAG:=$(git tag -l --contains $BUILD_GIT_COMMIT|head -1)}
[ -n "$BUILD_GIT_TAG" ] && [[ "$BUILD_GIT_COMMIT" != "$(git rev-parse $BUILD_GIT_TAG)" ]] && GIT_TAG= || true

#Branch detection
: ${BUILD_GIT_BRANCH:=$(git ls-remote | grep $BUILD_GIT_COMMIT | grep -v HEAD |grep heads | cut -d'/' -f3 | tr '\n\r' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')}

#Change detection
BUILD_GIT_CHANGE=$(git ls-remote | grep $BUILD_GIT_COMMIT | grep -v HEAD | grep 'changes' | cut -d'/' -f 4,5 | tr '\n\r' ' '| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

popd > /dev/null 2>&1

cat - <<EOF
PACKAGE_NAME=$PACKAGE_NAME
PACKAGE_VERSION=$PACKAGE_VERSION
BUILD_GIT_COMMITDATE=$BUILD_GIT_COMMITDATE
BUILD_GIT_COMMIT=$BUILD_GIT_COMMIT
BUILD_GIT_SHORT=$BUILD_GIT_SHORT
BUILD_GIT_TAG="$BUILD_GIT_TAG"
BUILD_GIT_BRANCH="$BUILD_GIT_BRANCH"
BUILD_GIT_CHANGE=$BUILD_GIT_CHANGE
EOF
