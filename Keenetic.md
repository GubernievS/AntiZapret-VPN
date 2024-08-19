Для того чтобы подключение antizapret-client-udp.ovpn заработало как надо на роутерах Keenetic, надо в antizapret-client-udp.ovpn дописать:

```
pull-filter ignore block-outside-dns
route 192.168.1.1
```

Где 192.168.1.1 адрес ДНС сервера получаемый от провайдера на роутер, интернет фильтры на роутере должны быть выключены
