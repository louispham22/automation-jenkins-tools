#!/bin/bash
#
# Deploy Docker Server Stack
#

usage() {
    cat - >&2 <<EOF
Usage: $0 [<options>] <ami-id> <subnet-id>

Description:
  Start a docker server stack.
    
  Options override the values present in the Environment Variables

Arguments:

Options:
  -h                Show this message
  -d                Enable SSH (Debug) Access
  -e <envName>      Name of Automation Test Env. Default: AutoTest.
  -a <ami-id>       The AMI Id of the docker server AMI. Default: value of SSM /AutoTest/DockerServer/AMI.
  -n <name>         Stack name. If not provided, will be automatically generated.
  -c <config>       Location of template.json. Default is the same folder as this script.
  -t <type>         Instance Type
  -l <cidr>         Lock access to CIDR
  -k <keyname>      KeyPair to use for SSH access
  -i <count>        Number of secondary IPs to assign

Environment:
  DEPLOY_DEBUGMODE  Enable SSH (Debug) Access (if not empty)
  DEPLOY_STACKNAME  Stack name. If not provided, will be automatically generated.
  DEPLOY_STACKCONF  Location of template.json. Default is the same folder as this script.
  DEPLOY_TYPE       Instance Type
  DEPLOY_ENVNAME    Name of Automation Test Env. Default: AutoTest.
  DEPLOY_LOCKTOCIDR Lock access to CIDR
  DEPLOY_KEYNAME    KeyPair to use for SSH access
  DEPLOY_IPCOUNT    Number of secondary IPs to assign (Defaults to maximum for type)
  DEPLOY_TIMEOUT    The amount of time (in minutes) that can pass before we fail the create task.
                    Default: 5 minutes.
EOF
}

while getopts ":hdt:l:k:a:i:e:" opt; do
	case $opt in
		\?)
			echo "Ignoring unknown option -$OPTARG" >&2
			;;
		:)
			echo "Option -$OPTARG requires an argument" >&2
			;;
        n)
            DEPLOY_STACKNAME=$OPTARG
            ;;
        c)
            DEPLOY_STACKCONF=$OPTARG
            ;;
        t)
            DEPLOY_TYPE=$OPTARG
            ;;
        l)
            DEPLOY_LOCKTOCIDR=$OPTARG
            ;;
        k)
            DEPLOY_KEYNAME=$OPTARG
            ;;
        a)
            AMI=$OPTARG
            ;;
        e)
            DEPLOY_ENVNAME=$OPTARG
            ;;
        i)
            DEPLOY_IPCOUNT=$OPTARG
            ;;
        d)
            DEPLOY_DEBUGMODE=true
            ;;
		h)
			usage;
			exit 0;
            ;;
	esac
done

shift $((OPTIND-1));

if [ -z "$AMI" ]; then
    AMI=$(aws ssm get-parameter --name /AutoTest/DockerServer/Ami | jq -r .Parameter.Value)
fi

if [ -z "$AMI" ]; then
    usage;
    exit 2;
fi

if [ -z "${DEPLOY_ENVNAME}" ]; then
    DEPLOY_ENVNAME=AutoTest
fi

if [ -z "${DEPLOY_STACKNAME}" ]; then
    DEPLOY_STACKNAME=AutoTest-DockerServer-$(tr -dc '[:alnum:]' < /dev/urandom | head -c6)
fi

if [ -z "${DEPLOY_STACKCONF}" ]; then
    DEPLOY_STACKCONF=$(dirname $0)/$(basename $0 .sh).template.json
fi

if [ -z "${DEPLOY_IPCOUNT}" ]; then
    case "$DEPLOY_TYPE" in
        [crm]5[d]?\.large)
            DEPLOY_IPCOUNT=9
            ;;
        [tcrm]5[d]?\.[2]?xlarge)
            DEPLOY_IPCOUNT=14
            ;;
        [crm]5[d]?\.[49]?xlarge|[crm]5[d]?\.12xlarge)
            DEPLOY_IPCOUNT=29
            ;;
        c5[d]?\.18xlarge|[rm]5[d]?\.24xlarge)
            DEPLOY_IPCOUNT=49
            ;;
        t3\.nano)
            DEPLOY_IPCOUNT=1
            ;;
        t3\.micro)
            DEPLOY_IPCOUNT=1
            ;;
        t3\.small)
            DEPLOY_IPCOUNT=3
            ;;
        t3\.medium)
            DEPLOY_IPCOUNT=5
            ;;
        t3\.large)
            DEPLOY_IPCOUNT=11
            ;;
        *)
            DEPLOY_IPCOUNT=9
            ;;
    esac
fi

: ${DEPLOY_TIMEOUT:=5}

version=$(aws ec2 describe-tags --filters Name=resource-id,Values=$AMI Name=key,Values=Version|jq -r .Tags[].Value)

PARAMS=("ParameterKey=AMI,ParameterValue=${AMI}"  "ParameterKey=Version,ParameterValue=${version}" "ParameterKey=EnvName,ParameterValue=${DEPLOY_ENVNAME}" )
if [ ! -z "${DEPLOY_TYPE}" ]; then
    PARAMS+=("ParameterKey=InstanceType,ParameterValue=${DEPLOY_TYPE}")
fi
if [ ! -z "${DEPLOY_LOCKTOCIDR}" ]; then
    PARAMS+=("ParameterKey=DockerAccessCidrIp,ParameterValue=${DEPLOY_LOCKTOCIDR}")
fi
if [ ! -z "${DEPLOY_IPCOUNT}" ]; then
    PARAMS+=("ParameterKey=IpAddressCount,ParameterValue=${DEPLOY_IPCOUNT}")
fi
if [ ! -z "${DEPLOY_KEYNAME}" ]; then
    PARAMS+=("ParameterKey=KeyName,ParameterValue=${DEPLOY_KEYNAME}")
fi
if [ ! -z "${DEPLOY_DEBUGMODE}" ]; then
    PARAMS+=("ParameterKey=DebugMode,ParameterValue=${DEPLOY_DEBUGMODE}")
fi

STACK_ID=$(aws cloudformation create-stack \
    --stack-name "${DEPLOY_STACKNAME}" \
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
    echo "Cloudformation event logs:"
    aws cloudformation describe-stack-events --stack-name ${STACK_ID} |jq -r '.StackEvents[] | "[" + .Timestamp + "](" + .ResourceType + ") - " + .ResourceStatus + ": " + .ResourceStatusReason' >&2
    aws cloudformation delete-stack --stack-name ${STACK_ID} >&2
    exit 1;
fi

echo "StackId=${STACK_ID}"
source <(aws cloudformation describe-stacks --stack-name ${STACK_ID} | jq -r '.Stacks[].Outputs[] | .OutputKey + "=" + .OutputValue')
echo "InstanceId=${InstanceId}"

ip=$(aws ec2 describe-instances --filters Name=instance-id,Values=${InstanceId} | jq -r '.Reservations[].Instances[].PrivateIpAddress')

# waiting for docker connection to succeed
for time in $(seq 0 5 60 | tail -n+2); do
    sleep 5;
    echo "  ...waited ${time} seconds" >&2
    STATUS=$(env DOCKER_HOST=tcp://$ip:2376 docker run amazonlinux bash -c "echo 'SUCCESS'");
    if [[ "$STATUS" = "SUCCESS" ]]; then
        break;
    fi
done

echo "Done" >&2