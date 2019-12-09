#!/bin/bash

if [ $# -lt 1 ]; then
	(>&2 echo "Usage: $(basename $0) <dnsgroup> <env> [<env> .. ]")
	exit 1
fi

: ${DNSDOMAIN:=autotest.porterscloud}
: ${IPVARPREFIX:=IP_}
: ${URLVARPREFIX:=URL_}
DNSGROUP=$1
VARS=( ${@:2} )

IPVARS=$(echo ${VARS[*]} | tr '[:space:]' '\n' | grep -e "^${IPVARPREFIX}" | sort | uniq)
URLVARS=$(echo ${VARS[*]} | tr '[:space:]' '\n' | grep -e "^${URLVARPREFIX}" | sort | uniq)
EXTS=($(echo "$(echo ${IPVARS[*]} | sed -e "/^${IPVARPREFIX}/ s/${IPVARPREFIX}//" -e "/^${IPVARPREFIX}/ s/${IPVARPREFIX}//")" | tr '[:space:]' '\n' | sort | uniq))

IPS=($(aws ec2 describe-network-interfaces --filters Name=attachment.instance-id,Values=$DNSGROUP | jq -r '.NetworkInterfaces[].PrivateIpAddresses[] | if .Primary | not then .PrivateIpAddress else empty end'))
if [ -z "${IPS[*]}" ] || [ "$(echo ${IPS[*]} | wc -w)" -lt "$(echo $EXTS | wc -w)" ]; then
	echo "could not get enough ips" >&2; exit 1;
fi

cnt=0
for varext in ${EXTS[*]}; do
	echo "$IPVARPREFIX$varext=${IPS[$cnt]}";
	echo "$IPVARPREFIX$varext=${IPS[$cnt]}" >&2;
    export $IPVARPREFIX$varext=${IPS[$cnt]}

    echo "$URLVARPREFIX$varext=$(echo ${PDOCKER_URLGROUP}-${varext} | tr '[:upper:]_' '[:lower:]-')";
	echo "$URLVARPREFIX$varext=$(echo ${PDOCKER_URLGROUP}-${varext} | tr '[:upper:]_' '[:lower:]-')" >&2;
    export $URLVARPREFIX$varext=$(echo ${PDOCKER_URLGROUP}-${varext} | tr '[:upper:]_' '[:lower:]-')

	cnt=$(( $cnt + 1 ))
done


echo "Generating Route53 Stack:" >&2

instanceStack=$(aws ec2 describe-instances --filters Name=instance-id,Values=${DNSGROUP} | jq -r '.Reservations[].Instances[].Tags | from_entries | .["aws:cloudformation:stack-name"]')

eval vars=$(echo "\${!$URLVARPREFIX*}");
if [ -n "$vars" ]; then
	# create url -> ip mapping from the instance is 
	json="{}";
	for urlvar in $vars; do
		ipvar="${IPVARPREFIX}${urlvar#$URLVARPREFIX}"
		if [ -n "${!ipvar}" ]; then
			json=$(echo $json | jq -c --arg url "${!urlvar}" --arg ip "${!ipvar}" '. + {($url):$ip}')
		fi
	done

	template=$(mktemp)
	# convert to stack json
	cat - > $template <<EOF
{
	AWSTemplateFormatVersion:"2010-09-09",
	Description: "Docker Server Private IP DNS",
	Parameters: {
		Domain:{
			Description: "Domain Name (HostedZoneName) to add DNS A records to",\
			Type: "String"
		}
	},
	Resources:{\
		Records:{\
			Type: "AWS::Route53::RecordSetGroup",
			Properties: {
				Comment: "AutoTest",
				HostedZoneName: { "Fn::Join": [ "", [ { Ref: "Domain" }, "." ] ] },
				RecordSets: (
					\$mapping | to_entries | [
						.[] | { Name: { "Fn::Join": [ "", [ .key, ".", { Ref: "Domain" }, "." ] ] }, Type: "A", TTL: 600, ResourceRecords: [ .value ] }
					]
				)
			}
		}
	}
}
EOF

	json=$(jq -n --argjson mapping "$json" -f $template);
	rm -f $template

	STACK_ID=$(aws cloudformation create-stack \
		--stack-name "${instanceStack}-IPS" \
		--template-body "$json" \
		--parameters "ParameterKey=Domain,ParameterValue=${DNSDOMAIN}" \
		--timeout-in-minutes 5 \
		| jq -r '.StackId')

	TIMEOUT=305

	# wait for stack to complete
	echo "Waiting for stack (Timeout: 5 minutes)" >&2
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
		exit 3;
	fi
	
	echo "Done" >&2	
else
	echo "Nothing to do." >&2
fi

