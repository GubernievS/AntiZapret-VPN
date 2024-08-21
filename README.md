# AntiZapret-VPN

Скрипт для автоматического развертывания AntiZapret VPN **(версия без контейнера)**\
\+ Разблокирован YouTube и часть сайтов блокируемых без решения суда

Поддерживается подключение по UDP и TCP\
Используется 443 порт вместо 1194 для обхода блокировки по порту

Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка и обновление:
1. Устанавливать на Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Ubuntu 24.04 или Debian 12)
2. В терминале под root выполнить:
```sh
apt-get update && apt-get install -y git
git clone https://github.com/GubernievS/AntiZapret-VPN.git antizapret-vpn
chmod +x antizapret-vpn/setup.sh && antizapret-vpn/setup.sh
```
3. Дождаться перезагрузки сервера и скопировать файлы antizapret-client-udp.ovpn и antizapret-client-tcp.ovpn с сервера из папки /etc/openvpn/client
4. (Опционально) Включить DCO
5. (Опционально) Добавить клиентов
***
Если у вас Ubuntu 24.04 или Debian 12, или вы [вручную обновили](https://community.openvpn.net/openvpn/wiki/OpenvpnSoftwareRepos) OpenVpn до версии 2.6+ то для включения [DCO](https://community.openvpn.net/openvpn/wiki/DataChannelOffload) (снижает нагрузку на ЦПУ и увеличивает скорость передачи) в терминале под root выполнить: 
```sh
./enable-openvpn-dco.sh
```
Для выключения DCO в терминале под root выполнить:
```sh
./disable-openvpn-dco.sh
```
***
Для добавления нового клиента в терминале под root выполнить:
```sh
./add-client.sh
```
Для удаления клиента в терминале под root выполнить:
```sh
./delete-client.sh
```
***
Команды для настройки антизапрета описаны в самом скрипте в комментариях
***
Обсуждение скрипта [тут](https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270)
***
Инструкция по настройке на роутерах [Keenetic](./Keenetic.md) и [TP-Link](./TP-Link.md)
***
[Хостинг для VPN со скидкой 10%](https://www.vdsina.com/?partner=9br77jaat2)
