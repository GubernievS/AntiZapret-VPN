#!/bin/bash
#
# Выключаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x disable-openvpn-dco.sh && ./disable-openvpn-dco.sh
#
set -e
echo "disable-dco" >> /etc/openvpn/server/antizapret-udp.conf
echo "disable-dco" >> /etc/openvpn/server/antizapret-tcp.conf
echo "disable-dco" >> /etc/openvpn/server/vpn-udp.conf
echo "disable-dco" >> /etc/openvpn/server/vpn-tcp.conf
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
systemctl restart openvpn-server@vpn-udp
systemctl restart openvpn-server@vpn-tcp
