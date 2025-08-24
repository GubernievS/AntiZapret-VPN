#!/bin/bash
#
# Включить/выключить DCO (Data Channel Offload) в OpenVpn 2.6
#
# chmod +x openvpn-dco.sh && ./openvpn-dco.sh [y/n]
#
set -e

handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

export LC_ALL=C

VERSION="$(openvpn --version | head -n 1 | awk '{print $2}')"
if [[ ! "$VERSION" =~ ^2\.6 ]]; then
	echo 'Cannot turn on/off DCO because OpenVPN version 2.6 is required'
	exit 2
fi

if [[ "$1" == [yn] ]]; then
	DCO="$1"
else
	echo
	echo 'OpenVPN DCO lowers CPU load, saves battery on mobile devices, boosts data speeds, and only supports AES-128-GCM, AES-256-GCM and CHACHA20-POLY1305 encryption protocols'
	until [[ "$DCO" =~ (y|n) ]]; do
		read -rp 'Turn on OpenVPN DCO? [y/n]: ' -e -i y DCO
	done
fi

if [[ "$DCO" == "y" ]]; then
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get dist-upgrade -y
	apt-get install --reinstall -y linux-headers-generic linux-headers-$(uname -r) openvpn-dco-dkms
	apt-get autoremove -y
	apt-get clean
	modprobe -r ovpn_dco_v2
	modprobe ovpn_dco_v2
	sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-udp.conf
	sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/antizapret-tcp.conf
	sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-udp.conf
	sed -i "/data-ciphers\|disable-dco/d" /etc/openvpn/server/vpn-tcp.conf
	echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305\"" >> /etc/openvpn/server/antizapret-udp.conf
	echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305\"" >> /etc/openvpn/server/antizapret-tcp.conf
	echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305\"" >> /etc/openvpn/server/vpn-udp.conf
	echo -e "data-ciphers \"AES-128-GCM:AES-256-GCM:CHACHA20-POLY1305\"" >> /etc/openvpn/server/vpn-tcp.conf
	if systemctl is-active --quie openvpn-server@*; then
		systemctl restart openvpn-server@*
	fi
	echo
	echo 'OpenVPN DCO turned ON successfully!'
else
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
	if systemctl is-active --quie openvpn-server@*; then
		systemctl restart openvpn-server@*
	fi
	echo
	echo 'OpenVPN DCO turned OFF successfully!'
fi
exit 0