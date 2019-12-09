#!/bin/bash
set -ex

# HrbcBuildUrl - the build url to get the hrbc binaries from
# NOCACHE - if set, will disable cache if one of the following: "all" or "image". image will only ignore image cache. all will ignore base cache too.
# BUILD_WORKSPACE - workspace root
# REGISTRY - if not specified, will use default
# PHP_VERSION
# HTTPD_VERSION
# TOMCAT_VERSION
# JAVA_VERSION
#
# usage: $0 [<tag> ... ]
#
# Obtained from build url version file
# HRBC_VERSION - the hrbc version
# API_SVN - api svn revision
# PRODUCT_SVN - product svn revision
# STATIC_SVN - static svn revison
# OFFICE_SVN - static svn revison

function hastag {
	local image="$1"
	local tag="$2"
	local result;

	if [[ " $(curl -sL http://${REGISTRY}v2/$image/tags/list | jq -r .tags[] | tr '\n' ' ') " =~ " $tag " ]]; then
		result=1;
	else
		result=0;
	fi

	return $result;
}

# get version info
curl -sL $HrbcBuildUrl/artifact/version.txt -o version.env && source version.env;

# Build version strings
VERTAG_HTTPD=${HTTPD_VERSION:-off}
VERTAG_PHP=${PHP_VERSION:-off};
VERTAG_TOMCAT=${TOMCAT_VERSION:-off}
VERTAG_JAVA=${JAVA_VERSION:-off}

VERTAG_WEB="AZ${VERTAG_AZ}-J${VERTAG_JAVA}-T${VERTAG_TOMCAT}-A${VERTAG_HTTPD}-P${VERTAG_PHP}"
VERTAG_BASE_PHP="AZ${VERTAG_AZ}-J${VERTAG_JAVA}-A${VERTAG_HTTPD}-P${VERTAG_PHP}"
VERTAG_BASE_TOMCAT="AZ${VERTAG_AZ}-J${VERTAG_JAVA}-T${VERTAG_TOMCAT}"

# base hrbc tag on branch + revision
VERTAG_HRBC_BRANCH=$HRBC_VERSION;

labels=( "hrbc.version=${HRBC_VERSION}" )
vars=()
#if API_HASH is present, we asume git and use commitdate/hash to build tag.
for varname in API PRODUCT STATIC OFFICE TOOLS; do
	if [ -n "$API_HASH" ]; then
		datevar=${varname}_DATE
		hashvar=${varname}_HASH
		vars+=( "D$(date -u '+%Y%m%d%H%M%S' -d${!datevar})_H$(echo -n ${!hashvar} | head -c10)" )
		labels+=( "hrbc.${varname,,}.git.commitdate=${!datevar}" "hrbc.${varname,,}.git.hash=${!hashvar}" )
	else
		svnvar=${varname}_SVN
		vars+=( "r${!svnvar}" )
		labels+=( "hrbc.${varname,,}.svn.revision=${!svnvar}" )
	fi
done

HRBC_REV=$(echo ${vars[*]} | tr ' ' '\n' | sort -rn | head -1)
VERTAG_HRBC="${VERTAG_WEB}-H${VERTAG_HRBC_BRANCH}_${HRBC_REV}"
VERTAG_PHP="${VERTAG_BASE_PHP}-H${VERTAG_HRBC_BRANCH}_${HRBC_REV}"
VERTAG_TOMCAT="${VERTAG_BASE_TOMCAT}-H${VERTAG_HRBC_BRANCH}_${HRBC_REV}"
REGISTRY=${REGISTRY:-registry.ps.porters.local:5000/}

# Check registry for hrbc-base, web-base and build if needed
if [[ "all" == "$NOCACHE" ]] || hastag hrbc/base $VERTAG_WEB; then 
	DOCKERBUILD_ENVWHITELIST="PHP_VERSION HTTPD_VERSION TOMCAT_VERSION JAVA_VERSION" \
		DOCKERBUILD_LABELS="middleware.php.version=$PHP_VERSION middleware.httpd.version=$HTTPD_VERSION middleware.tomcat.version=$TOMCAT_VERSION middleware.java.version=$JAVA_VERSION" \
		DOCKERBUILD_REGISTRY=${REGISTRY} \
		DOCKERBUILD_FROMTAG="AZ${VERTAG_AZ}" \
		$BUILD_WORKSPACE/tools/build/build.sh hrbc/base $BUILD_WORKSPACE/hrbc-base $VERTAG_WEB
fi

