#!/bin/bash
#
# Добавление нового клиента (* - только для OpenVPN)
#
# chmod +x add-client.sh && ./add-client.sh [ov/wg] [имя_клиента] [срок_действия*]
#
set -e

handle_error() {
	echo ""
	echo "Error occurred at line $1 while executing: $2"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

TYPE=$1
if [[ "$TYPE" != "ov" && "$TYPE" != "wg" ]]; then
	echo ""
	echo "Please choose the VPN type:"
	echo "    1) OpenVPN"
	echo "    2) WireGuard/AmneziaWG"
	until [[ $TYPE =~ ^[1-2]$ ]]; do
		read -rp "Type choice [1-2]: " -e TYPE
	done
fi

CLIENT=$2
if [[ -z "$CLIENT" && ! "$CLIENT" =~ ^[a-zA-Z0-9_-]{1,18}$ ]]; then
	echo ""
	echo "Tell me a name for the new client"
	echo "The name client must consist of 1 to 18 alphanumeric characters, it may also include an underscore or a dash"
	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]{1,18}$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi

SERVER_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
NAME="$CLIENT"
NAME="${NAME#antizapret-}"
NAME="${NAME#vpn-}"

render() {
	local IFS=''
	local File="$1"
	while read -r line; do
		while [[ "$line" =~ (\$\{[a-zA-Z_][a-zA-Z_0-9]*\}) ]]; do
			local LHS=${BASH_REMATCH[1]}
			local RHS="$(eval echo "\"$LHS\"")"
			line=${line//$LHS/$RHS}
		done
		echo "$line"
	done < $File
}

# OpenVPN
if [[ "$TYPE" == "ov" || "$TYPE" == "1" ]]; then

	CLIENT_CERT_EXPIRE=$3
	if ! [[ "$CLIENT_CERT_EXPIRE" =~ ^[0-9]+$ ]] || (( CLIENT_CERT_EXPIRE <= 0 )) || (( CLIENT_CERT_EXPIRE > 3650 )); then
		echo ""
		echo "Enter a valid client certificate expiration period (1 to 3650 days)"
		until [[ "$CLIENT_CERT_EXPIRE" =~ ^[0-9]+$ ]] && (( CLIENT_CERT_EXPIRE > 0 )) && (( CLIENT_CERT_EXPIRE <= 3650 )); do
			read -rp "Certificate expiration days (1-3650): " -e -i 3650 CLIENT_CERT_EXPIRE
		done
	fi

	mkdir /root/easyrsa3 || true
	cd /root/easyrsa3

	load_key() {
		CA_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/server/keys/ca.crt")
		CLIENT_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/client/keys/$CLIENT.crt")
		CLIENT_KEY=$(cat -- "/etc/openvpn/client/keys/$CLIENT.key")
		if [[ ! "$CA_CERT" ]] || [[ ! "$CLIENT_CERT" ]] || [[ ! "$CLIENT_KEY" ]]; then
			echo "Can't load client keys!"
			exit 11
		fi
	}

	if [[ ! -f ./pki/ca.crt ]] || \
	   [[ ! -f ./pki/issued/antizapret-server.crt ]] || \
	   [[ ! -f ./pki/private/antizapret-server.key ]]; then
		rm -rf ./pki/
		/usr/share/easy-rsa/easyrsa init-pki
		EASYRSA_CA_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch --req-cn="AntiZapret CA" build-ca nopass
		EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-server-full "antizapret-server" nopass
		cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
		cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
		cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
		echo "Created new PKI and CA"
	fi

	if [[ ! -f ./pki/crl.pem ]]; then
		/usr/share/easy-rsa/easyrsa gen-crl
		cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
		echo "Created new CRL"
	fi

	if [[ ! -f /etc/openvpn/server/keys/ca.crt ]] || \
	   [[ ! -f /etc/openvpn/server/keys/antizapret-server.crt ]] || \
	   [[ ! -f /etc/openvpn/server/keys/antizapret-server.key ]] || \
	   [[ ! -f ./pki/crl.pem ]]; then
		cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
		cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
		cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
		cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
	fi

	if [[ ! -f ./pki/issued/$CLIENT.crt ]] || \
	   [[ ! -f ./pki/private/$CLIENT.key ]]; then
		EASYRSA_CERT_EXPIRE=$CLIENT_CERT_EXPIRE /usr/share/easy-rsa/easyrsa --batch build-client-full $CLIENT nopass
		cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
		cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
	else
		echo "A client with the specified name was already created, please choose another name"
	fi

	if [[ ! -f /etc/openvpn/client/keys/$CLIENT.crt ]] || \
	   [[ ! -f /etc/openvpn/client/keys/$CLIENT.key ]]; then
		cp ./pki/issued/$CLIENT.crt /etc/openvpn/client/keys/$CLIENT.crt
		cp ./pki/private/$CLIENT.key /etc/openvpn/client/keys/$CLIENT.key
	fi

	load_key

	render "/etc/openvpn/client/templates/antizapret-udp.conf" > "/root/antizapret-$NAME-$SERVER_IP-udp.ovpn"
	render "/etc/openvpn/client/templates/antizapret-tcp.conf" > "/root/antizapret-$NAME-$SERVER_IP-tcp.ovpn"
	render "/etc/openvpn/client/templates/antizapret.conf" > "/root/antizapret-$NAME-$SERVER_IP.ovpn"
	render "/etc/openvpn/client/templates/vpn-udp.conf" > "/root/vpn-$NAME-$SERVER_IP-udp.ovpn"
	render "/etc/openvpn/client/templates/vpn-tcp.conf" > "/root/vpn-$NAME-$SERVER_IP-tcp.ovpn"
	render "/etc/openvpn/client/templates/vpn.conf" > "/root/vpn-$NAME-$SERVER_IP.ovpn"

	echo "OpenVPN configuration files for the client '$CLIENT' have been (re)created in '/root'"

