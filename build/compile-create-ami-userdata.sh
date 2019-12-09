#!/bin/bash
#
# Compile UserData
#
# Version: 1.0
#

function usage() {
	echo "Usage $(basename $0) [<options>] <source> <target>" >&2
	echo "Arguments:" >&2
	echo -e "\t<source>\tThe AMI Source directory" >&2
	echo -e "\t<target>\tThe Output directory" >&2
    echo "Options:" >&2
	echo -e "\t-h\t\tShow this help message" >&2
    echo "Environment:" >&2
    echo -e "\tAWSREGION\tAWS S3 Region"
    echo -e "\tS3URL\t\tAWS S3URL that the fs tar will be uploaded to"
	echo
}

if [ -z "$1" ]; then
	usage
	exit 1;
fi

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

if [ -z "$1" ] || [ -z "$2" ]; then
    usage;
    exit 1;
fi

SRC=$(readlink -f $1)
TARGET=$(readlink -f $2)

: ${AWSREGION:=ap-northeast-1}

mkdir -p $TARGET

WORK=$(mktemp -d)

# register term function
function deleteTempDir() {
    rm -rf $WORK
}
trap deleteTempDir INT TERM

pushd $WORK >/dev/null

echo "Preparing Work Environment" >&2

mkdir cloudinit;

if [ -d $SRC/cloudinit ]; then
    cp $SRC/cloudinit/* cloudinit;
    pushd cloudinit >/dev/null;
    find . -name '*.yml' -print0 | xargs -0 -I % basename % .yml | xargs -I % mv %.yml %.cfg
    popd >/dev/null
fi

# force shutdown
cat - >cloudinit/99_shutdown.cfg <<EOF
#cloud-config
power_state:
    mode: poweroff
EOF

# copy fs to workdir
if [ -d "$SRC/fs" ]; then
    echo "File System: Found" >&2
    mkdir -p $WORK/fs
    cp -r $SRC/fs/* $WORK/fs
else
    echo "File System: Not Found" >&2
fi

if [ -f "$SRC/script/install.sh" ]; then
    mkdir -p $WORK/fs
    echo "Install Script: Found" >&2
    mkdir -p $WORK/fs/var/local
    cp $SRC/script/install.sh $WORK/fs/var/local/install.sh
    chmod a+x $WORK/fs/var/local/install.sh
else
    echo "Install Script: Not Found" >&2
fi

if [ -f "$SRC/script/compile.sh" ]; then
    echo  "Compile Script: Found."  >&2
    echo  "Compile Script: Running... "  >&2
    env -uSRC -uTARGET -uWORK bash $SRC/script/compile.sh >> $TARGET/vars.env
    if [ $? -ne 0 ]; then 
        echo "Compile Script: Error" >&2
        deleteTempDir
        exit 4
    else
        echo "Compile Script: Success" >&2
    fi

else
    echo "Compile Script: Not Found." >&2
fi

echo "Preparation Complete." >&2

# build fs tar
if [ ! -z "$(ls "$WORK/fs" -a1|tail -n+3)" ]; then
    echo "Building File System..." >&2;
    pushd $WORK/fs >/dev/null
    tar -zcf $WORK/fs.tgz --owner 0 --group 0 . >/dev/null
    popd >/dev/null
    size=$(du -k $WORK/fs.tgz | cut -f1);
    echo "File System size: ${size}k" >&2
    if [ $size -le 8 ]; then
        echo "Embeding File System tar in cloudinit."
        cat - >cloudinit/50_fs_write.cfg <<EOF
#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]

write_files:
  - owner: root:root
    path: /var/local/fs.tgz
    permissions: '0644'
    content: !!binary |
EOF
        echo -n "      " >> cloudinit/50_fs_write.cfg
        base64 -w0 fs.tgz >> cloudinit/50_fs_write.cfg
    else
        echo "Adding File System download scripts to cloudinit." >&2;
        if [ -z "$S3URL" ]; then
            echo "Error: FS too large to write to userdata. S3 URL Required." >&2;
            deleteTempDir
            exit 3;
        fi
        cp fs.tgz $TARGET
        echo "AWSREGION=$AWSREGION" >> $TARGET/vars.env
        echo "FSS3URL=$S3URL" >> $TARGET/vars.env
        cat - >cloudinit/50_fs_dl.cfg <<EOF
#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]

packages: ['awscli']
runcmd:
  - 'aws --region ${AWSREGION} s3 cp ${S3URL} /var/local/fs.tgz'
EOF
    fi

    cat - >cloudinit/51_fs_extract.cfg <<EOF
#cloud-config
merge_how:
 - name: list
   settings: [append]
 - name: dict
   settings: [no_replace, recurse_list]

runcmd:
  - 'tar --no-overwrite-dir -C / -zxf /var/local/fs.tgz'
  - 'rm -rf /var/local/fs.tgz'
  - 'test -x /var/local/install.sh && /var/local/install.sh'
  - 'test -f /var/local/install.sh && rm -f /var/local/install.sh'
EOF

fi

cat - > mimeify.py <<EOF
#!/usr/bin/python

import sys

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

if len(sys.argv) == 1:
    print("%s input-file:type ..." % (sys.argv[0]))
    sys.exit(1)

combined_message = MIMEMultipart()
for i in sys.argv[1:]:
    (filename, format_type) = i.split(":", 1)
    with open(filename) as fh:
        contents = fh.read()
    sub_message = MIMEText(contents, format_type, sys.getdefaultencoding())
    sub_message.add_header('Content-Disposition', 'attachment; filename="%s"' % (filename))
    combined_message.attach(sub_message)

print(combined_message)
EOF

echo "Compiling to Userdata" >&2

cli="";
for file in $(ls -1 cloudinit/*); do
    type="$(head -1 $file|tr -d "\n#")"
    sed -i -e "1d" $file;
    cli="$cli $file:$type";
done

python mimeify.py $cli |gzip -9 - > $TARGET/userdata.gz
success=$?
popd >/dev/null

deleteTempDir

echo "Done" >&2
exit $success