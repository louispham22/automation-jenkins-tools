#/bin/bash
#
# Build Db Docker Image
#
# Usage: $(basename $0) <ImageTag> <DbFile> [<DbFile> .. ]
#
# Env:
# ImageName - the target db image name, as used by build.sh - default: hrbc/mysql
# FromName - the source db image name, as used by build.sh - default: mysql/server
# FromTag - the db image tag to use as source - default: latest
# 

set -ex

if [ "$#" -lt 2 ]; then
	echo "Usage: $(basename $0) <ImageTag> <DbFile> [<DbFile> .. ]"
	exit 1;
fi

ImageTag=$1
ImageName=${ImageName:-hrbc/mysql}
FromName=${FromName:-mysql/server}
FromTag=${FromTag:-latest}

workspace=$(pwd)
context=$(mktemp -d);

mkdir -p $context/sql
cat - > $context/Dockerfile <<EOS
FROM registry.ps.porters.local:5000/${FromName}:${FromTag}
ADD sql/* /initdb.d/
EOS

for dbFile in ${@:2}; do
	if [ ! -f "${dbFile}" ]; then
		continue;
	fi
	case "${dbFile}" in
		*.tgz | *.tar.gz)
			tar -C $context/sql -zxf ${dbFile}
		        ;;
               	*.sql | *.sql.gz | *.sh)
			mv ${dbFile} $context/sql;
			;;
		*)
			echo "Failing due to unknown file format: ${dbFile}.";
			rm -rf $context;
			exit 1;
			;;
	esac
done
${workspace}/tools/build/build.sh "${ImageName}" $context $ImageTag
rm -rf "$context"

