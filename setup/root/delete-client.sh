#!/bin/bash
set -e

cd /root/easyrsa3

CLIENT=$1
if [ -z "$CLIENT" ]
then
	echo ""
	echo "Tell me a name for the delete client OpenVPN"
	echo "The name must consist of alphanumeric character, it may also include an underscore or a dash"

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done
fi

/usr/share/easy-rsa/easyrsa --batch revoke antizapret-$CLIENT
if [ $? -ne 0 ]; then
    echo "Failed to revoke certificate for client $CLIENT"
    exit 1
fi

/usr/share/easy-rsa/easyrsa gen-crl
cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
if [ $? -ne 0 ]; then
    echo "Failed to update CRL"
    exit 2
fi

rm -f /root/antizapret-$CLIENT*.ovpn
rm -f /root/vpn-$CLIENT*.ovpn
rm -f /etc/openvpn/client/keys/antizapret-$CLIENT.crt
rm -f /etc/openvpn/client/keys/antizapret-$CLIENT.key

systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
systemctl restart openvpn-server@vpn-udp
systemctl restart openvpn-server@vpn-tcp

echo "OpenVPN client '$CLIENT' successfull deleted"