# Check registry for hrbc-base-web and build if needed
if [[ "all" == "$NOCACHE" ]] || hastag hrbc/base-web $VERTAG_WEB; then
	DOCKERBUILD_ENVWHITELIST="" \
		DOCKERBUILD_LABELS="middleware.php.version=$PHP_VERSION middleware.httpd.version=$HTTPD_VERSION middleware.tomcat.version=$TOMCAT_VERSION middleware.java.version=$JAVA_VERSION" \
		DOCKERBUILD_FROMTAG=${VERTAG_WEB} \
		DOCKERBUILD_REGISTRY=${REGISTRY} \
		$BUILD_WORKSPACE/tools/build/build.sh hrbc/base-web $BUILD_WORKSPACE/hrbc-base-web $VERTAG_WEB
fi

# Check registry for php hrbc-base, web-base and build if needed
if [[ "all" == "$NOCACHE" ]] || hastag hrbc/base $VERTAG_BASE_PHP; then 
	DOCKERBUILD_ENVWHITELIST="PHP_VERSION HTTPD_VERSION JAVA_VERSION" \
		DOCKERBUILD_LABELS="middleware.php.version=$PHP_VERSION middleware.httpd.version=$HTTPD_VERSION middleware.java.version=$JAVA_VERSION" \
		DOCKERBUILD_REGISTRY=${REGISTRY} \
		DOCKERBUILD_FROMTAG="AZ${VERTAG_AZ}" \
		$BUILD_WORKSPACE/tools/build/build.sh hrbc/base $BUILD_WORKSPACE/hrbc-base $VERTAG_BASE_PHP
fi

# Check registry for php hrbc-base-web and build if needed
if [[ "all" == "$NOCACHE" ]] || hastag hrbc/base-web $VERTAG_BASE_PHP; then
	DOCKERBUILD_ENVWHITELIST="" \
		DOCKERBUILD_LABELS="middleware.php.version=$PHP_VERSION middleware.httpd.version=$HTTPD_VERSION middleware.java.version=$JAVA_VERSION" \
		DOCKERBUILD_FROMTAG=${VERTAG_BASE_PHP} \
		DOCKERBUILD_REGISTRY=${REGISTRY} \
		$BUILD_WORKSPACE/tools/build/build.sh hrbc/base-web $BUILD_WORKSPACE/hrbc-base-web $VERTAG_BASE_PHP
fi

# Check registry for hrbc version and build if needed
if [ 31202300 -gt $(( $(echo $HRBC_VERSION | cut -d"." -f1) * 10000000 + $(echo  $HRBC_VERSION | cut -d"." -f2) * 100000 + $(echo $HRBC_VERSION | cut -d"." -f3) * 100 + $(($(echo $HRBC_VERSION | cut -d"." -f4))) )) ] && [[ $HRBC_VERSION = *.* ]]; then 
	IMAGES="hrbc/api hrbc/web hrbc/fts hrbc/batch hrbc/migration hrbc/tools"
elif [ 40000100 -gt $(( $(echo $HRBC_VERSION | cut -d"." -f1) * 10000000 + $(echo  $HRBC_VERSION | cut -d"." -f2) * 100000 + $(echo $HRBC_VERSION | cut -d"." -f3) * 100 + $(($(echo $HRBC_VERSION | cut -d"." -f4))) )) ] && [[ $HRBC_VERSION = *.* ]]; then 
	IMAGES="hrbc/api hrbc/web hrbc/batch hrbc/migration hrbc/tools"
else
	IMAGES="hrbc/api hrbc/web hrbc/batch hrbc/migration hrbc/tools"
	IMAGES_TOMCAT="hrbc/privateapi"
	IMAGES_PHP="hrbc/product-web"
fi

