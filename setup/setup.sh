#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
#
# Скрипт для автоматического развертывания AntiZapret VPN
# + Разблокирован YouTube и часть сайтов блокируемых без решения суда
# Поддерживается подключение по UDP и TCP 
# Используется 443 порт вместо 1194 для обхода блокировки по порту
#
# Версия от 15.08.2024 fix
# https://github.com/GubernievS/AntiZapret-VPN
#
# Протестировано на Ubuntu 20.04 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
#
# Установка:
# 1. Устанавливать только на чистую Ubuntu 20.04
# 2. Загрузить и распаковать архив https://github.com/GubernievS/AntiZapret-VPN/archive/refs/heads/main.zip
# 3. Папку из архива setup загрузить на сервер в папку root (например по SFTP через программу FileZilla)
# 4. В консоли под root выполнить:
# chmod +x setup/setup.sh && setup/setup.sh
# 5. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /etc/openvpn/client
#
# Обсуждение скрипта
# https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270
#
# Команды для настройки антизапрета
#
# Изменить файл с личным списком антизапрета include-hosts-custom.txt
# nano /root/antizapret/config/include-hosts-custom.txt
# Потом выполните команду для обновления списка антизапрета
# /root/antizapret/doall.sh
#
# Изменить конфигурацию OpenVpn сервера с UDP
# nano /etc/openvpn/server/antizapret.conf
# Потом перезапустить OpenVpn сервер
# service openvpn restart
#
# Изменить конфигурацию OpenVpn сервера с TCP
# nano /etc/openvpn/server/antizapret-tcp.conf
# Потом перезапустить OpenVpn сервер
# service openvpn-tcp restart
#
# Посмотреть статистику подключений OpenVpn c UDP (выход Ctrl+X)
# nano /etc/openvpn/server/logs/status.log -v
#
# Посмотреть статистику подключений OpenVpn c TCP (выход Ctrl+X)
# nano /etc/openvpn/server/logs/status-tcp.log -v
#
# Для отключения подключений к OpenVpn по TCP выполните команду
# systemctl disable openvpn-server@antizapret-tcp
#

#
# Обновляем систему
apt update -y && apt upgrade -y && apt autoremove -y

#
# Ставим необходимые пакеты
apt install -y --allow-unauthenticated ipcalc sipcalc gawk idn iptables ferm openvpn knot-resolver inetutils-ping curl wget ca-certificates openssl host dnsutils bsdmainutils procps unattended-upgrades nano vim-tiny git python3-dnslib

#
# Обновляем antizapret до последней версии из репозитория
git clone https://bitbucket.org/anticensority/antizapret-pac-generator-light.git /root/antizapret

#
# Исправляем шаблон для корректной работы gawk начиная с версии 5
sed -i "s/\\\_/_/" /root/antizapret/parse.sh

#
# Скачиваем Easy-RSA 3
curl -L https://github.com/OpenVPN/easy-rsa/releases/download/v3.2.0/EasyRSA-3.2.0.tgz | tar -xz
mv /root/EasyRSA-3.2.0/ /root/easyrsa3/

#
# Add knot-resolver CZ.NIC repository. It's newer and less buggy than in Debian repos.
cd /tmp
curl https://secure.nic.cz/files/knot-resolver/knot-resolver-release.deb -o knot-resolver.deb
dpkg -i knot-resolver.deb
apt update -y --allow-insecure-repositories
apt -o Dpkg::Options::="--force-confold" -y full-upgrade --allow-unauthenticated

#
# Clean package cache and remove the lists
apt autoremove -y && apt clean
rm -f /var/lib/apt/lists/* || true
rm -f /tmp/* || true

#
# Копируем нужные файлы
find /root/setup -name '*.gitkeep' -delete
cp -r /root/setup/* / 
rm -r /root/setup

#
# Выставляем разрешения на запуск скриптов
find /root -name "*.sh" -execdir chmod u+x {} +
chmod +x /root/dnsmap/proxy.py
chmod +x /root/easyrsa3/easyrsa

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
systemctl unmask systemd-networkd.service
systemctl enable systemd-networkd
systemctl enable kresd@1
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable dnsmap
systemctl enable openvpn-generate-keys
systemctl enable openvpn-server@antizapret
systemctl enable openvpn-server@antizapret-tcp

#
# Добавляем свои адреса в исключения и адреса из:
# Внереестровые блокировки  - https://bitbucket.org/anticensority/russian-unlisted-blocks/src/master/readme.txt
# Ограничивают доступ из РФ - https://github.com/dartraiden/no-russia-hosts/blob/master/hosts.txt
echo "youtube.com
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
intel.com
nordvpn.com
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
padlet.com
tlsext.com" > /root/antizapret/config/include-hosts-custom.txt

#
# Удаляем исключения из исключений
echo "" > /root/antizapret/config/exclude-hosts-dist.txt
#sed -i "/\b\(youtube\|youtu\|ytimg\|ggpht\|googleusercontent\|cloudfront\|ftcdn\)\b/d" /root/antizapret/config/exclude-hosts-dist.txt
sed -i "/\b\(googleusercontent\|cloudfront\|deviantart\)\b/d" /root/antizapret/config/exclude-regexp-dist.awk

#
# Добавляем AdGuard DNS для блокировки рекламы, отслеживающих модулей и фишинга
echo "
policy.add(policy.all(policy.FORWARD({'94.140.14.14'})))
policy.add(policy.all(policy.FORWARD({'94.140.15.15'})))" >> /etc/knot-resolver/kresd.conf

#
# Перезагружаем
reboot

#
# Забираем ovpn файлы подключений из /etc/openvpn/client