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

/usr/share/easy-rsa/easyrsa --batch revoke $CLIENT
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

rm /etc/openvpn/client/$CLIENT-udp.ovpn
rm /etc/openvpn/client/$CLIENT-tcp.ovpn
rm /etc/openvpn/client/keys/$CLIENT.crt
rm /etc/openvpn/client/keys/$CLIENT.key

systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp

echo "OpenVPN client successfull deleted"
