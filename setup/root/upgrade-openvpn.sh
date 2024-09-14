#!/bin/bash
#
# Установка последней версии OpenVPN 2.6 (и DCO если был установлен ранее)
#
# chmod +x upgrade-openvpn.sh && ./upgrade-openvpn.sh
#
set -e

mkdir -p /etc/apt/keyrings
curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

if [ -d "/root/openvpn" ]; then
	cd /root/openvpn
	make uninstall
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef"
apt-get autoremove -y
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y openvpn
echo ""
echo "Successful upgrade OpenVPN! Rebooting..."
reboot