# WireGuard/AmneziaWG
else

	IPS=$(cat /etc/wireguard/ips)
	if [[ ! -f "/etc/wireguard/key" ]]; then
		PRIVATE_KEY=$(wg genkey)
		PUBLIC_KEY=$(echo "${PRIVATE_KEY}" | wg pubkey)
		echo "PRIVATE_KEY=${PRIVATE_KEY}
		PUBLIC_KEY=${PUBLIC_KEY}" > /etc/wireguard/key
	else
		source /etc/wireguard/key
	fi

	if [[ ! -f "/etc/wireguard/antizapret.conf" ]]; then
		render "/etc/wireguard/templates/antizapret.conf" > "/etc/wireguard/antizapret.conf"
		systemctl restart wg-quick@antizapret
	fi

	if [[ ! -f "/etc/wireguard/vpn.conf" ]]; then
		render "/etc/wireguard/templates/vpn.conf" > "/etc/wireguard/vpn.conf"
		systemctl restart wg-quick@vpn
	fi

	CLIENT_BLOCK_ANTIZAPRET=$(awk "/# Client = ${CLIENT}\$/,/AllowedIPs/" "/etc/wireguard/antizapret.conf")
	CLIENT_BLOCK_VPN=$(awk "/# Client = ${CLIENT}\$/,/AllowedIPs/" "/etc/wireguard/vpn.conf")
	if [[ -n "$CLIENT_BLOCK_ANTIZAPRET" ]]; then
		CLIENT_PRIVATE_KEY=$(echo "$CLIENT_BLOCK_ANTIZAPRET" | grep '# PrivateKey =' | awk -F' = ' '{print $2}')
		CLIENT_PUBLIC_KEY=$(echo "$CLIENT_BLOCK_ANTIZAPRET" | grep 'PublicKey =' | awk -F' = ' '{print $2}')
		CLIENT_PRESHARED_KEY=$(echo "$CLIENT_BLOCK_ANTIZAPRET" | grep 'PresharedKey =' | awk -F' = ' '{print $2}')
		echo "A client with the specified name was already created, please choose another name"
	elif [[ -n "$CLIENT_BLOCK_VPN" ]]; then
		CLIENT_PRIVATE_KEY=$(echo "$CLIENT_BLOCK_VPN" | grep '# PrivateKey =' | awk -F' = ' '{print $2}')
		CLIENT_PUBLIC_KEY=$(echo "$CLIENT_BLOCK_VPN" | grep 'PublicKey =' | awk -F' = ' '{print $2}')
		CLIENT_PRESHARED_KEY=$(echo "$CLIENT_BLOCK_VPN" | grep 'PresharedKey =' | awk -F' = ' '{print $2}')
		echo "A client with the specified name was already created, please choose another name"
	else
		CLIENT_PRIVATE_KEY=$(wg genkey)
		CLIENT_PUBLIC_KEY=$(echo "${CLIENT_PRIVATE_KEY}" | wg pubkey)
		CLIENT_PRESHARED_KEY=$(wg genpsk)
	fi

	sed -i "/^# Client = ${CLIENT}\$/,/^$/d" /etc/wireguard/antizapret.conf
	sed -i "/^# Client = ${CLIENT}\$/,/^$/d" /etc/wireguard/vpn.conf

	# AntiZapret

	BASE_CLIENT_IP=$(grep "^Address" /etc/wireguard/antizapret.conf | sed 's/.*= *//' | cut -d'.' -f1-3 | head -n 1)

	for i in {2..255}; do
		CLIENT_IP="${BASE_CLIENT_IP}.$i"
		if ! grep -q "$CLIENT_IP" /etc/wireguard/antizapret.conf; then
			break
		fi
		if [[ $i == 255 ]]; then
			echo "The WireGuard/AmneziaWG subnet can support only 253 clients"
			exit 22
		fi
	done

	render "/etc/wireguard/templates/antizapret-client-wg.conf" > "/root/antizapret-$NAME-wg.conf"
	render "/etc/wireguard/templates/antizapret-client-am.conf" > "/root/antizapret-$NAME-am.conf"

	echo -e "# Client = ${CLIENT}
