#!/bin/bash
#
# Включаем DCO (Data Channel Offload) на OpenVpn 2.6+
#
# chmod +x enable-openvpn-dco.sh && ./enable-openvpn-dco.sh
#
set -e
apt-get update && apt-get full-upgrade -y && apt-get autoremove -y
apt-get install -y openvpn-dco-dkms
modprobe -r ovpn_dco_v2
modprobe ovpn_dco_v2
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco\|providers/d" /etc/openvpn/server/antizapret-udp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco\|providers/d" /etc/openvpn/server/antizapret-tcp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco\|providers/d" /etc/openvpn/server/vpn-udp.conf
sed -i "/ncp-ciphers\|data-ciphers\|disable-dco\|providers/d" /etc/openvpn/server/vpn-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/vpn-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/vpn-tcp.conf
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
systemctl restart openvpn-server@vpn-udp
systemctl restart openvpn-server@vpn-tcp
