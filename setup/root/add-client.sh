#!/bin/bash
set -e

mkdir /root/easyrsa3 || true
cd /root/easyrsa3

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
	CLIENT_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/client/keys/antizapret-$CLIENT.crt")
	CLIENT_KEY=$(cat -- "/etc/openvpn/client/keys/antizapret-$CLIENT.key")
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
	echo "Created new PKI and CA"
fi

if [[ ! -f ./pki/crl.pem ]]
then
	/usr/share/easy-rsa/easyrsa gen-crl
	cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
	echo "Created new CRL"
fi

if [[ ! -f /etc/openvpn/server/keys/ca.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.key ]] || \
   [[ ! -f ./pki/crl.pem ]]
then
	cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
	cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
	cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
	cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
fi

if [[ ! -f ./pki/issued/antizapret-$CLIENT.crt ]] || \
   [[ ! -f ./pki/private/antizapret-$CLIENT.key ]]
then
	EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-client-full antizapret-$CLIENT nopass
	cp ./pki/issued/antizapret-$CLIENT.crt /etc/openvpn/client/keys/antizapret-$CLIENT.crt
	cp ./pki/private/antizapret-$CLIENT.key /etc/openvpn/client/keys/antizapret-$CLIENT.key
else
	echo "The specified client was already found, please choose another name"
fi

if [[ ! -f /etc/openvpn/client/keys/antizapret-$CLIENT.crt ]] || \
   [[ ! -f /etc/openvpn/client/keys/antizapret-$CLIENT.key ]]
then
	cp ./pki/issued/antizapret-$CLIENT.crt /etc/openvpn/client/keys/antizapret-$CLIENT.crt
	cp ./pki/private/antizapret-$CLIENT.key /etc/openvpn/client/keys/antizapret-$CLIENT.key
fi

load_key

render "/etc/openvpn/client/templates/antizapret-udp.conf" > "/etc/openvpn/client/antizapret-$CLIENT-udp.ovpn"
render "/etc/openvpn/client/templates/antizapret-tcp.conf" > "/etc/openvpn/client/antizapret-$CLIENT-tcp.ovpn"
render "/etc/openvpn/client/templates/vpn-udp.conf" > "/etc/openvpn/client/vpn-$CLIENT-udp.ovpn"
render "/etc/openvpn/client/templates/vpn-tcp.conf" > "/etc/openvpn/client/vpn-$CLIENT-tcp.ovpn"

echo "OpenVPN client name '$CLIENT' configuration files have been (re)created in '/etc/openvpn/client'"