for image in $IMAGES; do
	if [[ "all" == "$NOCACHE" ]] || [[ "image" == "$NOCACHE" ]] || hastag $image $VERTAG_HRBC; then
		# migration uses full versiontag as base and no artifact url
		[[ "hrbc/migration" = $image ]] && VerTagBase=$VERTAG_HRBC || VerTagBase=$VERTAG_WEB
		[[ "hrbc/migration" = $image ]] && BuildArgs="" || BuildArgs="ARTIFACT_URL=$HrbcBuildUrl/artifact"
		DOCKERBUILD_ENVWHITELIST="" \
			DOCKERBUILD_LABELS="${labels[*]}" \
			DOCKERBUILD_FROMTAG=${VerTagBase} \
			DOCKERBUILD_REGISTRY=${REGISTRY} \
			DOCKERBUILD_BUILDARG=${BuildArgs} \
			$BUILD_WORKSPACE/tools/build/build.sh $image $BUILD_WORKSPACE/${image/\//-} $VERTAG_HRBC $@
	else
		# pull latest in case local copy was cleaned
		docker pull ${REGISTRY}${image}:${VERTAG_HRBC}

		# add tags if already built
		for tag in $@; do
			docker tag ${REGISTRY}${image}:${VERTAG_HRBC} ${REGISTRY}${image}:$tag
			docker push ${REGISTRY}${image}:$tag
		done
	fi

	# if this is the latest tag in revision, we should add the latest flag (same base, no revision)
	prefix=${VERTAG_WEB}-H${VERTAG_HRBC_BRANCH}
	if test "$HRBC_REV" = "$(curl -sL http://${REGISTRY}v2/$image/tags/list | jq -r .tags[] | grep ^${prefix}_[rD][0-9]*.*$ | sed -re s/^..\{${#prefix}\}[r]*//g | sort -rn|head -1)"; then
		docker tag ${REGISTRY}${image}:${VERTAG_HRBC} ${REGISTRY}${image}:${prefix}
		docker push ${REGISTRY}${image}:${prefix}
	fi
done

if [ -n "$IMAGES_TOMCAT" ]; then
	for image in $IMAGES_TOMCAT; do
		if [[ "all" == "$NOCACHE" ]] || [[ "image" == "$NOCACHE" ]] || hastag $image $VERTAG_TOMCAT; then
			BuildArgs="ARTIFACT_URL=$HrbcBuildUrl/artifact"
			DOCKERBUILD_ENVWHITELIST="" \
				DOCKERBUILD_LABELS="${labels[*]}" \
				DOCKERBUILD_FROMTAG=${VERTAG_BASE_TOMCAT} \
				DOCKERBUILD_REGISTRY=${REGISTRY} \
				DOCKERBUILD_BUILDARG=${BuildArgs} \
				$BUILD_WORKSPACE/tools/build/build.sh $image $BUILD_WORKSPACE/${image/\//-} $VERTAG_TOMCAT $@
		else
			# pull latest in case local copy was cleaned
			docker pull ${REGISTRY}${image}:${VERTAG_TOMCAT}

			# add tags if already built
			for tag in $@; do
				docker tag ${REGISTRY}${image}:${VERTAG_TOMCAT} ${REGISTRY}${image}:$tag
				docker push ${REGISTRY}${image}:$tag
			done
		fi

		# if this is the latest tag in revision, we should add the latest flag (same base, no revision)
		prefix=${VERTAG_BASE_TOMCAT}-H${VERTAG_HRBC_BRANCH}
		if test "$HRBC_REV" = "$(curl -sL http://${REGISTRY}v2/$image/tags/list | jq -r .tags[] | grep ^${prefix}_[rD][0-9]*.*$ | sed -re s/^..\{${#prefix}\}[r]*//g | sort -rn|head -1)"; then
			docker tag ${REGISTRY}${image}:${VERTAG_TOMCAT} ${REGISTRY}${image}:${prefix}
			docker push ${REGISTRY}${image}:${prefix}
		fi
	done
fi

if [ -n "$IMAGES_PHP" ]; then
	for image in $IMAGES_PHP; do
		if [[ "all" == "$NOCACHE" ]] || [[ "image" == "$NOCACHE" ]] || hastag $image $VERTAG_PHP; then
			BuildArgs="ARTIFACT_URL=$HrbcBuildUrl/artifact"
			DOCKERBUILD_ENVWHITELIST="" \
				DOCKERBUILD_LABELS="${labels[*]}" \
				DOCKERBUILD_FROMTAG=${VERTAG_BASE_PHP} \
				DOCKERBUILD_REGISTRY=${REGISTRY} \
				DOCKERBUILD_BUILDARG=${BuildArgs} \
				$BUILD_WORKSPACE/tools/build/build.sh $image $BUILD_WORKSPACE/${image/\//-} $VERTAG_PHP $@
		else
			# pull latest in case local copy was cleaned
			docker pull ${REGISTRY}${image}:${VERTAG_PHP}

			# add tags if already built
			for tag in $@; do
				docker tag ${REGISTRY}${image}:${VERTAG_PHP} ${REGISTRY}${image}:$tag
				docker push ${REGISTRY}${image}:$tag
			done
		fi

		# if this is the latest tag in revision, we should add the latest flag (same base, no revision)
		prefix=${VERTAG_BASE_PHP}-H${VERTAG_HRBC_BRANCH}
		if test "$HRBC_REV" = "$(curl -sL http://${REGISTRY}v2/$image/tags/list | jq -r .tags[] | grep ^${prefix}_[rD][0-9]*.*$ | sed -re s/^..\{${#prefix}\}[r]*//g | sort -rn|head -1)"; then
			docker tag ${REGISTRY}${image}:${VERTAG_PHP} ${REGISTRY}${image}:${prefix}
			docker push ${REGISTRY}${image}:${prefix}
		fi
	done
fi

echo "VERTAG_BASE=${VERTAG_WEB}" >> version.env
echo "VERTAG_HRBC=${VERTAG_HRBC}" >> version.env
echo "VERTAG_PHP=${VERTAG_PHP}" >> version.env
echo "VERTAG_TOMCAT=${VERTAG_TOMCAT}" >> version.env
