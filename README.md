# AntiZapret-VPN

Скрипт для автоматического развертывания AntiZapret VPN ! ВЕРСИЯ БЕЗ КОНТЕЙНЕРА !\
\+ Разблокирован YouTube и часть сайтов блокируемых без решения суда

Поддерживается подключение по UDP и TCP\
Используется 443 порт вместо 1194 для обхода блокировки по порту

Протестировано на Debian 10 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb

Установка:
1. Устанавливать только на Debian 10
2. Загрузить и распаковать архив https://github.com/GubernievS/AntiZapret-VPN/archive/refs/heads/main.zip
3. Загрузить из архива папку setup на сервер в папку root по SFTP (например через программу FileZilla)
4. В консоли под root выполнить:
chmod +x setup/setup.sh && setup/setup.sh
5. Скопировать файл antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /root/easy-rsa-ipsec/CLIENT_KEY



Для обновления с версии AntiZapret-VPN-Container надо создать бекап ключей и в консоли под root выполнить:

sudo lxc file pull -r -p antizapret-vpn/etc/openvpn/server/keys backup/etc/openvpn/server
sudo lxc file pull -r -p antizapret-vpn/root/easy-rsa-ipsec/easyrsa3/pki backup/root/easy-rsa-ipsec/easyrsa3
sudo lxc file pull -r -p antizapret-vpn/root/easy-rsa-ipsec/CLIENT_KEY backup/root/easy-rsa-ipsec

В папке root/backup лежат файлы для переноса ключей, содержимое нужно перенести в папку setup до запуска установки