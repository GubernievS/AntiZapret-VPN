# AntiZapret-VPN (версия без контейнера)

Скрипт для автоматического развертывания AntiZapret VPN + обычный VPN

Через AntiZapret VPN работают только:
- Заблокированные сайты из единого реестра РФ, список автоматически обновляется раз в 6 часов
- Сайты к которым ограничивается доступ без судебного решения (например youtube.com) и сайты ограничивающие доступ из РФ (например intel.com, chatgpt.com), список предзаполнен и доступен для ручного редактирования

Все остальные сайты работают через вашего провайдера с максимальной доступной вам скоростью

Через обычный VPN доступны все сайты, доступные с вашего хостинга

AntiZapret VPN + обычный VPN работают через OpenVPN\
Поддерживается подключение по UDP и TCP\
Используются 80 и 443 порты для обхода блокировок по портам

При подключении используется AdGuard DNS для блокировки рекламы, отслеживающих модулей и фишинга

За основу взяты [эти исходники](https://bitbucket.org/anticensority/antizapret-vpn-container/src/master) разработанные ValdikSS

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
3. Дождаться перезагрузки сервера и скопировать файлы *.ovpn с сервера из папки /etc/openvpn/client
4. (Опционально) Включить DCO
5. (Опционально) Добавить клиентов
***
Если у вас Ubuntu 24.04 или Debian 12, или вы [вручную обновили](https://community.openvpn.net/openvpn/wiki/OpenvpnSoftwareRepos) OpenVPN до версии 2.6+ то для включения [DCO](https://community.openvpn.net/openvpn/wiki/DataChannelOffload) (снижает нагрузку на cpu и увеличивает скорость передачи) в терминале под root выполнить: 
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
./add-client.sh [имя_пользователя]
```
Для удаления клиента в терминале под root выполнить:
```sh
./delete-client.sh [имя_пользователя]
```
Пользовательские ключи хранятся в файлах antizapret-имя_пользователя.*
***
Команды для настройки антизапрета описаны в самом скрипте в комментариях
***
Обсуждение скрипта [тут](https://ntc.party/t/скрипт-для-автоматического-развертывания-antizapret-vpn-новая-версия-без-контейнера-youtube/9270)
***
Инструкция по настройке на роутерах [Keenetic](./Keenetic.md) и [TP-Link](./TP-Link.md)
***
Хостинги для VPN принимающие рубли: [vdsina.com](https://www.vdsina.com/?partner=9br77jaat2) со скидкой 10% и [aeza.net](https://aeza.net/?ref=529527) с бонусом 15% (бонус действует 24ч)

