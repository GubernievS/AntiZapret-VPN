# AntiZapret-VPN

Скрипт для автоматического развертывания AntiZapret VPN **! ВЕРСИЯ БЕЗ КОНТЕЙНЕРА !**\
\+ Разблокирован YouTube и часть сайтов блокируемых без решения суда

Поддерживается подключение по UDP и TCP\
Используется 443 порт вместо 1194 для обхода блокировки по порту

Протестировано на Ubuntu 20.04/Ubuntu 22.04/Debian 11 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка:
1. Устанавливать только на чистую Ubuntu 20.04/Ubuntu 22.04/Debian 11
2. Загрузить и распаковать архив https://github.com/GubernievS/AntiZapret-VPN/archive/refs/heads/main.zip
3. Папку из архива setup загрузить на сервер в папку root (например по SFTP через программу FileZilla)
4. В консоли под root выполнить:
```sh
chmod +x setup/setup.sh && setup/setup.sh
```
5. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /etc/openvpn/client
***
Обсуждение скрипта\
https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270
