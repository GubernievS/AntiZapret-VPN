#!/bin/bash
set -e
#
# Скрипт для автоматического развертывания AntiZapret VPN
# + Разблокирован YouTube и часть сайтов блокируемых без решения суда
# Поддерживается подключение по UDP и TCP 
# Используется 443 порт вместо 1194 для обхода блокировки по порту
#
# Версия от 20.08.2024
# https://github.com/GubernievS/AntiZapret-VPN
#
# Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
#
# Установка:
# 1. Устанавливать на Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Debian 12)
# 2. В терминале под root выполнить:
# apt-get update && apt-get install -y git
# git clone https://github.com/GubernievS/AntiZapret-VPN.git antizapret-vpn
# chmod +x antizapret-vpn/setup.sh && antizapret-vpn/setup.sh
# 3. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /etc/openvpn/client
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
# nano /etc/openvpn/server/antizapret-udp.conf
# Потом перезапустить OpenVpn сервер
# service openvpn-udp restart
#
# Изменить конфигурацию OpenVpn сервера с TCP
# nano /etc/openvpn/server/antizapret-tcp.conf
# Потом перезапустить OpenVpn сервер
# service openvpn-tcp restart
#
# Посмотреть статистику подключений OpenVpn c UDP (выход Ctrl+X)
# nano /etc/openvpn/server/logs/status-udp.log -v
#
# Посмотреть статистику подключений OpenVpn c TCP (выход Ctrl+X)
# nano /etc/openvpn/server/logs/status-tcp.log -v
#
# Для отключения подключений к OpenVpn по TCP выполните команду
# systemctl disable openvpn-server@antizapret-tcp
#
# Для добавления нового пользователя выполните команду и введите имя
# /root/add-client.sh

#
# Обновляем систему
apt-get update && apt-get full-upgrade -y && apt-get autoremove -y

#
# Ставим необходимые пакеты
DEBIAN_FRONTEND=noninteractive apt-get install -y git curl iptables easy-rsa ferm gawk openvpn knot-resolver python3-dnslib idn sipcalc

#
# Обновляем antizapret до последней версии из репозитория
rm -r /root/antizapret || true
git clone https://bitbucket.org/anticensority/antizapret-pac-generator-light.git /root/antizapret

#
# Исправляем шаблон для корректной работы gawk начиная с версии 5
sed -i "s/\\\_/_/" /root/antizapret/parse.sh

#
# Копируем нужные файлы и папки, удаляем не нужные
find /root/antizapret-vpn -name '*.gitkeep' -delete
cp -r /root/antizapret-vpn/setup/* / 
rm -r /root/antizapret-vpn
mkdir /root/easyrsa3 || true

#
# Выставляем разрешения на запуск скриптов
find /root -name "*.sh" -execdir chmod u+x {} +
chmod +x /root/dnsmap/proxy.py

#
# Генерируем ключи и создаем ovpn файлы подключений в /etc/openvpn/client
/root/generate.sh

#
# Добавляем AdGuard DNS для блокировки рекламы, отслеживающих модулей и фишинга
echo "
policy.add(policy.all(policy.FORWARD({'94.140.14.14'})))
policy.add(policy.all(policy.FORWARD({'94.140.15.15'})))" >> /etc/knot-resolver/kresd.conf

#
# Запустим все необходимые службы при загрузке
systemctl enable kresd@1
systemctl enable antizapret-update.service
systemctl enable antizapret-update.timer
systemctl enable dnsmap
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp

##################################
#     Настраиваем исключения     #
##################################

#
# Добавляем свои адреса в исключения
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
adguard-vpn.com
signal.org" > /root/antizapret/config/include-hosts-custom.txt

#
# Ограничивают доступ из РФ - https://github.com/dartraiden/no-russia-hosts/blob/master/hosts.txt
# (список примерный и скопирован не весь)
echo "copilot.microsoft.com
4pda.to
habr.com
cisco.com
dell.com
dellcdn.com
fujitsu.com
deezer.com
fluke.com
formula1.com
intel.com
nordvpn.com
qualcomm.com
strava.com
openai.com
intercomcdn.com
oaistatic.com
oaiusercontent.com
chatgpt.com" >> /root/antizapret/config/include-hosts-custom.txt

#
# Внереестровые блокировки  - https://bitbucket.org/anticensority/russian-unlisted-blocks/src/master/readme.txt
echo "tor.eff.org
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
tlsext.com" >> /root/antizapret/config/include-hosts-custom.txt

#
# Удаляем исключения из исключений
#echo "" > /root/antizapret/config/exclude-hosts-dist.txt
sed -i "/\b\(youtube\|youtu\|ytimg\|ggpht\|googleusercontent\|cloudfront\|ftcdn\)\b/d" /root/antizapret/config/exclude-hosts-dist.txt
sed -i "/\b\(googleusercontent\|cloudfront\|deviantart\)\b/d" /root/antizapret/config/exclude-regexp-dist.awk

#
# Перезагружаем
reboot