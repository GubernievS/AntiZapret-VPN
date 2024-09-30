#!/bin/bash
#
# Удаление клиента
#
# chmod +x delete-client.sh && ./delete-client.sh [ovpn/wg] [имя_клиента]
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
if [[ "$TYPE" != "ovpn" && "$TYPE" != "wg" ]]; then
	echo ""
	echo "Please choose the VPN type:"
	echo "    1) OpenVPN"
	echo "    2) WireGuard"
	until [[ $TYPE =~ ^[1-2]$ ]]; do
		read -rp "Type choice [1-2]: " -e -i 1 TYPE
	done
fi

echo ""
echo "Existing client names:"
# OpenVPN
if [[ "$TYPE" == "ovpn" || "$TYPE" == "1" ]]; then
	tail -n +2 /root/easyrsa3/pki/index.txt | grep "^V" | cut -d '=' -f 2
# WireGuard
else
	grep -E "^# Client" "/etc/wireguard/antizapret.conf" | cut -d '=' -f 2 | sed 's/^ *//'
fi

CLIENT=$2
if [[ -z "$CLIENT" && ! "$CLIENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
	echo ""
	echo "Tell me a name for the client to delete"
	echo "The name must consist of alphanumeric character, it may also include an underscore or a dash"
	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi

NAME="$CLIENT"
NAME="${NAME#antizapret-}"
NAME="${NAME#vpn-}"

# OpenVPN
if [[ "$TYPE" == "ovpn" || "$TYPE" == "1" ]]; then

	cd /root/easyrsa3

	/usr/share/easy-rsa/easyrsa --batch revoke $CLIENT
	if [[ $? -ne 0 ]]; then
		echo "Failed to revoke certificate for client '$CLIENT', please check if the client exists"
		exit 1
	fi

	/usr/share/easy-rsa/easyrsa gen-crl
	cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
	if [[ $? -ne 0 ]]; then
		echo "Failed to update CRL"
		exit 2
	fi

	rm -f /root/antizapret-$NAME-*.ovpn
	rm -f /root/vpn-$NAME-*.ovpn
	rm -f /etc/openvpn/client/keys/$CLIENT.crt
	rm -f /etc/openvpn/client/keys/$CLIENT.key

	systemctl restart openvpn-server@antizapret-udp
	systemctl restart openvpn-server@antizapret-tcp
	systemctl restart openvpn-server@vpn-udp
	systemctl restart openvpn-server@vpn-tcp

	echo "OpenVPN client '$CLIENT' successfull deleted"

# WireGuard
else


if ! grep -q "# Client = ${CLIENT}" "/etc/wireguard/antizapret.conf" && \
   ! grep -q "# Client = ${CLIENT}" "/etc/wireguard/vpn.conf"; then
	echo "Failed to delete client '$CLIENT', please check if the client exists"
	exit 11
fi

	sed -i "/^# Client = ${CLIENT}\$/,/^$/d" "/etc/wireguard/antizapret.conf"
	sed -i "/^# Client = ${CLIENT}\$/,/^$/d" "/etc/wireguard/vpn.conf"

	rm -f /root/antizapret-$NAME.conf
	rm -f /root/vpn-$NAME.conf

	if systemctl is-active --quiet wg-quick@antizapret 2>/dev/null; then
		wg syncconf antizapret <(wg-quick strip antizapret)
	fi

	if systemctl is-active --quiet wg-quick@vpn 2>/dev/null; then
		wg syncconf vpn <(wg-quick strip vpn)
	fi

	echo "WireGuard client '$CLIENT' successfull deleted"

fi


