#!/bin/bash

# define helper functions

usage() {
    cat - <<EOF
Usage: $0 [<USERDATA> [<TARGETNAME> [<TARGETVERSION>]]]

The following environment variables are required:
BUILDAMI_BASEAMI - The Base AMI ID, Name or version-name-tag. Must resovle to a valid ami id.
BUILDAMI_SECURITYGROUPS - The Security Group Ids
BUILDAMI_PROFILE - The IAM Instance Profile
BUILDAMI_SUBNET - The Subnet ID

The following environment variables may be used instead of the arguments.
Either the arguments or these environment variables must be specified.
BUILDAMI_USERDATA - Path to the userdata file
BUILDAMI_TARGETNAME - AMI Name
BUILDAMI_TARGETVERSION - AMI Version

The following environment variables are optional:
BUILDAMI_TYPE - The instance type to use. Default: t3.nano
BUILDAMI_TARGETDESCRIPTION - The description of the AMI. Default: Generated from name and version.
BUILDAMI_KEYPAIR - The KeyName Pair to use. Default: none.
BUILDAMI_OUTPUT - File to write resulting ami info to. Default: none.
BUILDAMI_BLOCKDEVICEMAPPING - AWSCLI BlockDeviceMapping configuration. Defaults to a single (root) 10GB GP2 EBS disk.
BUILDAMI_TIMEOUT_INSTANCE - Timeout in seconds for the instance creation. Minimum value: 120 seconds. Default: 300 seconds.
BUILDAMI_TIMEOUT_AMI - Timeout in seconds for the AMI creation. Minimum value: 120 seconds. Default: 300 seconds.
BUILDAMI_WAIT_INSTANCE - Interval to wait before checking instance creation completion. Maximum value: 60 seconds. Default: 5 seconds.
BUILDAMI_WAIT_AMI - Interval to wait before checking AMI creation completion. Maximum value: 60 seconds. Default: 5 seconds.
BUILDAMI_S3URL - S3 URL to upload the fs.tgz to. BUILDAMI_FSTGZ and BUILDAMI_S3REGION must be provided. Default: None
BUILDAMI_S3REGION - Region to use with S3 calls. Default: None
BUILDAMI_FSTGZ - Path to the FS tarball to upload to S3. Default: None
EOF
}

function join() {
    local IFS=$1
    shift
    echo "${*}"
}

function resolveAmi() {
    local ami=$1
    local imageId=""
    local version=""

    # check-id
    imageId=$(aws ec2 describe-images --filters Name=state,Values=available Name=image-id,Values=${ami} | jq -r .Images[].ImageId);
    if [ ! -z "${imageId}" ]; then 
        echo $imageId;
        return;
    fi

    # check native name
    imageId=$(aws ec2 describe-images --filters Name=state,Values=available Name=name,Values=${ami} | jq -r .Images[].ImageId)
    if [ ! -z "${imageId}" ]; then 
        echo $imageId;
        return;
    fi

    # now get all amis with name tag, sort by version.
    # get last value separated by '-' and check if it is version.
    version=$(echo ${ami##*-} | grep '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*');
    if [ ! -z "$version" ]; then
        imageId=$(aws ec2 describe-images --filters Name=state,Values=available Name=tag:Name,Values=${ami%-*} \
            | jq -r '.Images[] as $image | {id: $image.ImageId, tags: ( reduce $image.Tags[] as $tag ({}; . * {($tag.Key):$tag.Value}))} | .tags.Version + "-" + .tags.Build + " " + .id' \
            | sort -rVs | grep "^${version}" | head -1 | cut -d" " -f2)
    else
        imageId=$(aws ec2 describe-images --filters Name=state,Values=available Name=tag:Name,Values=${ami} \
            | jq -r '.Images[] as $image | {id: $image.ImageId, tags: ( reduce $image.Tags[] as $tag ({}; . * {($tag.Key):$tag.Value}))} | .tags.Version + "-" + .tags.Build + " " + .id' \
            | sort -rVs | head -1 | cut -d" " -f2)
    fi

    # if unresolved, this will be blank
    echo $imageId;
}


while getopts ":h" opt; do
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
	esac
done

shift $((OPTIND-1));

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            /) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    
    LC_COLLATE=$old_lc_collate
}

# check for help command

if [[ "$1" = "help" ]]; then
    usage;
    exit 4;
fi

# prepare variables

if [[ ! -z "$1" ]]; then
    BUILDAMI_USERDATA="$1"
