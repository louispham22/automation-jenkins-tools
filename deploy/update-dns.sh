#!/bin/bash
set -e

DNSDOMAIN=${DNSDOMAIN:-dynamic.ps.porters.local}
URLVARPREFIX=${URLVARPREFIX:-URL_}
IPVARPREFIX=${IPVARPREFIX:-IP_}
DNS=${DNS:-192.168.11.16}

eval vars=$(echo "\${!$URLVARPREFIX*}");
cmd="";
for urlvar in $vars; do
	ipvar="${IPVARPREFIX}${urlvar#$URLVARPREFIX}"
	if [ -n "${!ipvar}" ]; then
		echo "Setting ${!urlvar}.$DNSDOMAIN to ${!ipvar}"
		cmd="$cmd
update delete ${!urlvar}.$DNSDOMAIN a
update add ${!urlvar}.$DNSDOMAIN 60 a ${!ipvar}"
	else
		cmd="$cmd
update delete ${!urlvar}.$DNSDOMAIN a"
	fi
done

if [ -z "$cmd" ]; then
	 echo "Nothing to do."
else
	echo "$cmd"
	nsupdate -y hmac-sha512:dynamic.ps.porters.local:rAm0Aw0hvuOhGu1CcatQDiJ9i5hVzHXXXfjUgnWiSUV7u8UST2KHxUDAIO6ZsFk23rEqLXhCkMvvuEdH1Carlw== <<EOF
server $DNS
$cmd
send
EOF
fi
