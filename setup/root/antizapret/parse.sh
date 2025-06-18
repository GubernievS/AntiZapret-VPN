#!/bin/bash
set -e

echo "Parse AntiZapret VPN files:"

export LC_ALL=C

cd /root/antizapret

rm -f temp/*
rm -f result/*

for file in config/*; do
	if [[ -f "$file" ]]; then
		# Если последний символ не новая строка - добавляем её
		if [[ "$(tail -c1 "$file")" != $'\n' ]]; then
			echo >> "$file"
		fi
	fi
done

source /root/antizapret/setup

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" ]]; then
	echo "IPs..."

	# Обрабатываем конфигурационные файлы
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-ips.txt | sort -u > temp/exclude-ips.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-ips.txt download/*-ips.txt | sort -u > temp/include-ips.txt

	# Убираем IP-адреса из исключений
	grep -vFxf temp/exclude-ips.txt temp/include-ips.txt > temp/ips.txt || > temp/ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/ips.txt > result/ips.txt

	# Выводим результат
	wc -l result/ips.txt

	# Создаем файл для OpenVPN и файлы маршрутов для роутеров
	echo -n > result/DEFAULT
	[[ "$ALTERNATIVE_IP" == "y" ]] && IP="172" || IP="10"
	echo -e "route 0.0.0.0 128.0.0.0 net_gateway\nroute 128.0.0.0 128.0.0.0 net_gateway\nroute ${IP}.29.0.0 255.255.248.0\nroute ${IP}.30.0.0 255.254.0.0" > result/tp-link-openvpn-routes.txt
	echo -e "route ADD DNS_IP_1 MASK 255.255.255.255 ${IP}.29.8.1\nroute ADD DNS_IP_2 MASK 255.255.255.255 ${IP}.29.8.1\nroute ADD ${IP}.30.0.0 MASK 255.254.0.0 ${IP}.29.8.1" > result/keenetic-wireguard-routes.txt
	GATEWAY="${IP}.29.8.1"
	while read -r line
	do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
		echo "push \"route ${IP} ${MASK}\"" >> result/DEFAULT
		echo "route ${IP} ${MASK}" >> result/tp-link-openvpn-routes.txt
		echo "route ADD ${IP} MASK ${MASK} ${GATEWAY}" >> result/keenetic-wireguard-routes.txt
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

	# Обрабатываем список с рекламными доменами для блокировки от OISD
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' download/oisd.txt >> temp/include-adblock-hosts.txt

	# Удаляем дубли и сортируем
	sort -u temp/include-adblock-hosts.txt > result/include-adblock-hosts.txt
	sort -u temp/exclude-adblock-hosts.txt > result/exclude-adblock-hosts.txt

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
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-hosts.txt download/exclude-hosts.txt | sort -u > result/exclude-hosts.txt
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
	grep -vFxf download/nxdomain.txt temp/include-hosts.txt > temp/include-hosts2.txt || > temp/include-hosts2.txt

	if [[ "$ROUTE_ALL" = "y" ]]; then
		# Пустим все домены через AntiZapret VPN
		echo '.' >> temp/include-hosts2.txt
		# Удаляем лишнее, дубли и сортируем
		sed -e 's/\./\\./g' -e 's/^/\\./' -e 's/$/$/' result/exclude-hosts.txt > temp/exclude-patterns.txt
		grep -Ef temp/exclude-patterns.txt temp/include-hosts2.txt | sort -u > result/include-hosts.txt
	else
		# Удаляем дубли и сортируем
		sort -u temp/include-hosts2.txt > result/include-hosts.txt
	fi

	# Выводим результат
	wc -l result/include-hosts.txt
	wc -l result/exclude-hosts.txt

	# Создаем файл для Knot Resolver
	echo -e '$TTL 3600\n@ SOA . . (0 0 0 0 0)' > result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME ./; t; s/$/ CNAME ./; p; s/^/*./' result/include-hosts.txt >> result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME rpz-passthru./; t; s/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-hosts.txt >> result/proxy.rpz

	# Обновляем файл в Knot Resolver только если файл proxy.rpz изменился
	if [[ -f result/proxy.rpz ]] && ! diff -q result/proxy.rpz /etc/knot-resolver/proxy.rpz; then
		cp -f result/proxy.rpz /etc/knot-resolver/proxy.rpz.tmp
		mv -f /etc/knot-resolver/proxy.rpz.tmp /etc/knot-resolver/proxy.rpz
	fi

	# Очищаем кэш knot-resolver
	echo 'cache.clear()' | socat - /run/knot-resolver/control/1
fi

exit 0