fi
if [[ ! -z "$2" ]]; then
    BUILDAMI_TARGETNAME="$2"
fi
if [[ ! -z "$3" ]]; then
    BUILDAMI_TARGETVERSION="$3"
fi

if [ ! -z "${BUILDAMI_BASEAMI}" ]; then
    # resolve AMI Id
    BUILDAMI_BASEAMI=$(resolveAmi ${BUILDAMI_BASEAMI})
fi

if [ -z "${BUILDAMI_BASEAMI}" ]\
    || [ -z "${BUILDAMI_SECURITYGROUPS}" ]\
    || [ -z "${BUILDAMI_USERDATA}" ]\
    || [ -z "${BUILDAMI_SUBNET}" ]\
    || [ -z "${BUILDAMI_TARGETNAME}" ]\
    || [ -z "${BUILDAMI_TARGETVERSION}" ]\
    || [ -z "${BUILDAMI_PROFILE}" ] ; then
    echo "Required Parameters Missing"
    echo
    usage;
    exit 1;
fi

if { [ ! -z "${BUILDAMI_S3URL}" ] || [ ! -z "${BUILDAMI_FSTGZ}" ] || [ ! -z "${BUILDAMI_S3REGION}" ]; } && { [ -z "${BUILDAMI_S3URL}" ] || [ -z ${BUILDAMI_FSTGZ} ] || [ -z ${BUILDAMI_S3REGION} ]; }; then
    echo "BUILD_FSTGZ, BUILDAMI_S3REGION and BUILDAMI_S3URL are required when one of them is specified";
    echo
    usage;
    exit 1;
fi

: ${BUILDAMI_TIMEOUT_INSTANCE:=300}
: ${BUILDAMI_TIMEOUT_AMI:=300}
: ${BUILDAMI_WAIT_INSTANCE:=5}
: ${BUILDAMI_WAIT_AMI:=5}

if [ $BUILDAMI_TIMEOUT_INSTANCE -lt 120 ] \
    || [ $BUILDAMI_TIMEOUT_AMI -lt 120 ] \
    || [ $BUILDAMI_WAIT_INSTANCE -gt 60 ] \
    || [ $BUILDAMI_WAIT_AMI -gt 60 ]; then
    echo "Timeout or Wait values are outside of acceptible range"
    echo
    usage
    exit 3;
fi

: ${BUILDAMI_TYPE:=t3.nano}
: ${BUILDAMI_TARGETDESCRIPTION:=${BUILDAMI_TARGETNAME} ${BUILDAMI_TARGETVERSION}}
: ${BUILDAMI_BLOCKDEVICEMAPPING:=DeviceName=/dev/xvda,Ebs={VolumeSize=10\}}

USERDATAPATH=$(readlink -f ${BUILDAMI_USERDATA});
if [ ! -f "$USERDATAPATH" ]; then
    echo "${BUILDAMI_USERDATA} could not be found, or is not a readable file."
    echo
    usage;
    exit 2;
fi;

if [ ! -z "${BUILDAMI_FSTGZ}" ]; then
    FSTGZPATH=$(readlink -f ${BUILDAMI_FSTGZ});
    if [ ! -f "$FSTGZPATH" ]; then
        echo "${BUILDAMI_FSTGZ} could not be found, or is not a readable file."
        echo
        usage;
        exit 2;
    fi;

    # copy to S3
    echo "Copying FS to S3"
    aws --region ${BUILDAMI_S3REGION} s3 cp "${FSTGZPATH}" "${BUILDAMI_S3URL}"
fi

# start ec2 instance with userdata.
echo -n "Creating Instance: "
INSTANCE=$(aws ec2 run-instances \
    --instance-type ${BUILDAMI_TYPE} \
    --image-id ${BUILDAMI_BASEAMI} \
    $(if [ ! -z "${BUILDAMI_KEYPAIR}" ]; then echo "--key-name ${BUILDAMI_KEYPAIR}";fi;) \
    --security-group-ids "${BUILDAMI_SECURITYGROUPS}" \
    --subnet-id ${BUILDAMI_SUBNET} \
    --user-data fileb://$(urlencode "${USERDATAPATH}") \
    --iam-instance-profile Name=${BUILDAMI_PROFILE} \
    --instance-initiated-shutdown-behavior stop \
    --block-device-mappings ${BUILDAMI_BLOCKDEVICEMAPPING} \
    --count 1 \
    --tag-specification \
        'ResourceType=instance,Tags=[{Key=Name,Value=CreateAMI},{Key=TargetName,Value="'${BUILDAMI_TARGETNAME}'"},{Key=TargetVersion,Value='${BUILDAMI_TARGETVERSION}'}]'\
    | jq -r .Instances[].InstanceId)
