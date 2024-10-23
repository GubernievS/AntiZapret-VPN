#!/bin/bash
#
# Удаление клиента
#
# chmod +x delete-client.sh && ./delete-client.sh [ov/wg] [имя_клиента]
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
if [[ -z "$CLIENT" || ! "$CLIENT" =~ ^[a-zA-Z0-9_-]{1,18}$ ]]; then
	echo ""
	echo "Existing client names:"
	# OpenVPN
	if [[ "$TYPE" == "ov" || "$TYPE" == "1" ]]; then
		tail -n +2 /etc/openvpn/easyrsa3/pki/index.txt | grep "^V" | cut -d '=' -f 2
	# WireGuard/AmneziaWG
	else
		cat /etc/wireguard/antizapret.conf /etc/wireguard/vpn.conf | grep -E "^# Client" | cut -d '=' -f 2 | sed 's/ //g' | sort -u
	fi
	echo ""
	echo "Tell me a name for the client to delete"
	echo "The name client must consist of 1 to 18 alphanumeric characters, it may also include an underscore or a dash"
	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]{1,18}$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi

NAME="$CLIENT"
NAME="${NAME#antizapret-}"
NAME="${NAME#vpn-}"

# OpenVPN
if [[ "$TYPE" == "ov" || "$TYPE" == "1" ]]; then

	cd /etc/openvpn/easyrsa3

	/usr/share/easy-rsa/easyrsa --batch revoke $CLIENT
	if [[ $? -ne 0 ]]; then
		echo "Failed to revoke certificate for client '$CLIENT', please check if the client exists"
		exit 11
	fi

	/usr/share/easy-rsa/easyrsa gen-crl
	cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
	if [[ $? -ne 0 ]]; then
		echo "Failed to update CRL"
		exit 12
	fi

	rm -f /root/vpn/antizapret-$NAME-*.ovpn
	rm -f /root/vpn/vpn-$NAME-*.ovpn
	rm -f /etc/openvpn/client/keys/$CLIENT.crt
	rm -f /etc/openvpn/client/keys/$CLIENT.key

	systemctl restart openvpn-server@*

	echo "OpenVPN client '$CLIENT' successfull deleted"

# WireGuard/AmneziaWG
else
	if ! grep -q "# Client = ${CLIENT}" "/etc/wireguard/antizapret.conf" && ! grep -q "# Client = ${CLIENT}" "/etc/wireguard/vpn.conf"; then
		echo "Failed to delete client '$CLIENT', please check if the client exists"
		exit 21
	fi

	sed -i "/^# Client = ${CLIENT}\$/,/^AllowedIPs/d" /etc/wireguard/antizapret.conf
	sed -i "/^# Client = ${CLIENT}\$/,/^AllowedIPs/d" /etc/wireguard/vpn.conf

	sed -i '/^$/N;/^\n$/D' /etc/wireguard/antizapret.conf
	sed -i '/^$/N;/^\n$/D' /etc/wireguard/vpn.conf

	rm -f /root/vpn/antizapret-$NAME-*.conf
	rm -f /root/vpn/vpn-$NAME-*.conf

	if systemctl is-active --quiet wg-quick@antizapret; then
		wg syncconf antizapret <(wg-quick strip antizapret 2> /dev/null)
	fi

	if systemctl is-active --quiet wg-quick@vpn; then
		wg syncconf vpn <(wg-quick strip vpn 2> /dev/null)
	fi

	echo "WireGuard/AmneziaWG client '$CLIENT' successfull deleted"

fi