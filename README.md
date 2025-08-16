# AntiZapret VPN + полный VPN

| У автора есть собственный VPN-сервер. Вы можете приобрести готовое подключение к AntiZapret VPN или получить помощь в настройке своего сервера или роутера. Все подробности и стоимость [тут](https://t.me/antizapret_vpn/4) |
|------------------|

Скрипт для установки на [своём сервере](https://github.com/GubernievS/AntiZapret-VPN#где-купить-сервер) AntiZapret VPN и обычного VPN, работает по протоколам OpenVPN (есть патч для обхода блокировки), WireGuard и AmneziaWG

AntiZapret VPN реализует технологию [раздельного туннелирования](https://encyclopedia.kaspersky.ru/glossary/split-tunneling)

Через AntiZapret VPN работают только (список сайтов автоматически обновляется раз в сутки с 2:00 до 4:00 по времени сервера):
- Заблокированные Роскомнадзором сайты и IP-адреса (например discord.com)
- Сайты, доступ к которым ограничивается незаконно (например youtube.com)
- Сайты, ограничивающие доступ из России (например intel.com, chatgpt.com)

Все остальные сайты работают без VPN через вашего провайдера с максимальной доступной скоростью, не нарушая работу сайтов проверяющих наличие у вас Российского IP-адреса (госуслуги, банки, интернет-магазины, стриминговые сервисы и тд)

Список сайтов и IP-адресов для AntiZapret VPN предзаполнен и обновляется автором\
Также доступно ручное добавление собственных сайтов и IP-адресов (include-hosts.txt и include-ips.txt в папке /root/antizapret/config)

**Внимание!** Для правильной работы AntiZapret VPN нужно [отключить DNS в браузере](https://www.google.ru/search?q=отключить+DNS+в+браузере)

Через [полный VPN](https://www.kaspersky.ru/resource-center/definitions/what-is-a-vpn) работают все сайты, доступные с вашего сервера, что позволяет обходить все ограничения

Ваш сервер должен быть расположен за пределами России и стран бывшего Советского Союза, в противном случае разблокировка сайтов не гарантируется

**OpenVPN** (файлы \*.ovpn)\
Поддерживается подключение по UDP и TCP, а также возможность подключения только по UDP (\*-udp.ovpn) или только по TCP (\*-tcp.ovpn)\
Используются порты 50080 и 50443, а также резервные порты 80 и 443 для обхода блокировок портов\
OpenVPN позволяет нескольким клиентам использовать один и тот же файл подключения (\*.ovpn) для подключения к серверу, по умолчанию создается один клиент 'antizapret-client'\
Если ваш провайдер блокирует протокол OpenVPN - установите патч для обхода блокировки протокола (только для UDP соединений)\
По умолчанию используется протокол шифрования AES-128-GCM, если ваше устройство не поддерживает аппаратное шифрование AES-NI, то рекомендуется попробовать в файле подключения (\*.ovpn) заменить AES-128-GCM на CHACHA20-POLY1305\
VPN-клиенты: [OpenVPN Connect](https://openvpn.net/client), [OpenVPN (Windows)](https://openvpn.net/community-downloads)

**WireGuard** (файлы \*-wg.conf)\
Поддерживается подключение по UDP, используются порты 51080 и 51443\
WireGuard не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-wg.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается один клиент 'antizapret-client'\
Если ваш провайдер блокирует протокол WireGuard - попробуйте использовать AmneziaWG\
При ошибке загрузки файла подключения необходимо сократить длину файла до 32 (Windows) или 15 (Linux/Android/iOS) символов и удалить скобки\
VPN-клиенты: [WireGuard](https://www.wireguard.com/install)

**AmneziaWG** (файлы \*-am.conf)\
Поддерживается подключение по UDP, используются порты 52080 и 52443\
AmneziaWG работает в [режиме обфускации Wireguard](https://habr.com/ru/companies/amnezia/articles/807539)\
AmneziaWG не позволяет нескольким клиентам использовать один и тот же файл подключения (\*-am.conf) для подключения к серверу, поэтому каждому клиенту необходимо создать свой личный файл подключения\
Файлы подключения клиентов для WireGuard и AmneziaWG создаются сразу, по умолчанию создается один клиент 'antizapret-client'\
Если ваш провайдер (встречается на мобильных) блокирует протокол AmneziaWG - попробуйте в настройке подключения поменять Jc на 3, 4 или 5\
Не используйте VPN-клиент AmneziaVPN - он подменяет DNS АнтиЗапрета на свои, из-за чего AntiZapret VPN не работает\
При ошибке загрузки файла подключения необходимо сократить длину имени файла до 32 (Windows) или 15 (Linux/Android/iOS) символов и удалить скобки\
VPN-клиенты: [AmneziaWG (Windows)](https://github.com/amnezia-vpn/amneziawg-windows-client/releases), [AmneziaWG (Android)](https://play.google.com/store/apps/details?id=org.amnezia.awg), [AmneziaWG (Apple)](https://apps.apple.com/ru/app/amneziawg/id6478942365)

За основу взяты [эти исходники](https://bitbucket.org/anticensority/antizapret-vpn-container/src/master) разработанные ValdikSS\
Скрипт отключает UFW и Firewalld, при необходимости их необходимо настроить и включить вручную\
Протестировано на Ubuntu 22.04/24.04 и Debian 11/12 - Процессор: 1 core, Память: 1 Gb, Хранилище: 10 Gb, Внешний IPv4

***

## Установка и обновление
1. Устанавливать только на Ubuntu 22.04/24.04 или Debian 11/12 (рекомендуется Ubuntu 24.04)
2. Для установки или обновления в терминале под root выполнить
```sh
bash <(wget -qO- --no-hsts --inet4-only https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup.sh)
```
3. Изменить настройки (или нажимать Enter для выбора значения по умолчанию):
	- Установить патч для обхода блокировки протокола OpenVPN (только для UDP соединений)
	- Включить OpenVPN DCO
	- Выбрать DNS для AntiZapret VPN и обычного VPN
	- Включить блокировку рекламы, трекеров и фишинга в AntiZapret VPN на основе правил AdGuard и OISD
	- Использовать альтернативные диапазоны IP-адресов: 172... вместо 10...
	- Использовать резервные порты 80 и 443 для OpenVPN
	- Включить подробные логи в OpenVPN
	- Разрешить нескольким клиентам подключаться к OpenVPN используя один и тот же файл подключения (\*.ovpn)
	- Включить защиту от перебора паролей SSH и защиту от сканирования и сетевых атак
	- Ограничить маршрутизацию через AntiZapret VPN только к IP-адресам из config/forward-ips.txt и result/route-ips.txt
	- Указать доменное имя для подключения к OpenVPN и WireGuard/AmneziaWG
	- Пустить все домены через AntiZapret VPN кроме российских доменов и доменов из config/exclude-hosts.txt
	- Добавить IP-адреса: голосовых серверов Discord, Telegram, Cloudflare, Amazon, Hetzner, DigitalOcean, OVH и тд
4. Дождаться перезагрузки сервера и скопировать файлы подключений (*.ovpn и *.conf) с сервера из подпапок /root/antizapret/client (например через MobaXtrem, FileZilla или WinSCP)\
После загрузки сервера, заблокированные сайты заработают через несколько минут
5. Установить дополнения:
	- [StatusOpenVPN](https://github.com/TheMurmabis/StatusOpenVPN) - статистика подключений и Telegram-бот
	- [AdminAntizapret](https://github.com/Kirito0098/AdminAntizapret) - управление и конфигурация
	- [TG-Bot-OpenVPN-Antizapret](https://github.com/VATAKATru61/TG-Bot-OpenVPN-Antizapret) - Telegram-бот (только OpenVPN)

***

## Настройка

### 1. Установить/удалить патч для обхода блокировки протокола OpenVPN (только для UDP соединений)
```sh
/root/antizapret/patch-openvpn.sh [0-2]
```

### 2. Включить/отключить [OpenVPN DCO](https://community.openvpn.net/openvpn/wiki/DataChannelOffload)
```sh
/root/antizapret/openvpn-dco.sh [y/n]
```
Включение заметно снижает нагрузку на CPU сервера и клиента - это экономит аккумулятор мобильных устройств и увеличивает скорость передачи данных через OpenVPN\
При включении OpenVPN DCO будут работать только алгоритмы шифрования AES-128-GCM, AES-256-GCM и CHACHA20-POLY1305\
Алгоритмы шифрования AES-128-CBC, AES-192-CBC и AES-256-CBC не поддерживаются и будут отключены

### 3. Добавить/удалить клиента
```sh
/root/antizapret/client.sh [1-8] [имя_клиента] [срок_действия]
```
Срок действия в днях - только для OpenVPN\
После добавления нового клиента скопируйте новые файлы подключений (*.ovpn и *.conf) с сервера из подпапок /root/antizapret/client

### 4. Добавить свои сайты в список АнтиЗапрета
```sh
nano /root/antizapret/config/include-hosts.txt
```
Добавлять нужно в файл /root/antizapret/config/include-hosts.txt только домены, например:
subdomain.example.com\
example.com\
com\
После этого нужно обновить список АнтиЗапрета
```sh
/root/antizapret/doall.sh
```

### 5. Исключить свои сайты из списка АнтиЗапрета
```sh
nano /root/antizapret/config/exclude-hosts.txt
```
Добавлять нужно в файл /root/antizapret/config/exclude-hosts.txt только домены, например:
subdomain.example.com\
example.com\
com\
После этого нужно обновить список АнтиЗапрета
```sh
/root/antizapret/doall.sh
```

### 6. Добавить свои IP-адреса в список АнтиЗапрета
```sh
nano /root/antizapret/config/include-ips.txt
```
Добавлять нужно в файл /root/antizapret/config/include-ips.txt только IP-адреса с маской A.B.C.D/M, например:\
8.8.8.8/32\
10.20.0.0/16\
20.30.40.0/24\
После этого нужно обновить список АнтиЗапрета
```sh
/root/antizapret/doall.sh
```
После обновления списка АнтиЗапрета, клиентам OpenVPN (antizapret-\*.ovpn) достаточно переподключиться к серверу\
А клиентам WireGuard/AmneziaWG нужно добавить новые IP-адреса через запятую в конфигурационные файлы (antizapret-\*.conf) в строке AllowedIPs

***

## Пообщаться
Обсуждение скрипта на [4pda.to](https://4pda.to/forum/index.php?showtopic=1095869) и [ntc.party](https://ntc.party/t/9270) (для просмотра 4pda и ntc нужен VPN)\
Приватная группа в [telegram](https://t.me/+XJwXHTmMvUk3NTli)

***

## Настройка на роутерах
OpenVPN на роутерах [Keenetic](./Keenetic.md), [TP-Link](./TP-Link.md) и [MikroTik](https://github.com/Kirito0098/AntiZapret-OpenVPN-Mikrotik)\
WireGuard/AmneziaWG на роутерах [Keenetic](https://4pda.to/forum/index.php?showtopic=1095869&view=findpost&p=133090948), [MikroTik](https://4pda.to/forum/index.php?showtopic=1095869&view=findpost&p=133091005) и еще [Mikrotik](https://github.com/Kirito0098/AntiZapret-WG-Mikrotik), [OpenWRT](https://4pda.to/forum/index.php?showtopic=1095869&view=findpost&p=133105107) (для просмотра 4pda нужен VPN) и еще [OpenWRT](https://telegra.ph/AntiZapret-WireGuardAmneziaWG-on-OpenWRT-03-16)

***

## Где купить сервер
Хорошие и быстрые сервера в Европе принимающие рубли:
- [vdsina.com](https://www.vdsina.com/?partner=9br77jaat2) (Нидерланды) - ссылка для регистрации с бонусом 10%
- [aeza.net](https://aeza.net/?ref=529527) (разные страны) - ссылка для регистрации с бонусом 15% если пополнение сделать в течении 24 часов с момента регистрации

Недорогие промо-сервера в Европе принимающие рубли:
- SWE-PROMO (Стокгольм) от [aeza.net](https://aeza.net/?ref=529527) - доступность для заказа SWE-PROMO можно отслеживать через [aezastatus_bot](https://t.me/aezastatus_bot)
- PROMO-Platinum (Франкфурт) от [h2.nexus](https://h2.nexus)

Регистрируясь и покупая по реферальным ссылкам Вы поддерживаете проект!

***

## FAQ

### 1. Как переустановить сервер и сохранить настройки и работоспособность ранее созданных файлов подключений OpenVPN (\*.ovpn) и WireGuard/AmneziaWG (\*.conf)?
Выполните команду
```sh
/root/antizapret/client.sh 8
```
И скачайте созданный файл /root/antizapret/backup\*.tar.gz\
Если команда выполнилась с ошибкой то скачайте с сервера папки: /root/antizapret/config /etc/openvpn/easyrsa3 /etc/wireguard\
Переустановите сервер\
Обратно на сервер в папку /root закачайте файл backup\*.tar.gz, или папки: config easyrsa3 wireguard \
Запустите скрипт установки

### 2. Как посмотреть активные соединения?

Посмотреть активные соединения и статистику OpenVPN можно в логах \*-status.log в папке /etc/openvpn/server/logs на сервере (файлы обновляются каждые 30 секунд)\
Посмотреть активные соединения и статистику WireGuard/AmneziaWG можно командой
```sh
wg show
```
Кроме этого, есть [сторонний проект](https://github.com/TheMurmabis/StatusOpenVPN) для просмотра статистики через веб-интерфейс

### 3. Какие IP-адреса используются?

Клиенты обычного VPN = 10.28.0.0/22, 10.28.4.0/22, 10.28.8.0/24 (172.28.0.0/22, 172.28.4.0/22, 172.28.8.0/24)\
Клиенты AntiZapret VPN = 10.29.0.0/22, 10.29.4.0/22, 10.29.8.0/24 (172.29.0.0/22, 172.29.4.0/22, 172.29.8.0/24)\
DNS АнтиЗапрета = 10.29.0.1, 10.29.4.1, 10.29.8.1 (172.29.0.1, 172.29.4.1, 172.29.8.1)\
Подменные IP АнтиЗапрета = 10.30.0.0/15 (172.30.0.0/15)\
Через запятую перечислены IP-адреса: OpenVPN UDP, OpenVPN TCP, WireGuard/AmneziaWG\
В скобках указаны альтернативные IP-адреса

### 4. Как запретить нескольким клиентам использовать один и тот же файл подключения (\*.ovpn) для одновременного подключения к серверу?

На сервере в папке /etc/openvpn/server во всех файлах .conf убрать строчки duplicate-cn\
Перезагрузить сервер

### 5. Как пересоздать все файлы подключений (\*.ovpn и \*.conf) в подпапках /root/antizapret/client?

Выполните команду
```sh
/root/antizapret/client.sh 7
```
В подпапках /root/antizapret/client будут пересозданы все файлы подключений

### 6. Как работает опциональная защита от сканирования и сетевых атак?

IP-адрес блокируется на 10 минут при нарушении следующих правил:
- Сканирование портов: более 10 попыток подключения с одного IP-адреса или суммарно со всех IPv4-адресов подсети /24 или со всех IPv6-адресов подсети /64 по разным портам и протоколам\
Если в течение минуты не было попыток подключения, лимит сбрасывается
- DDoS-атака: более 100 000 новых подключений с одного IP-адреса или суммарно со всех IPv4-адресов подсети /24 или со всех IPv6-адресов подсети /64 по разным портам и протоколам\
Если в течение 10 секунд не было попыток подключения, лимит сбрасывается

При попытке подключения с заблокированного IP-адреса или подсети блокировка продлевается до 10 минут\
Если подсеть или IP-адрес добавлен в список исключений, блокировка на него не распространяется

Отключен ответ на ping\
Отключен ответ о неудачной попытке подключения к закрытому порту сервера

Список заблокированных IPv4- и IPv6-адресов
```sh
ipset list antizapret-block | grep '\.' | sort -u 
ipset list antizapret-block6 | grep -E '.*:.*:.*:' | sort -u
```
Список отслеживаемых подключений по IPv4 и IPv6 за последнюю минуту
```sh
ipset list antizapret-watch | grep '\.' | sort -u
ipset list antizapret-watch6 | grep -E '.*:.*:.*:' | sort -u
```
Список исключений IPv4 и IPv6
```sh
ipset list antizapret-allow | grep '\.' | sort -u
ipset list antizapret-allow6 | grep -E '.*:.*:.*:' | sort -u
```

Можно добавить IPv4-адреса исключений в файл /root/antizapret/config/allow-ips.txt 
```sh
nano /root/antizapret/config/allow-ips.txt 
```
После этого нужно обновить списки IP-адресов
```sh
/root/antizapret/parse.sh ip
```

### 7. Как работает опциональная защита SSH?

Подключение по SSH блокируется на минуту с 4 попытки подключения с одного IP-адреса или суммарно со всех IPv4-адресов подсети /24 или со всех IPv6-адресов подсети /64\
Если в течение минуты с IP-адреса или подсети не было попыток подключения, лимит сбрасывается\
При попытке подключения с заблокированного IP-адреса или подсети блокировка продлевается на минуту

***
![Поблагодарить и поддержать](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)

Поблагодарить и поддержать проект можно на:

[cloudtips.ru](https://pay.cloudtips.ru/p/b3f20611)

[boosty.to](https://boosty.to/gubernievs)