echo "Done"
echo "Instance ID: $INSTANCE"

if [ -z "$INSTANCE" ]; then
    echo "Fatal: Error Creating Instance." >&2
    exit 3;
fi

# register termination function
function terminate() {
    echo "Terminating Instances: "
    aws ec2 terminate-instances --instance-ids $INSTANCE | jq -r .TerminatingInstances[].InstanceId
    echo "Done"

    # if FS was uploaded to S3 - delete it.
    if [ ! -z "$FSTGZPATH" ]; then
        aws --region "${BUILDAMI_S3REGION}" s3 rm "${BUILDAMI_S3URL}"
    fi
}
trap terminate INT TERM

# wait for instance to shutdown
echo "Waiting for instance setup to complete (Timeout: ${BUILDAMI_TIMEOUT_INSTANCE} seconds)"
for time in $(seq 0 ${BUILDAMI_WAIT_INSTANCE} ${BUILDAMI_TIMEOUT_INSTANCE} | tail -n+2); do
    sleep ${BUILDAMI_WAIT_INSTANCE};
    echo "  ...waited ${time} seconds"
    STATUS=$(aws ec2 describe-instance-status --instance-ids $INSTANCE --include-all-instances | jq -r .InstanceStatuses[].InstanceState.Name)

    if [[ "$STATUS" = "stopped" ]]; then
        break;
    fi
done
if [[ ! "$STATUS" = "stopped" ]]; then
    echo "Fatal: Instance preparation timed out." >&2
    terminate
    exit 4;
fi
echo "Done"

# Determine AMI Name
AMINAME="${BUILDAMI_TARGETNAME/ /-}-${BUILDAMI_TARGETVERSION}"
AMINAME=${AMINAME,,}

nameFilter="Name=tag:Name,Values=\"${BUILDAMI_TARGETNAME}\""
IMAGES=( $(aws ec2 describe-images \
    --owners self \
    --filters \
        "$nameFilter" \
        Name=tag:Version,Values=$BUILDAMI_TARGETVERSION \
    | jq -r .Images[].ImageId) )

if [ -z "$IMAGES" ]; then
    AMIBUILD=1
else 
    idFilters="Name=resource-id,Values=$(join , ${IMAGES[*]})"
    AMIBUILD=$(( $(aws ec2 describe-tags --filters "$idFilters" Name=key,Values=Build \
        | jq -r .Tags[].Value | sort -r | head -1) + 1 ))
fi
AMINAME="$AMINAME-$AMIBUILD"

# Create AMI
echo -n "Creating AMI: "

AMIID=$(aws ec2 create-image \
    --instance-id $INSTANCE \
    --name "$AMINAME" \
    --description "${BUILDAMI_TARGETDESCRIPTION}" \
    | jq -r .ImageId)
tagName="Key=Name,Value=\"${BUILDAMI_TARGETNAME}\""
aws ec2 create-tags --resources $AMIID --tags "$tagName" Key=Version,Value=${BUILDAMI_TARGETVERSION} Key=Build,Value=${AMIBUILD}
echo "Done"

echo "AMI Name: $AMINAME"
echo "AMI Id: $AMIID"

echo -n "Waiting for AMI to complete (Timeout: ${BUILDAMI_TIMEOUT_AMI} seconds)"

# waiting for AMI to be complete
for time in $(seq 0 ${BUILDAMI_WAIT_AMI} ${BUILDAMI_TIMEOUT_AMI} | tail -n+2); do
    sleep ${BUILDAMI_WAIT_AMI};
    echo "  ...waited ${time} seconds"
    STATUS=$(aws ec2 describe-images --owners self --image-ids $AMIID | jq -r .Images[].State) 
    if [[ "$STATUS" = "available" ]]; then
        break;
    fi
done
if [[ ! "$STATUS" = "available" ]]; then
    echo "Fatal: AMI Creation timed out." >&2
    terminate
    exit 5;
fi
echo "Done"

# terminate instance
terminate;

# if needed, output variables to file
if [ ! -z "$BUILDAMI_OUTPUT" ]; then
    echo "AMINAME=$AMINAME" > $BUILDAMI_OUTPUT
    echo "AMIID=$AMIID" >> $BUILDAMI_OUTPUT
fi

echo "AMI Successfully Created".

