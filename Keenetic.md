Для того чтобы подключение antizapret-\*.ovpn заработало как надо на роутерах Keenetic, надо в начало файла antizapret-\*.ovpn дописать:

```
pull-filter ignore block-outside-dns
route 1.1.1.1
route 8.8.8.8
```

В параметрах VPN-подключения поставить галочку: 'Получать маршруты от удаленной стороны'

В разделе 'Кабель Ethernet' (или 'Модем 3G/4G'), в опциях 'Параметры IPv4' поставить галочку 'Игнорировать DNSv4 интернет-провайдера'

В разделе 'Интернет-фильтры', на вкладке 'Контентный фильтр' поставить 'Режим фильтрации: Выключен'
Перейти на вкладку 'Настройка DNS', и нажимая 'Добавить сервер' добавить IP-адреса: 1.1.1.1 и 8.8.8.8