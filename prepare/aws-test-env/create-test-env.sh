#!/bin/bash
#
# Register Cloudwatch Agent configs
#


usage() {
    cat - <<EOF
Usage: $0 [<options>]

Description:
  Create Test Environment

OPTIONS:
  -h          Show this help message.
  -c <cidr>   The CIDR of the VPC. Default: 10.57.0.0/16
  -z <az-num> The AZ to use. 0 -> a, 1 -> b, etc.. Default: 2
  -n <name>   The Env Name (used to prefix the exports.) Default: AutoTest
  -d <domain> The internal test domain name. Default: .autotest.porterscloud
EOF
}

FORCE=""

while getopts ":hc:z:d:n:" opt; do
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
        c)
            CidrBlock="$OPTARG"
			;;
        z)
            AvailabilityZone="$OPTARG"
			;;
        n)
            EnvName="$OPTARG"
			;;
        d)
            DomainName="$OPTARG"
			;;
	esac
done

shift $((OPTIND-1));

: ${DEPLOY_TIMEOUT:=5}
: ${DEPLOY_STACKCONF:=$(readlink -f test-env.template.json)}

PARAMS=()
if [ ! -z "${DEPLOY_TYPE}" ]; then
    PARAMS+=("ParameterKey=CidrBlock,ParameterValue=${CidrBlock}")
fi
if [ ! -z "${AvailabilityZone}" ]; then
    PARAMS+=("ParameterKey=AvailabilityZone,ParameterValue=${AvailabilityZone}")
fi
if [ ! -z "${EnvName}" ]; then
    PARAMS+=("ParameterKey=EnvName,ParameterValue=${EnvName}")
fi
if [ ! -z "${DomainName}" ]; then
    PARAMS+=("ParameterKey=DomainName,ParameterValue=${DomainName}")
fi

STACK_ID=$(aws cloudformation create-stack \
    --capabilities CAPABILITY_NAMED_IAM \
    --stack-name "AutoTestEnv-${EnvName:-Default}" \
    --template-body file://${DEPLOY_STACKCONF} \
    --parameters ${PARAMS[*]} \
    --timeout-in-minutes ${DEPLOY_TIMEOUT} \
    | jq -r '.StackId')

TIMEOUT=$(( $DEPLOY_TIMEOUT * 60 + 10 ))

# wait for stack to complete
echo "Waiting for stack (Timeout: ${DEPLOY_TIMEOUT} minutes)" >&2
for time in $(seq 0 5 ${TIMEOUT} | tail -n+2); do
    sleep 5;
    echo "  ...waited ${time} seconds" >&2
    STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} | jq -r .Stacks[].StackStatus)

    if [[ "$STATUS" = "CREATE_COMPLETE" ]] || [[ "$STATUS" = "ROLLBACK_COMPLETE" ]]; then
        break;
    fi
done

if [[ ! "$STATUS" = "CREATE_COMPLETE" ]]; then
    echo "Fatal: Stack Creation failed or timed out." >&2
    echo "Cloudformation event logs:" >&2
    aws cloudformation describe-stack-events --stack-name ${STACK_ID} |jq -r '.StackEvents[] | "[" + .Timestamp + "](" + .ResourceType + ") - " + .ResourceStatus + ": " + .ResourceStatusReason' >&2
    aws cloudformation delete-stack --stack-name ${STACK_ID} >&2
    exit 1;
fi

echo "StackId=${STACK_ID}"
aws cloudformation describe-stacks --stack-name ${STACK_ID} | jq -r '.Stacks[].Outputs[] | .OutputKey + "=" + .OutputValue'

echo "Done" >&2