#!/bin/bash
#
# Выключаем DCO (Data Channel Offload) на OpenVpn 2.6
#
# chmod +x disable-openvpn-dco.sh && ./disable-openvpn-dco.sh
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

VERSION=$(openvpn --version | head -n 1 | awk '{print $2}')
if [[ ! "$VERSION" =~ ^2\.6 ]]; then
	echo "Cannot disable DCO because OpenVPN version 2.6 is required"
    exit 1
fi

sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-udp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-tcp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-udp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-192-CBC:AES-256-CBC\"
disable-dco" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-192-CBC:AES-256-CBC\"
disable-dco" >> /etc/openvpn/server/antizapret-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-192-CBC:AES-256-CBC\"
disable-dco" >> /etc/openvpn/server/vpn-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305:AES-128-CBC:AES-192-CBC:AES-256-CBC\"
disable-dco" >> /etc/openvpn/server/vpn-tcp.conf
systemctl restart openvpn-server@*
echo ""
echo "Successful disable OpenVPN DCO!"