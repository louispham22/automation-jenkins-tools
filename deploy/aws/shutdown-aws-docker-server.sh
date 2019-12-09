#!/bin/bash
#
# Deploy Docker Server Stack
#

usage() {
    cat - >&2 <<EOF
Usage: $0 [<options>] <stack-id>

Description:
  Delete a docker server stack.
    
Arguments:
  <stack-id>    The Stack ID

Options:
  -h                Show this message
  
EOF
}

while getopts ":hdt:l:k:p:i:" opt; do
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
	esac
done

shift $((OPTIND-1));

STACK_ID=$1
if [ -z "$STACK_ID" ]; then 
    usage;
    exit 2;
fi

# determine stackname from id. if '/' are not present, then the id is the stack name.
stackname=$(cut -d"/" -f2 <<<"${STACK_ID}");
if [ -z "$stackname" ]; then
	stackname=${STACK_ID}
	# resolve stack-id
	STACK_ID=$(aws cloudformation describe-stacks --stack-name $stackname | jq -r Stacks[].StackId)
fi

# try and delete the IPS too, but dont fail if they dont exist
aws cloudformation delete-stack --stack-name ${stackname}-IPS >/dev/null || true
aws cloudformation delete-stack --stack-name ${STACK_ID} >&2

# wait for delete to complete
SHUTDOWN_TIMEOUT=5
TIMEOUT=$(( $SHUTDOWN_TIMEOUT * 60 + 10 ))

# wait for stack delete to complete
echo "Waiting for stack to delete (Timeout: ${SHUTDOWN_TIMEOUT} minutes)" >&2
for time in $(seq 0 5 ${TIMEOUT} | tail -n+2); do
    sleep 5;
    echo "  ...waited ${time} seconds" >&2
    STATUS=$(aws cloudformation describe-stacks --stack-name ${STACK_ID} | jq -r .Stacks[].StackStatus)

    if [[ "$STATUS" = "DELETE_COMPLETE" ]] || [[ "$STATUS" = "DELETE_FAILED" ]]; then
        break;
    fi
done

if [[ ! "$STATUS" = "DELETE_COMPLETE" ]]; then
    echo "Fatal: Stack Creation failed or timed out." >&2
    echo "Cloudformation event logs:"
    aws cloudformation describe-stack-events --stack-name ${STACK_ID} |jq -r '.StackEvents[] | "[" + .Timestamp + "](" + .ResourceType + ") - " + .ResourceStatus + ": " + .ResourceStatusReason' >&2
    exit 1;
fi