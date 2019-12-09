#!/bin/bash
#
# Verify HRBC DB Schema Migrations.
#
# To do this we need 2 pieces of information. They are determined from the git commit log.
# 1. The prev HRBC Release revision (PrevHRBCRev)
# 2. The target DB Version (NextHRBCVer)
#
# We also need access to the source files. The HRBCGIT should contain a path to the HRBC Git repository.
# If not a git repository, script will fail.
#
# This script will extract the info from the commit log, if not present, it will fail with error code and message.
#
# We then the current revision and target DB Version, to generate SQL migrations and target SQL Db schema.
#
# Next step is to checkout the Release revision and generate Original SQL Db Schema.
#
# Now we populate DB with original, run migration sql and dump schema.
# Then we populate DB with new schema and dump.
# Finaly we compare the dumps. The schema_check.sh scirpt is used for these last stages.
#
# If dumps equal, return success, otherwise dump the diff and return with error code
#

[ -d $HRBCGIT/.git ] || { echo "$HRBCGIT not a git repository"; exit 1; }

cmd_schema=$(readlink -f $(dirname $0)/schema_check.sh)
cmd_tags=$(readlink -f $(dirname $0)/../git/get-tags.sh)

tmp=$(mktemp -d -p $WORKSPACE)
mkdir -p $tmp/prev $tmp/next $tmp/mig

pushd $HRBCGIT >/dev/null

eval $($cmd_tags HEAD COMMITTAGS)
[ -n "${COMMITTAGS[PrevHRBCRev]}" ] || { echo "PrevHRBCRev commit tag not set."; exit 2; }
[ -n "${COMMITTAGS[NextHRBCVer]}" ] || { echo "NextHRBCVer commit tag not set."; exit 3; }

echo "PrevHRBCRev: ${COMMITTAGS[PrevHRBCRev]}"
echo "NextHRBCVer: ${COMMITTAGS[NextHRBCVer]}"

[ -d "product/migration_script/${COMMITTAGS[NextHRBCVer]}" ] || { echo "no migrations: product/migration_script/${COMMITTAGS[NextHRBCVer]} missing."; exit 4; }

cat product/protected/data/db/databases/agent/mysql/*.sql > $tmp/next/db.sql
cat product/migration_script/${COMMITTAGS[NextHRBCVer]}/*.sql > $tmp/mig/db.sql

git checkout ${COMMITTAGS[PrevHRBCRev]}

cat product/protected/data/db/databases/agent/mysql/*.sql > $tmp/prev/db.sql

git checkout $GERRIT_PATCHSET_REVISION

popd

pushd $tmp

$cmd_schema VERIFY1 next prev mig
retval=$?

popd

if [ $retval != 0 ]; then
    mv $tmp result;
    exit 5;
else
    rm -rf $tmp;
fi

