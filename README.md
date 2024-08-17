# AntiZapret-VPN

Скрипт для автоматического развертывания AntiZapret VPN **! ВЕРСИЯ БЕЗ КОНТЕЙНЕРА !**\
\+ Разблокирован YouTube и часть сайтов блокируемых без решения суда

Поддерживается подключение по UDP и TCP\
Используется 443 порт вместо 1194 для обхода блокировки по порту

Протестировано на Ubuntu 20.04/Ubuntu 22.04/Debian 11/Debian 12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка:
1. Устанавливать только на чистую Ubuntu 20.04+ или Debian 11+
4. В консоли под root выполнить:
```sh
apt-get update && apt-get install -y git
git clone https://github.com/GubernievS/AntiZapret-VPN.git
mv ./AntiZapret-VPN/setup /root
rm -rf ./AntiZapret-VPN
chmod +x setup/setup.sh && setup/setup.sh
```
5. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /etc/openvpn/client
***
Обсуждение скрипта\
https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270