# PrivateKey = ${CLIENT_PRIVATE_KEY}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}/32
" >> "/etc/wireguard/antizapret.conf"

	if systemctl is-active --quiet wg-quick@antizapret 2> /dev/null; then
		wg syncconf antizapret <(wg-quick strip antizapret)
	fi

	# VPN

	BASE_CLIENT_IP=$(grep "^Address" /etc/wireguard/vpn.conf | sed 's/.*= *//' | cut -d'.' -f1-3 | head -n 1)

	for i in {2..255}; do
		CLIENT_IP="${BASE_CLIENT_IP}.$i"
		if ! grep -q "$CLIENT_IP" /etc/wireguard/vpn.conf; then
			break
		fi
		if [[ $i == 255 ]]; then
			echo "The WireGuard/AmneziaWG subnet can support only 253 clients"
			exit 23
		fi
	done

	render "/etc/wireguard/templates/vpn-client-wg.conf" > "/root/vpn-$NAME-wg.conf"
	render "/etc/wireguard/templates/vpn-client-am.conf" > "/root/vpn-$NAME-am.conf"

	echo -e "# Client = ${CLIENT}
# PrivateKey = ${CLIENT_PRIVATE_KEY}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${CLIENT_PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}/32
" >> "/etc/wireguard/vpn.conf"

	if systemctl is-active --quiet wg-quick@vpn 2> /dev/null; then
		wg syncconf vpn <(wg-quick strip vpn)
	fi

	echo "WireGuard/AmneziaWG configuration files for the client '$CLIENT' have been (re)created in '/root'"

fi