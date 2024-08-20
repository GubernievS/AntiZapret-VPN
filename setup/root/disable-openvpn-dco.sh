#!/bin/bash
#
# Выключаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x disable-openvpn-dco.sh && ./disable-openvpn-dco.sh
#
set -e
echo -e "disable-dco" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "disable-dco" >> /etc/openvpn/server/antizapret-tcp.conf
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
