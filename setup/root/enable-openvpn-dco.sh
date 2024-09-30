#!/bin/bash
#
# Включаем DCO (Data Channel Offload) на OpenVpn 2.6
#
# chmod +x enable-openvpn-dco.sh && ./enable-openvpn-dco.sh
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

version=$(openvpn --version | head -n 1 | awk '{print $2}')
if [[ ! $version =~ ^2\.6 ]]; then
	echo "Enabling OpenVPN DCO is not possible, as OpenVPN version 2.6 is required"
	exit 0
fi

apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt autoremove -y
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y linux-headers-generic linux-headers-$(uname -r) openvpn-dco-dkms
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
systemctl daemon-reload
systemctl restart openvpn-server@*
echo ""
echo "Successful enable OpenVPN DCO!"