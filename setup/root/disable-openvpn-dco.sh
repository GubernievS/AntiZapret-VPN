#!/bin/bash
#
# Выключаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x disable-openvpn-dco.sh && ./disable-openvpn-dco.sh
#
set -e

version=$(openvpn --version | head -n 1 | awk '{print $2}')
if [[ ! $version =~ ^2\.6 ]]; then
    echo "OpenVPN version is not 2.6. Exiting."
    exit 1
fi

sed -i "/ncp-ciphers\|data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-udp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-tcp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-udp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:AES-128-CBC:AES-256-CBC\"
providers legacy default
disable-dco" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:AES-128-CBC:AES-256-CBC\"
providers legacy default
disable-dco" >> /etc/openvpn/server/antizapret-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:AES-128-CBC:AES-256-CBC\"
providers legacy default
disable-dco" >> /etc/openvpn/server/vpn-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:AES-128-CBC:AES-256-CBC\"
providers legacy default
disable-dco" >> /etc/openvpn/server/vpn-tcp.conf
systemctl daemon-reload
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
systemctl restart openvpn-server@vpn-udp
systemctl restart openvpn-server@vpn-tcp
echo ""
echo "Successful disable DCO!"