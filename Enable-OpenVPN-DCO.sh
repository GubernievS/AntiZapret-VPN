#!/bin/bash
#
# Включаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x Enable-OpenVPN-DCO.sh && ./Enable-OpenVPN-DCO.sh
#
set -e
apt-get install -y openvpn-dco-dkms
systemctl stop openvpn-server@antizapret-udp
systemctl stop openvpn-server@antizapret-tcp
modprobe -r ovpn_dco_v2
modprobe ovpn_dco_v2
systemctl start openvpn-server@antizapret-udp
systemctl start openvpn-server@antizapret-tcp
