#/bin/bash
set -ex

: ${RT:=$(pwd)}
: ${BUILD:=Release}
: ${TGZDIR=$RT/out}

TestProjectRoot=$1
TestProject=$2

if [ -z "$TestProjectRoot" ] || [ -z "$TestProject" ]; then
	echo "Usage: $0 <TestProjectRoot> <TestProject>";
	exit 1;
fi

rm -rf $TGZDIR
mkdir -p $TGZDIR

pushd $RT/tests;

dotnet restore --configfile nuget.config

pushd ${TestProjectRoot}

dotnet publish ${TestProject} -c $BUILD

: ${OUTPUT_PATH:=$(readlink -f ${TestProject}/bin/*/*|head -1)}
: ${APPSETTINGS:=$OUTPUT_PATH/publish/appsettings.json}

# Replace Config values with Jenkins Config values
for line in $(echo ${TestConfigParams}|sort|uniq); do  
	k=${line%%=*}
	v=${line#*=}
	jq -c "foreach . as \$item (. ; if .[\"$k\"] then .[\"$k\"] = \"$v\" else . end )" $APPSETTINGS >> tmp.$$.json && mv tmp.$$.json $APPSETTINGS
done
cat $APPSETTINGS | jq '.'

export APPSETTINGS

#Run NUnit
cmd=( "dotnet" "nunit" "$(readlink -f ${OUTPUT_PATH}/publish/${TestProject}.dll)" "--result=${TGZDIR}/TestResultOrig.xml" )
if [ -n "$NUnitRun" ]; then
	 cmd+=( "--where=\"$NUnitRun\"" )
fi
cmd+=( $ExtraParams )
echo ${cmd[@]} > cmd.sh
cat cmd.sh
sh cmd.sh || echo "Ignoring Test Failure";
rm cmd.sh;

popd
popd

if [ -f ${TGZDIR}/TestResultOrig.xml ]; then
	#Transform to report summary format
	if [ -x tools/test/to-summary.sh ]; then
		tools/test/to-summary.sh $TGZDIR/TestResultOrig.xml > $TGZDIR/ReportSummary.xml
	fi

	#Transform TestResult.xml to NUnit2 format
	xmlstarlet tr ${NUNIT_RUNNER}/nunit3-nunit2.xslt $TGZDIR/TestResultOrig.xml > $TGZDIR/TestResult.xml

	#Collect output files and Create a Zip file
	if [ -d $OUTPUT_PATH/publish/Log ]; then
		mv $OUTPUT_PATH/publish/Log/* $TGZDIR
	fi
else
	#ok.. something went wrong. tar the whole output for debugging
	cp -r $OUTPUT_PATH $TGZDIR
fi

#tar -zcf ../TestLogs.tgz TestResult.xml TestResultOrig.xml *.html *.log *.css *.js *.gif *.png *.jpg *.xml
pushd $TGZDIR
tar -zcf $RT/TestLogs.tgz *
popd