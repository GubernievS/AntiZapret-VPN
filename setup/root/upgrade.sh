#!/bin/bash
#
# Установка обновлений Knot Resolver, dnslib, OpenVPN и DCO (если был установлен ранее)
#
# chmod +x upgrade.sh && ./upgrade.sh
#
set -e

if [ -d "/root/openvpn" ]; then
	cd /root/openvpn
	make uninstall
fi

mkdir -p /etc/apt/keyrings

curl -fsSL https://pkg.labs.nic.cz/gpg -o /usr/share/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/usr/share/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

apt update
apt remove --purge -y python3-dnslib
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt autoremove -y
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y openvpn python3-pip
PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install --upgrade dnslib

echo ""
echo "Successful upgrade Knot Resolver, dnslib and OpenVPN! Rebooting..."
reboot