# AntiZapret VPN + обычный VPN

Скрипт для установки на своём сервере AntiZapret VPN и обычного VPN, работает по протоколам OpenVPN (есть патч для обхода блокировки), WireGuard и AmneziaWG

AntiZapret VPN реализует технологию [раздельного туннелирования](https://encyclopedia.kaspersky.ru/glossary/split-tunneling)

Через AntiZapret VPN работают только:
- Заблокированные сайты из единого реестра РФ, список которых автоматически обновляется раз в сутки
- Сайты, доступ к которым ограничивается без судебного решения (например, youtube.com)
- Сайты, ограничивающие доступ из России (например, intel.com, chatgpt.com)

Все остальные сайты работают без VPN через вашего провайдера с максимальной доступной скоростью, не нарушая работу сайтов проверяющих наличие у вас Российского IP-адреса (госуслуги, банки, онлайн-кинотеатры и тд)

Список сайтов для AntiZapret VPN предзаполнен (include-hosts-dist.txt)\
Также доступно ручное добавление собственных сайтов (include-hosts-custom.txt)

**Внимание!** Для правильной работы AntiZapret VPN нужно [отключить DNS в браузере](https://www.google.ru/search?q=отключить+DNS+в+браузере)

Через обычный VPN работают все сайты, доступные с вашего сервера, что позволяет обходить все ограничения

Ваш сервер должен находиться за пределами России, в противном случае разблокировка сайтов не гарантируется

AntiZapret VPN (antizapret-\*) и обычный VPN (vpn-\*) подключаются через VPN клиенты: [OpenVPN Connect](https://openvpn.net/client), [OpenVPN](https://openvpn.net/community-downloads), [WireGuard](https://www.wireguard.com/install), [Amnezia VPN](https://amnezia.org/ru/downloads), [AmneziaWG for Windows](https://github.com/amnezia-vpn/amneziawg-windows-client/releases)

**OpenVPN** (\*.ovpn)\
Поддерживается подключение по UDP и TCP, а также возможность подключения только по UDP (\*-udp.ovpn) или только по TCP (\*-tcp.ovpn)\
Используются порты 50080 и 50443, а также резервные порты 80 и 443 для обхода блокировок портов\
OpenVPN позволяет нескольким клиентам использовать один и тот же файл подключения (\*.ovpn) для подключения к серверу, по умолчанию создается один клиент: antizapret-client\
Если ваш провайдер блокирует протокол OpenVPN - установите патч для обхода блокировки протокола

**WireGuard** (\*-wg.conf)\
Поддерживается подключение по UDP, используются порты 51080 и 51443\
WireGuard не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-wg.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается три клиента: antizapret-client1, antizapret-client2, antizapret-client3\
Если ваш провайдер блокирует протокол WireGuard - попробуйте использовать клиент AmneziaWG

**AmneziaWG** (\*-am.conf)\
Поддерживается подключение по UDP, используются порты 52080 и 52443\
AmneziaWG работает в [режиме обфускации Wireguard](https://habr.com/ru/companies/amnezia/articles/807539)\
AmneziaWG не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-am.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается три клиента: antizapret-client1, antizapret-client2, antizapret-client3

По умолчанию используется быстрый Cloudflare DNS, опционально можно включить AdGuard DNS для блокировки рекламы, отслеживающих модулей и фишинга

За основу взяты [эти исходники](https://bitbucket.org/anticensority/antizapret-vpn-container/src/master) разработанные ValdikSS

Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка:
1. Устанавливать на чистую Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Ubuntu 24.04)
2. В терминале под root выполнить
```sh
apt update && apt install -y git && cd /root && git clone https://github.com/GubernievS/AntiZapret-VPN.git tmp && chmod +x tmp/setup.sh && tmp/setup.sh
```
3. Дождаться перезагрузки сервера и скопировать файлы подключений (*.ovpn и *.conf) с сервера из папки /root

Опционально можно:
1. Установить патч для обхода блокировки протокола OpenVPN
2. Включить OpenVPN DCO
3. Включить AdGuard DNS для: AntiZapret/обычного VPN (только при установке)
4. Использовать альтернативные диапазоны IP-адресов: 172... вместо 10... (только при установке)
5. Добавить клиентов (только после установки)
***
Установить патч для обхода блокировки протокола OpenVPN (работает только для UDP соединений)
```sh
./patch-openvpn.sh
```
***
Включить [OpenVPN DCO](https://community.openvpn.net/openvpn/wiki/DataChannelOffload) (заметно снижает нагрузку на CPU сервера и клиента - это экономит аккумулятор мобильных устройств и увеличивает скорость передачи данных через OpenVPN)
```sh
./enable-openvpn-dco.sh
```
Выключить OpenVPN DCO
```sh
./disable-openvpn-dco.sh
```
***
Добавить нового клиента (* - только для OpenVPN)
```sh
./add-client.sh [ov/wg] [имя_клиента] [срок_действия*]
```
Удалить клиента
```sh
./delete-client.sh [ov/wg] [имя_клиента]
```
После добавления нового клиента скопируйте новые файлы подключений (*.ovpn и *.conf) с сервера из папки /root
***
Добавить свои сайты в список антизапрета (include-hosts-custom.txt)
```sh
nano /root/antizapret/config/include-hosts-custom.txt
```
Добавлять нужно только домены, например:
>subdomain.example.com\
example.com\
com

После этого нужно обновить список антизапрета
```sh
/root/antizapret/doall.sh
```
***
Обсуждение скрипта на [ntc.party](https://ntc.party/t/9270) и [4pda.to](https://4pda.to/forum/index.php?showtopic=1095869)
***
Инструкция по настройке на роутерах [Keenetic](./Keenetic.md) и [TP-Link](./TP-Link.md)
***
### Где купить сервер?
Хостинги в Европе для VPN принимающие рубли: [vdsina.com](https://www.vdsina.com/?partner=9br77jaat2) с бонусом 10% и [aeza.net](https://aeza.net/?ref=529527) с бонусом 15% (если пополнение сделать в течении 24 часов с момента регистрации)
***
### FAQ
1. Как переустановить сервер и сохранить работоспособность ранее созданных файлов подключений OpenVPN (\*.ovpn), WireGuard (\*-wg.conf) и AmneziaWG (\*-am.conf)
> Скачать с сервера папки /root/easyrsa3 и /etc/wireguard (можно без подпапки templates)\
Переустановить сервер\
Обратно на сервер закачать папки /root/easyrsa3 и /etc/wireguard\
Запустить скрипт установки

2. Как посмотреть активные соединения?

> Посмотреть активные соединения OpenVPN можно в логах \*-status.log в папке /etc/openvpn/server/logs (Логи обновляются каждые 30 секунд)\
Посмотреть активные соединения WireGuard/AmneziaWG можно командой wg show

3. Какие IP используются?

> DNS антизапрета = 10.29.0.1\
Клиенты AntiZapret VPN = 10.29.0.0/16\
Клиенты обычного VPN = 10.28.0.0/16\
Подменные IP = 10.30.0.0/15
***
[![donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://pay.cloudtips.ru/p/b3f20611)

Поблагодарить и поддержать проект можно так же на карту: 5536914118120611
