#!/bin/bash
#
# Script to compare declared schema with a migrated schema
#
# REQUIRES: mysql, mysqldump.
#
# This script does not compare the files directly. It runs them against the
# given DB and compares the dumps of the resulting databases.
#
# The following files will be created (or overwriten if the alread exist):
#     error.txt       The last error output will be in here.
#     expected.sql    The dump of the expected database.
#     migrated.sql    The dump of the migrated database.
#     differences.sql The difference between expected.sql and migrated.sql.
#
# On successfull completion, the created files will be removed, but if
# the script is interupted or an error occurs, they will remain to help you
# debug the problem.
#
# WARNING: Please note that the database given in <DBNAME> will be dropped and
#          recreated, then finaly dropped on success, so do not use an actual
#          DB. Instead use a non-existing DB or one you have set asside for
#          these kinds of operations.
#

if [ $# -lt 4 ]; then 
	echo -e "Syntax Error.\nCorrect Syntax: $0 <DBNAME> <EXPECTED_PATH> <CURRENT_PATH> <MIGRATION_PATH>"
	exit 1;
fi;

DBNAME=$1
EXPECTED=$2
CURRENT=$3
MIGRATION=$4

echo -n "Preparing Expected Schema using ${EXPECTED} ... "

mysql --login-path=local -e "DROP DATABASE IF EXISTS \`$DBNAME\`;CREATE DATABASE \`$DBNAME\`;"

cat "$EXPECTED"/*.sql | mysql --login-path=local $DBNAME &> error.txt
if [ -n "`cat error.txt`" ]; then
	echo "Failed. Interupting."
	cat error.txt;
	exit 1;
else
	echo "Ok."
fi

mysqldump --login-path=local --skip-opt --disable-keys --single-transaction --no-data --skip-comments $DBNAME > expected.sql

echo -n "Preparing Current Schema using ${CURRENT} ... "
mysql --login-path=local -e "DROP DATABASE IF EXISTS \`$DBNAME\`;CREATE DATABASE \`$DBNAME\`;"
cat "$CURRENT"/*.sql | mysql --login-path=local $DBNAME &> error.txt
if [ -n "`cat error.txt`" ]; then
	echo "Failed. Interupting."
	cat error.txt;
	exit 1;
else
	echo "Ok."
fi

echo -n "Migrating Current Schema using ${MIGRATION} ... "
cat "$MIGRATION"/*.sql | mysql --login-path=local $DBNAME &> error.txt
if [ -n "`cat error.txt`" ]; then
	echo "Failed. Interupting."
	cat error.txt;
	exit 1;
else
	echo "Ok."
fi

mysqldump --login-path=local --skip-opt --disable-keys --single-transaction --no-data --skip-comments $DBNAME > migrated.sql

echo -n "Comparing Migrated Schema and Expected Schema... "

diff expected.sql migrated.sql > differences.txt

if [ -z "`cat differences.txt`" ]; then
	echo "None."
else
	echo "Found `cat differences.txt | wc -l` lines."
        cat differences.txt
	exit 1;
fi

#clean
rm error.txt differences.txt expected.sql migrated.sql
echo "Done."



