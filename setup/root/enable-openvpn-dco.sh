#!/bin/bash
#
# Включаем DCO (Data Channel Offload) на OpenVpn 2.6
#
# chmod +x enable-openvpn-dco.sh && ./enable-openvpn-dco.sh
#
set -e

version=$(openvpn --version | head -n 1 | awk '{print $2}')10
if [[ ! $version =~ ^2\.6 ]]; then
    echo "OpenVPN version is not 2.6. Exiting."
    exit 1
fi

apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt dist-upgrade
apt autoremove -y
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y linux-headers-$(uname -r) openvpn-dco-dkms
modprobe -r ovpn_dco_v2
modprobe ovpn_dco_v2
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-udp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-tcp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-udp.conf
sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/antizapret-tcp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/vpn-udp.conf
echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM\"" >> /etc/openvpn/server/vpn-tcp.conf
echo ""
echo "Successful enable DCO!"
if [ "$1" != "noreboot" ]; then
	echo "Rebooting..."
	reboot
fi