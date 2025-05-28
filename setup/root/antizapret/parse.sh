#!/bin/bash
set -e

echo "Parse AntiZapret VPN files:"

cd /root/antizapret

rm -f temp/*
rm -f result/*

for file in config/*; do
	if [[ -f "$file" ]]; then
	# Проверяем есть ли символ новой строки в конце файла
		if [[ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]]; then
			echo "" >> "$file"  # Добавляем новую строку если её нет
		fi
	fi
done

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" ]]; then
	echo "IPs..."

	# Обрабатываем конфигурационные файлы
	LC_ALL=C sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-ips.txt | sort -u > temp/exclude-ips.txt
	LC_ALL=C sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-ips.txt download/include-ips.txt | sort -u > temp/include-ips.txt

	# Убираем IP-адреса из исключений
	grep -vFxf temp/exclude-ips.txt temp/include-ips.txt > temp/ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/ips.txt > result/ips.txt

	# Выводим результат
	wc -l result/ips.txt

	# Создаем файл для OpenVPN и файлы маршрутов для роутеров
	echo -n > result/DEFAULT
	echo -e "route 0.0.0.0 128.0.0.0 net_gateway\nroute 128.0.0.0 128.0.0.0 net_gateway\nroute 10.29.0.0 255.255.248.0\nroute 10.30.0.0 255.254.0.0" > result/tp-link-openvpn-routes.txt
	echo -e "route ADD DNS_IP_1 MASK 255.255.255.255 10.29.8.1\nroute ADD DNS_IP_2 MASK 255.255.255.255 10.29.8.1\nroute ADD 10.30.0.0 MASK 255.254.0.0 10.29.8.1" > result/keenetic-wireguard-routes.txt
	while read -r line
	do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
		echo "push \"route ${IP} ${MASK}\"" >> result/DEFAULT
		echo "route ${IP} ${MASK}" >> result/tp-link-openvpn-routes.txt
		echo "route ADD ${IP} MASK ${MASK} 10.29.8.1" >> result/keenetic-wireguard-routes.txt
	done < result/ips.txt

	# Обновляем файл в OpenVPN только если файл DEFAULT изменился
	if [[ -f result/DEFAULT ]] && ! diff -q result/DEFAULT /etc/openvpn/server/ccd/DEFAULT; then
		cp -f result/DEFAULT /etc/openvpn/server/ccd/DEFAULT
	fi

	# Создаем файл для WireGuard/AmneziaWG
	awk '{printf ", %s", $0}' result/ips.txt > result/ips

	# Обновляем файл в WireGuard/AmneziaWG только если файл ips изменился
	if [[ -f result/ips ]] && ! diff -q result/ips /etc/wireguard/ips; then
		cp -f result/ips /etc/wireguard/ips
	fi
fi

if [[ -z "$1" || "$1" == "host" || "$1" == "hosts" ]]; then
	echo "AdBlock hosts..."

	# Обрабатываем список с рекламными доменами для блокировки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-adblock-hosts.txt download/include-adblock-hosts.txt > temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-adblock-hosts.txt download/exclude-adblock-hosts.txt > temp/exclude-adblock-hosts.txt

	# Обрабатываем список с рекламными доменами для блокировки от AdGuard
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed '/^[0-9.]*$/d' >> temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки от AdGuard
	sed -n '/\*/!s/^@@||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed '/^[0-9.]*$/d' >> temp/exclude-adblock-hosts.txt

	# Обрабатываем список с рекламными доменами для блокировки от AdAway
	sed -E '/^\s*#/d; /^\s*$/d; /localhost/d; s/^127\.0\.0\.1 //g' download/adaway.txt >> temp/include-adblock-hosts.txt

	# Удаляем дубли и сортируем
	LC_ALL=C sort -u temp/include-adblock-hosts.txt > result/include-adblock-hosts.txt
	LC_ALL=C sort -u temp/exclude-adblock-hosts.txt > result/exclude-adblock-hosts.txt

	# Выводим результат
	wc -l result/include-adblock-hosts.txt
	wc -l result/exclude-adblock-hosts.txt

	# Создаем файл для Knot Resolver
	echo -e '$TTL 3600\n@ SOA . . (0 0 0 0 0)' > result/deny.rpz
	sed 's/$/ CNAME ./; p; s/^/*./' result/include-adblock-hosts.txt >> result/deny.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-adblock-hosts.txt >> result/deny.rpz
	sed '/^;/d' download/rpz.txt >> result/deny.rpz

	# Обновляем файл в Knot Resolver только если файл deny.rpz изменился
	if [[ -f result/deny.rpz ]] && ! diff -q result/deny.rpz /etc/knot-resolver/deny.rpz; then
		cp -f result/deny.rpz /etc/knot-resolver/deny.rpz.tmp
		mv -f /etc/knot-resolver/deny.rpz.tmp /etc/knot-resolver/deny.rpz
	fi

	echo "Hosts..."

	# Обрабатываем конфигурационные файлы
	LC_ALL=C sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-hosts.txt download/exclude-hosts.txt | sort -u > result/exclude-hosts.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-hosts.txt download/include-hosts.txt > temp/include-hosts.txt

	# Обрабатываем список заблокированных ресурсов из github.com/zapret-info
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	cut -d ';' -f 2 download/dump.csv | iconv -f cp1251 -t utf8 | \
	grep -P '\.[а-яА-Яa-zA-Z]' | \
	sed -e 's/^\*\.\?//' -e 's/\.$//' -e 's/"//g' | \
	CHARSET=UTF-8 idn --no-tld >> temp/include-hosts.txt

	# Обрабатываем список заблокированных ресурсов из antifilter.download
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	sed -e 's/\.$//' -e 's/"//g' download/domains.lst | CHARSET=UTF-8 idn --no-tld >> temp/include-hosts.txt

	# Удаляем не существующие домены
	grep -vFxf download/nxdomain.txt temp/include-hosts.txt > temp/include-hosts2.txt

	# Удаляем дубли и сортируем
	LC_ALL=C sort -u temp/include-hosts2.txt > temp/include-hosts3.txt

	# Удаляем домены у которых уже есть домены верхнего уровня
	grep -E '^([^.]*\.){6}[^.]*$' temp/include-hosts3.txt | sed 's/^/./' > temp/exclude-patterns.txt
	LC_ALL=C grep -vFf temp/exclude-patterns.txt temp/include-hosts3.txt | sort -u > temp/include-hosts4.txt

	grep -E '^([^.]*\.){5}[^.]*$' temp/include-hosts4.txt | sed 's/^/./' > temp/exclude-patterns2.txt
	LC_ALL=C grep -vFf temp/exclude-patterns2.txt temp/include-hosts4.txt | sort -u > temp/include-hosts5.txt

	grep -E '^([^.]*\.){4}[^.]*$' temp/include-hosts5.txt | sed 's/^/./' > temp/exclude-patterns3.txt
	LC_ALL=C grep -vFf temp/exclude-patterns3.txt temp/include-hosts5.txt | sort -u > temp/include-hosts6.txt

	grep -E '^([^.]*\.){3}[^.]*$' temp/include-hosts6.txt | sed 's/^/./' > temp/exclude-patterns4.txt
	LC_ALL=C grep -vFf temp/exclude-patterns4.txt temp/include-hosts6.txt | sort -u > temp/include-hosts7.txt

	grep -E '^([^.]*\.){2}[^.]*$' temp/include-hosts7.txt | sed 's/^/./' > temp/exclude-patterns5.txt
	LC_ALL=C grep -vFf temp/exclude-patterns5.txt temp/include-hosts7.txt | sort -u > temp/include-hosts8.txt

	grep -E '^([^.]*\.){1}[^.]*$' temp/include-hosts8.txt | sed 's/^/./' > temp/exclude-patterns6.txt
	LC_ALL=C grep -vFf temp/exclude-patterns6.txt temp/include-hosts8.txt | sort -u > temp/include-hosts9.txt

	grep -E '^([^.]*\.){0}[^.]*$' temp/include-hosts9.txt | sed 's/^/./' > temp/exclude-patterns7.txt
	LC_ALL=C grep -vFf temp/exclude-patterns7.txt temp/include-hosts9.txt | sort -u > result/include-hosts.txt

	# Выводим результат
	wc -l result/include-hosts.txt
	wc -l result/exclude-hosts.txt

	# Создаем файл для Knot Resolver
	echo -e '$TTL 3600\n@ SOA . . (0 0 0 0 0)' > result/proxy.rpz
	sed 's/$/ CNAME ./; p; s/^/*./' result/include-hosts.txt >> result/proxy.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-hosts.txt >> result/proxy.rpz

	# Обновляем файл в Knot Resolver только если файл proxy.rpz изменился
	if [[ -f result/proxy.rpz ]] && ! diff -q result/proxy.rpz /etc/knot-resolver/proxy.rpz; then
		cp -f result/proxy.rpz /etc/knot-resolver/proxy.rpz.tmp
		mv -f /etc/knot-resolver/proxy.rpz.tmp /etc/knot-resolver/proxy.rpz
	fi
fi

exit 0