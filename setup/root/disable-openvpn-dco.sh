#!/bin/bash
#
# Выключаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x disable-openvpn-dco.sh && ./disable-openvpn-dco.sh
#
set -e
sed -i "/tun-mtu/d" /etc/openvpn/server/antizapret-udp.conf
sed -i "/tun-mtu/d" /etc/openvpn/server/antizapret-tcp.conf
echo "disable-dco" >> /etc/openvpn/server/antizapret-udp.conf
echo "disable-dco" >> /etc/openvpn/server/antizapret-tcp.conf
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
