#!/bin/bash
#
# Включаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x enable-openvpn-dco.sh && ./enable-openvpn-dco.sh
#
set -e
apt-get install -y openvpn-dco-dkms
systemctl stop openvpn-server@antizapret-udp
systemctl stop openvpn-server@antizapret-tcp
modprobe -r ovpn_dco_v2
modprobe ovpn_dco_v2
sed -i '/ncp-ciphers\|data-ciphers\|disable-dco/d' /etc/openvpn/server/antizapret-udp.conf
sed -i '/ncp-ciphers\|data-ciphers\|disable-dco/d' /etc/openvpn/server/antizapret-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-tcp.conf
systemctl start openvpn-server@antizapret-udp
systemctl start openvpn-server@antizapret-tcp
