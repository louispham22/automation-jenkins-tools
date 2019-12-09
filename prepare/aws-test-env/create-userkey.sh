#!/bin/bash
#
# Generate credentials for jenkins user
#


usage() {
    cat - <<EOF
Usage: $0 [<options>]

Description:
  Create Test Environement Jenkins User Credentials.

  The Username is retrieved from the stack. The stack should of been created with the create-test-env.sh script.

  This script outputs 2 files to current folder: <username>.pem and <username>.credentials. If either of these exist before script is run, script will fail.

OPTIONS:
  -h          Show this help message.
  -n <name>   The Env Name (used to determine the stack name) Default: AutoTest
EOF
}


while getopts ":hn:" opt; do
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
        n)
            EnvName="$OPTARG"
			;;
	esac
done

shift $((OPTIND-1));

STACK_NAME="AutoTestEnv-${EnvName:-Default}"

UserName=$(aws cloudformation describe-stacks --stack-name ${STACK_NAME} | jq -r '.Stacks[].Outputs[] | if .OutputKey=="JenkinsUser" then .OutputValue else empty end')

if [ -z "$UserName" ]; then
    echo "User name could not be detected." >&2
    exit 2;
fi

credFile="${UserName}.credentials"
keyFile="${UserName}.pem"

if [ -f $credFile ] || [ -f $keyFile ]; then
    echo "credential or key files already exist in this folder" >&2
    exit 1;
fi

aws iam create-access-key --user-name $UserName | jq -r '.AccessKey | ["aws_access_key_id = " + .AccessKeyId, "aws_secret_access_key = "+ .SecretAccessKey][]' > $credFile
aws ec2 --region ap-northeast-1 create-key-pair --key-name $UserName | jq -r .KeyMaterial > $keyFile