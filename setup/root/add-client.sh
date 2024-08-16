#!/bin/bash
set -e

echo ""
echo "Tell me a name for the new client AntiZapret VPN"
echo "The name must consist of alphanumeric character, it may also include an underscore or a dash"

until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
	read -rp "Client name: " -e CLIENT
done

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE/easyrsa3"

export EASYRSA_CERT_EXPIRE=3650

set +e

SERVER=""
for i in 1 2 3 4 5;
do
    SERVER="$(curl -s -4 icanhazip.com)"
    [[ "$?" == "0" ]] && break
    sleep 2
done
[[ ! "$SERVER" ]] && echo "Can't determine global IP address!" && exit

set -e

render() {
    local IFS=''
    local File="$1"
    while read -r line ; do
        while [[ "$line" =~ (\$\{[a-zA-Z_][a-zA-Z_0-9]*\}) ]] ; do
        local LHS=${BASH_REMATCH[1]}
        local RHS="$(eval echo "\"$LHS\"")"
        line=${line//$LHS/$RHS}
        done
        echo "$line"
    done < $File
}

load_key() {
    CA_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/server/keys/ca.crt")
    CLIENT_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/client/keys/$CLIENT.crt")
    CLIENT_KEY=$(cat -- "/etc/openvpn/client/keys/$CLIENT.key")
    if [ ! "$CA_CERT" ] || [ ! "$CLIENT_CERT" ] || [ ! "$CLIENT_KEY" ]
    then
        echo "Can't load client keys!"
        exit
    fi
}

if [[ ! -f /etc/openvpn/client/keys/$CLIENT.crt ]] || \
   [[ ! -f /etc/openvpn/client/keys/$CLIENT.key ]]
then
    EASYRSA_BATCH=1 ./easyrsa build-client-full "$CLIENT" nopass nodatetime
    cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
    cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
else
	echo "The specified client was already found, please choose another name"
fi

load_key
render "/etc/openvpn/client/templates/openvpn-udp-unified.conf" > "/etc/openvpn/client/$CLIENT-udp.ovpn"
render "/etc/openvpn/client/templates/openvpn-tcp-unified.conf" > "/etc/openvpn/client/$CLIENT-tcp.ovpn"
