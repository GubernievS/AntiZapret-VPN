#!/bin/bash
#
# Добавление нового клиента
#
# chmod +x add-client.sh && ./add-client.sh [имя_клиента]
#
set -e

mkdir /root/easyrsa3 || true
cd /root/easyrsa3

CLIENT=$1
if [[ -z "$CLIENT" ]]
then
	echo ""
	echo "Tell me a name for the new client OpenVPN"
	echo "The name must consist of alphanumeric character, it may also include an underscore or a dash"

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi

CLIENT_CERT_EXPIRE=$2
if [[ -z "$CLIENT_CERT_EXPIRE" ]]; then
  CLIENT_CERT_EXPIRE=3650
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
	CLIENT_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/client/keys/$CLIENT.crt")
	CLIENT_KEY=$(cat -- "/etc/openvpn/client/keys/$CLIENT.key")
	if [[ ! "$CA_CERT" ]] || [[ ! "$CLIENT_CERT" ]] || [[ ! "$CLIENT_KEY" ]]
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

if [[ ! -f ./pki/issued/$CLIENT.crt ]] || \
   [[ ! -f ./pki/private/$CLIENT.key ]]
then
	EASYRSA_CERT_EXPIRE=$CLIENT_CERT_EXPIRE /usr/share/easy-rsa/easyrsa --batch build-client-full $CLIENT nopass
	cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
	cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
else
	echo "The specified client was already found, please choose another name for new client OpenVPN"
fi

if [[ ! -f /etc/openvpn/client/keys/$CLIENT.crt ]] || \
   [[ ! -f /etc/openvpn/client/keys/$CLIENT.key ]]
then
	cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
	cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
fi

load_key

NAME="$CLIENT"
NAME="${NAME#antizapret-}"
NAME="${NAME#vpn-}"

render "/etc/openvpn/client/templates/antizapret-udp.conf" > "/root/antizapret-$NAME-$SERVER-udp.ovpn"
render "/etc/openvpn/client/templates/antizapret-tcp.conf" > "/root/antizapret-$NAME-$SERVER-tcp.ovpn"
render "/etc/openvpn/client/templates/antizapret.conf" > "/root/antizapret-$NAME-$SERVER.ovpn"
render "/etc/openvpn/client/templates/vpn-udp.conf" > "/root/vpn-$NAME-$SERVER-udp.ovpn"
render "/etc/openvpn/client/templates/vpn-tcp.conf" > "/root/vpn-$NAME-$SERVER-tcp.ovpn"
render "/etc/openvpn/client/templates/vpn.conf" > "/root/vpn-$NAME-$SERVER.ovpn"

echo "OpenVPN configuration files for client '$CLIENT' have been (re)created in '/root'"