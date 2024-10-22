# AntiZapret VPN + обычный VPN

Скрипт для установки на [своём сервере](https://github.com/GubernievS/AntiZapret-VPN#где-купить-сервер) AntiZapret VPN и обычного VPN, работает по протоколам OpenVPN (есть патч для обхода блокировки), WireGuard и AmneziaWG

AntiZapret VPN реализует технологию [раздельного туннелирования](https://encyclopedia.kaspersky.ru/glossary/split-tunneling)

Через AntiZapret VPN работают только (список сайтов автоматически обновляется раз в сутки):
- Заблокированные Роскомнадзором сайты и IP-адреса (например discord.com)
- Сайты, доступ к которым ограничивается незаконно (например youtube.com)
- Сайты, ограничивающие доступ из России (например intel.com, chatgpt.com)

Все остальные сайты работают без VPN через вашего провайдера с максимальной доступной скоростью, не нарушая работу сайтов проверяющих наличие у вас Российского IP-адреса (госуслуги, банки, онлайн-кинотеатры и тд)

Список сайтов для AntiZapret VPN предзаполнен (include-hosts-dist.txt)\
Также доступно ручное добавление собственных сайтов (include-hosts-custom.txt)

**Внимание!** Для правильной работы AntiZapret VPN нужно [отключить DNS в браузере](https://www.google.ru/search?q=отключить+DNS+в+браузере)

Через обычный VPN работают все сайты, доступные с вашего сервера, что позволяет обходить все ограничения

Ваш сервер должен быть расположен за пределами России и стран бывшего Советского Союза, в противном случае разблокировка сайтов не гарантируется

AntiZapret VPN (файлы antizapret-\*) и обычный VPN (файлы vpn-\*) подключаются через VPN-клиенты: [OpenVPN Connect](https://openvpn.net/client), [OpenVPN (Windows)](https://openvpn.net/community-downloads), [WireGuard](https://www.wireguard.com/install), [Amnezia VPN](https://amnezia.org/ru/downloads), [AmneziaWG (Windows)](https://github.com/amnezia-vpn/amneziawg-windows-client/releases)

**OpenVPN** (файлы \*.ovpn)\
Поддерживается подключение по UDP и TCP, а также возможность подключения только по UDP (\*-udp.ovpn) или только по TCP (\*-tcp.ovpn)\
Используются порты 50080 и 50443, а также резервные порты 80 и 443 для обхода блокировок портов\
OpenVPN позволяет нескольким клиентам использовать один и тот же файл подключения (\*.ovpn) для подключения к серверу, по умолчанию создается один клиент 'antizapret-client'\
Если ваш провайдер блокирует протокол OpenVPN - установите патч для обхода блокировки протокола

**WireGuard** (файлы \*-wg.conf)\
Поддерживается подключение по UDP, используются порты 51080 и 51443\
WireGuard не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-wg.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается один клиент 'antizapret-client'\
Если ваш провайдер блокирует протокол WireGuard - попробуйте использовать клиент AmneziaWG

**AmneziaWG** (файлы \*-am.conf)\
Поддерживается подключение по UDP, используются порты 52080 и 52443\
AmneziaWG работает в [режиме обфускации Wireguard](https://habr.com/ru/companies/amnezia/articles/807539)\
AmneziaWG не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-am.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается один клиент 'antizapret-client'

По умолчанию используются DNS от [Cloudflare](https://ru.wikipedia.org/wiki/1.1.1.1) и [Google](https://ru.wikipedia.org/wiki/Google_Public_DNS), вместо них можно использовать:\
[AdGuard](https://adguard-dns.io/ru/public-dns.html) для блокировки рекламы, отслеживающих модулей и фишинга\
[Yandex (Базовый)](https://dns.yandex.ru) и [НСДИ](https://www.diera.ru/blog/nsdi-dns) если есть проблемы с загрузкой сайтов (например lampa.mx) с другими DNS


За основу взяты [эти исходники](https://bitbucket.org/anticensority/antizapret-vpn-container/src/master) разработанные ValdikSS

Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core Память: 1 Gb Хранилище: 10 Gb
***
### Установка и обновление
1. Устанавливать на чистую Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Ubuntu 24.04)
2. В терминале под root выполнить
```sh
apt update && apt install -y git && cd /root && git clone https://github.com/GubernievS/AntiZapret-VPN.git tmp && chmod +x tmp/setup.sh && tmp/setup.sh
```
3. Дождаться перезагрузки сервера и скопировать файлы подключений (*.ovpn или *.conf) с сервера из папки /root/vpn\
После загрузки сервера, заблокированные сайты заработают через несколько минут

Опционально можно:
1. Установить патч для обхода блокировки протокола OpenVPN
2. Включить OpenVPN DCO
3. Выбрать DNS для AntiZapret VPN и обычного VPN (только при установке)
4. Использовать альтернативные диапазоны IP-адресов: 172... вместо 10... (только при установке)
***
### Настройка
1. Установить патч для обхода блокировки протокола OpenVPN (работает только для UDP соединений)
```sh
./patch-openvpn.sh
```

2. Включить [OpenVPN DCO](https://community.openvpn.net/openvpn/wiki/DataChannelOffload) - это заметно снижает нагрузку на CPU сервера и клиента - это экономит аккумулятор мобильных устройств и увеличивает скорость передачи данных через OpenVPN
```sh
./enable-openvpn-dco.sh
```
>При включении OpenVPN DCO будут работать только алгоритмы шифрования AES-128-GCM и AES-256-GCM\
Алгоритмы шифрования AES-128-CBC, AES-192-CBC и AES-256-CBC не поддерживаются и будут отключены

3. Выключить OpenVPN DCO
```sh
./disable-openvpn-dco.sh
```

4. Добавить нового клиента (срок действия в днях - только для OpenVPN)
```sh
./add-client.sh [ov/wg] [имя_клиента] [срок_действия]
```

5. Удалить клиента
```sh
./delete-client.sh [ov/wg] [имя_клиента]
```
>После добавления нового клиента скопируйте новые файлы подключений (*.ovpn и *.conf) с сервера из папки /root/vpn

6. Добавить свои сайты в список антизапрета (include-hosts-custom.txt)
```sh
nano /root/antizapret/config/include-hosts-custom.txt
```
>Добавлять нужно только домены, например:
subdomain.example.com\
example.com\
com\
После этого нужно обновить список антизапрета
```sh
/root/antizapret/doall.sh
```

7. Добавить свои IP-адреса в список антизапрета (include-ips-custom.txt)
```sh
nano /root/antizapret/config/include-ips-custom.txt
```
>Добавлять нужно только IP-адреса с маской A.B.C.D/M, например:\
8.8.8.8/32\
10.20.0.0/16\
20.30.40.0/24\
После этого нужно обновить список антизапрета
```sh
/root/antizapret/doall.sh
```
>После этого клиентам OpenVPN (antizapret-\*.ovpn) достаточно переподключиться\
А созданным клиентам WireGuard/AmneziaWG нужно добавить эти IP-адреса через запятую в конфигурационные файлы (antizapret-\*.conf) в строке AllowedIPs
***
Обсуждение скрипта на [ntc.party](https://ntc.party/t/9270) и [4pda.to](https://4pda.to/forum/index.php?showtopic=1095869)
***
### Настройка на роутерах
OpenVPN на роутерах [Keenetic](./Keenetic.md) и [TP-Link](./TP-Link.md)\
WireGuard/AmneziaWG на роутерах [Keenetic](https://ntc.party/t/11998) и [MikroTik](https://ntc.party/t/11455)
***
### Где купить сервер
Хорошие сервера в Европе для VPN принимающие рубли (ссылки для регистрации): [vdsina.com](https://www.vdsina.com/?partner=9br77jaat2) с бонусом 10% и [aeza.net](https://aeza.net/?ref=529527) с бонусом 15% (если пополнение сделать в течении 24 часов с момента регистрации)
***
### FAQ
1. Как переустановить сервер и сохранить работоспособность ранее созданных файлов подключений OpenVPN (\*.ovpn) и WireGuard/AmneziaWG (\*.conf)?
> Для OpenVPN скачать с сервера папку /etc/openvpn/easyrsa3\
Для WireGuard/AmneziaWG скачать с сервера папку /etc/wireguard\
Переустановить сервер\
Обратно на сервер в папку /root закачать папки easyrsa3 и wireguard\
Запустить скрипт установки

2. Как посмотреть активные соединения?

> Посмотреть активные соединения OpenVPN можно в логах \*-status.log в папке /etc/openvpn/server/logs на сервере (Логи обновляются каждые 30 секунд)\
Посмотреть активные соединения и статистику WireGuard/AmneziaWG можно командой
```sh
wg show
```

3. Какие IP используются?

> DNS антизапрета = 10.29.0.1\
Клиенты AntiZapret VPN = 10.29.0.0/16\
Клиенты обычного VPN = 10.28.0.0/16\
Подменные IP = 10.30.0.0/15

4. Как запретить нескольким клиентам использовать один и тот же файл подключения (\*.ovpn) для одновременного подключения к серверу?

> На сервере в папке /etc/openvpn/server во всех файлах .conf убрать строчки duplicate-cn
Перезагрузить сервер

5. Как пересоздать все файлы подключений (\*.ovpn и \*.conf) в папке /root/vpn?

> Выполните команду
```sh
./add-client.sh recreate
```
>В папке /root/vpn будут пересозданы все файлы подключений, прошлые файлы подключений будут перемещены в папку /root/vpn/old

***
[![donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://pay.cloudtips.ru/p/b3f20611)

Поблагодарить и поддержать проект можно так же на карту: 5536914118120611