# AntiZapret-VPN

Скрипт для автоматического развертывания AntiZapret VPN **! ВЕРСИЯ БЕЗ КОНТЕЙНЕРА !**\
\+ Разблокирован YouTube и часть сайтов блокируемых без решения суда

Поддерживается подключение по UDP и TCP\
Используется 443 порт вместо 1194 для обхода блокировки по порту

Протестировано на Ubuntu 20.04 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка:
1. Устанавливать только на чистую Ubuntu 20.04
2. Загрузить и распаковать архив https://github.com/GubernievS/AntiZapret-VPN/archive/refs/heads/main.zip
3. Папку из архива setup загрузить на сервер в папку root (например по SFTP через программу FileZilla)
4. В консоли под root выполнить:
```sh
chmod +x setup/setup.sh && setup/setup.sh
```
5. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /root/easy-rsa-ipsec/CLIENT_KEY
***
Обсуждение скрипта\
https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270
***
### Обновления с AntiZapret-VPN-Container
Для обновления с версии AntiZapret-VPN-Container надо создать бекап ключей и настроек подключения, в консоли под root выполнить команды:
```sh
sudo lxc file pull -r -p antizapret-vpn/etc/openvpn/server/keys backup/etc/openvpn/server
sudo lxc file pull -r -p antizapret-vpn/root/easy-rsa-ipsec/easyrsa3/pki backup/root/easy-rsa-ipsec/easyrsa3
sudo lxc file pull -r -p antizapret-vpn/root/easy-rsa-ipsec/CLIENT_KEY backup/root/easy-rsa-ipsec
```
В папке root/backup будут лежат файлы для переноса ключей и настроек подключения, содержимое этой папки нужно сохранить на локальном компьютере и перенести на новый сервер в папку setup до запуска установки\
В файлах ovpn в строке remote нужно изменить IP адрес на адрес нового сервера, если вы обновляете тот же сервер то обновлять IP адрес не нужно
