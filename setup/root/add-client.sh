#!/bin/bash
set -e

CLIENT=$1
if [ -z "$CLIENT" ]
then
	echo ""
	echo "Tell me a name for the new client OpenVPN"
	echo "The name must consist of alphanumeric character, it may also include an underscore or a dash"

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi


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
[[ ! "$SERVER" ]] && echo "Can't determine global IP address!" && exit 1

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
		exit 2
	fi
}

if [[ ! -f ./pki/ca.crt ]] || \
   [[ ! -f ./pki/issued/antizapret-server.crt ]] || \
   [[ ! -f ./pki/private/antizapret-server.key ]]
then
	rm -rf ./pki/
	/usr/share/easy-rsa/easyrsa init-pki
	EASYRSA_CA_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch --req-cn="AntiZapret CA" build-ca nopass
	EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-server-full "antizapret-server" nopass
	cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
	cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
	cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
	echo "Created new PKI and CA in '/root/easyrsa3/pki'"
fi

if [[ ! -f /etc/openvpn/server/keys/ca.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.key ]]
then
	cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
	cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
	cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
fi

if [[ ! -f ./pki/issued/$CLIENT.crt ]] || \
   [[ ! -f ./pki/private/$CLIENT.key ]]
then
	EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-client-full "$CLIENT" nopass
	cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
	cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
	echo "OpenVPN client configuration files will be created now"
else
	echo "The specified client was already found, please choose another name"
	echo "OpenVPN client configuration files will be updated now"
fi

if [[ ! -f /etc/openvpn/client/keys/$CLIENT.crt ]] || \
   [[ ! -f /etc/openvpn/client/keys/$CLIENT.key ]]
then
	cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
	cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
fi

load_key

render "/etc/openvpn/client/templates/openvpn-udp-unified.conf" > "/etc/openvpn/client/$CLIENT-udp.ovpn"
render "/etc/openvpn/client/templates/openvpn-tcp-unified.conf" > "/etc/openvpn/client/$CLIENT-tcp.ovpn"

echo "Files '$CLIENT-udp.ovpn' and '$CLIENT-tcp.ovpn' have been created in '/etc/openvpn/client'"