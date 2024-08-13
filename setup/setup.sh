#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

#
# Скрипт для автоматического развертывания AntiZapret VPN
# + Разблокирован YouTube и часть сайтов блокируемых без решения суда
# Поддерживается подключение по UDP и TCP 
# Используется 443 порт вместо 1194 для обхода блокировки по порту
#
# Версия от 13.08.2024
# https://github.com/GubernievS/AntiZapret-VPN
#
# Протестировано на Debian 10 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
#
# Установка:
# 1. Устанавливать только на чистую Ubuntu 20.04 или Debian 10 (Внимание! Debian 10 уже устаревшая и возможно не безопасная, тк обновления безопасности прекращены с 30 июня 2022 года)
# 2. Загрузить и распаковать архив https://github.com/GubernievS/AntiZapret-VPN/archive/refs/heads/main.zip
# 3. Папку из архива setup загрузить на сервер в папку root (например по SFTP через программу FileZilla)
# 4. В консоли под root выполнить:
# chmod +x setup/setup.sh && setup/setup.sh
# 5. Скопировать файл antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /root/easy-rsa-ipsec/CLIENT_KEY
#

#
# Обновляем систему
apt update && apt upgrade -y && apt autoremove -y

#
# Ставим необходимые пакеты
apt install bash ipcalc sipcalc gawk idn iptables ferm openvpn knot-resolver inetutils-ping curl wget ca-certificates openssl host dnsutils bsdmainutils procps unattended-upgrades nano vim-tiny git python3-pip socat -y
pip3 install dnslib

#
# Обновляем antizapret до последней версии из репозитория
git clone https://bitbucket.org/anticensority/antizapret-pac-generator-light.git /root/antizapret

#
# Add knot-resolver CZ.NIC repository. It's newer and less buggy than in Debian repos.
cd /tmp
curl https://secure.nic.cz/files/knot-resolver/knot-resolver-release.deb -o knot-resolver-release.deb
dpkg -i knot-resolver-release.deb
apt update
apt -o Dpkg::Options::="--force-confold" -y full-upgrade

#
# Clean package cache and remove the lists
apt autoremove -y && apt clean
rm /var/lib/apt/lists/* || true

#
# Копируем нужные файлы
find /root/setup -name '*.gitkeep' -delete
cp -r /root/setup/* / 
rm -r /root/setup

#
# Выставляем разрешения на запуск скриптов
find /root -name "*.sh" -execdir chmod u+x {} +
chmod +x /root/dnsmap/proxy.py
chmod +x /root/easy-rsa-ipsec/easyrsa3/easyrsa

#
# systemd-nspawn, which is used in mkosi, will by default mount (or copy?)
# host resolv.conf. We don't need that.
umount /etc/resolv.conf || true
mv /etc/resolv.conf_copy /etc/resolv.conf

#
# Обновляем process.sh в antizapret
mv -f /root/antizapret-process.sh /root/antizapret/process.sh

#
# Run all needed service on boot
systemctl enable systemd-networkd
systemctl enable kresd@1
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable dnsmap
systemctl enable openvpn-generate-keys
systemctl enable openvpn-server@antizapret
systemctl enable openvpn-server@antizapret-tcp

#
# Добавляем свои адреса в исключения и адреса из https://bitbucket.org/anticensority/russian-unlisted-blocks/src/master/readme.txt
sh -c "echo 'youtube.com
googlevideo.com
ytimg.com
ggpht.com
googleapis.com
gstatic.com
gvt1.com
gvt2.com
gvt3.com
digitalocean.com
strava.com
adguard-vpn.com
signal.org
tor.eff.org
news.google.com
play.google.com
twimg.com
bbc.co.uk
bbci.co.uk
radiojar.com
xvideos.com
doubleclick.net
windscribe.com
vpngate.net
rebrand.ly
adguard.com
antizapret.prostovpn.org
avira.com
mullvad.net
invent.kde.org
s-trade.com
ua
is.gd
1plus1tv.ru
linktr.ee
is.gd
anicult.org
12putinu.net
padlet.com' > /root/antizapret/config/include-hosts-custom.txt"

#
# Удаляем исключения из исключений
sed -i "/\b\(youtube\|youtu\|ytimg\|ggpht\|googleusercontent\|cloudfront\|ftcdn\)\b/d" /root/antizapret/config/exclude-hosts-dist.txt
sed -i "/\b\(googleusercontent\|cloudfront\|deviantart\)\b/d" /root/antizapret/config/exclude-regexp-dist.awk

#
# Добавляем AdGuard DNS для блокировки рекламы, отслеживающих модулей и фишинга
sh -c "echo \"\npolicy.add(policy.all(policy.FORWARD({'94.140.14.14'})))\npolicy.add(policy.all(policy.FORWARD({'94.140.15.15'})))\" >> /etc/knot-resolver/kresd.conf"

#
# Перезагружаем
reboot

#
# Забираем ovpn файлы подключений из /root/easy-rsa-ipsec/CLIENT_KEY