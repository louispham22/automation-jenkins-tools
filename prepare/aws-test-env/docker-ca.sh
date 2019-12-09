#!/bin/bash
#
# If Docker CA does not exist in SSM, Create CA and keys, then publish them.
#

usage() {
    cat - <<EOF
Usage: $0 [<options>]

Description:
  Create DockerServer CA, Key and Passphrase and store them in SSM.

  If the CA already exists, this script does nothing unless the operation is forced.

OPTIONS:
  -h  Show this help message.
  -f  Force CA Creation.
EOF
}

FORCE=""

while getopts ":hf" opt; do
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
        f)
            FORCE="force"
            ;;
	esac
done

shift $((OPTIND-1));

CA=$(aws ssm get-parameters --names /AutoTest/DockerServer/CA/Cert |jq -r .Parameters[].Value)

if [ ! -z "$CA" ] && [ -z "$FORCE" ]; then
    echo "CA exists. Skipping." >&2
    exit 0;
fi

WORK=$(mktemp -d)
pushd $WORK >/dev/null

echo -n "Writing Password. New Version: " >&2
aws ssm put-parameter --overwrite --type SecureString --name /AutoTest/DockerServer/CA/Password --value "$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w 64 | head -n 1 | tr -d '[:space:]')" | jq -r .Version >&2

echo "Generating Key." >&2
aws ssm get-parameter --name /AutoTest/DockerServer/CA/Password --with-decryption | jq -j .Parameter.Value | openssl genpkey -outform pem -pass stdin -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -aes256 -out ca-key.pem >&2

echo -n "Writing Key. New Version: " >&2
aws ssm put-parameter --overwrite --type SecureString --name /AutoTest/DockerServer/CA/Key --value "$(cat ca-key.pem)" |jq -r .Version >&2

echo "Generating Certificate." >&2
aws ssm get-parameter --name /AutoTest/DockerServer/CA/Password --with-decryption | jq -j .Parameter.Value | openssl req -new -x509 -days 3650 -key ca-key.pem -sha256 -out ca.pem -subj /C=JP/ST=Tokyo/O=Porters/CN=DockerServer -passin stdin -batch >&2

echo -n "Writing Certificate. New Version: " >&2
aws ssm put-parameter --overwrite --type String --name /AutoTest/DockerServer/CA/Cert --value "$(cat ca.pem)"|jq -r .Version >&2

echo "Generating Client Key." >&2
openssl genrsa -out client-key.pem 4096 >&2

echo -n "Writing Client Key. New Version: " >&2
aws ssm put-parameter --overwrite --type SecureString --name /AutoTest/DockerServer/Client/Key --value "$(cat client-key.pem)" |jq -r .Version >&2

echo "Generating Client Certificate." >&2

echo "extendedKeyUsage = clientAuth" > extfile-client.cnf
openssl req -subj '/CN=client' -new -key client-key.pem -out client.csr >&2
aws ssm get-parameter --name /AutoTest/DockerServer/CA/Password --with-decryption | jq -j .Parameter.Value | openssl x509 -req -days 3650 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out cert.pem -extfile extfile-client.cnf -passin stdin >&2

echo -n "Writing Client Certificate. New Version: " >&2
aws ssm put-parameter --overwrite --type String --name /AutoTest/DockerServer/Client/Cert --value "$(cat cert.pem)"|jq -r .Version >&2

echo "Done" >&2

popd >/dev/null
rm -rf $WORK