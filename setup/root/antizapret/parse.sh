#!/bin/bash
set -e

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

echo "Parse AntiZapret VPN files:"

export LC_ALL=C

cd /root/antizapret

rm -f temp/*
rm -f result/*

source /root/antizapret/setup

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" ]]; then
	echo "IPs..."

	# Обрабатываем конфигурационные файлы
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' config/exclude-ips.txt | sort -u > temp/exclude-ips.txt
	shopt -s nullglob
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/*-ips.txt config/include-ips.txt | sort -u > temp/include-ips.txt
	shopt -u nullglob

	# Убираем IP-адреса из исключений
	grep -vFxf temp/exclude-ips.txt temp/include-ips.txt > temp/ips.txt || > temp/ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/ips.txt > result/ips.txt

	# Выводим результат
	echo "$(wc -l < result/ips.txt) - ips.txt"

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
	# Очищаем кэш knot-resolver
	count=$(echo 'cache.clear()' | socat - /run/knot-resolver/control/1 | grep -oE '[0-9]+')
	echo "DNS cache cleared: $count entries"

	echo "AdBlock-hosts..."

	# Обрабатываем список с рекламными доменами для блокировки
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/include-adblock-hosts.txt config/include-adblock-hosts.txt > temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/exclude-adblock-hosts.txt config/exclude-adblock-hosts.txt > temp/exclude-adblock-hosts.txt

	# Обрабатываем список с рекламными доменами для блокировки от AdGuard
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed '/^[0-9.]*$/d' >> temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки от AdGuard
	sed -n '/\*/!s/^@@||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed '/^[0-9.]*$/d' >> temp/exclude-adblock-hosts.txt

	# Обрабатываем список с рекламными доменами для блокировки от OISD
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/oisd.txt >> temp/include-adblock-hosts.txt

	# Удаляем дубли и сортируем
	sort -u temp/include-adblock-hosts.txt > result/include-adblock-hosts.txt
	sort -u temp/exclude-adblock-hosts.txt > result/exclude-adblock-hosts.txt

	# Выводим результат
	echo "$(wc -l < result/include-adblock-hosts.txt) - include-adblock-hosts.txt"
	echo "$(wc -l < result/exclude-adblock-hosts.txt) - exclude-adblock-hosts.txt"

	# Создаем файл для Knot Resolver
	echo -e '$TTL 3600\n@ SOA . . (0 0 0 0 0)' > result/deny.rpz
	sed 's/$/ CNAME ./; p; s/^/*./' result/include-adblock-hosts.txt >> result/deny.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-adblock-hosts.txt >> result/deny.rpz
	sed '/^;/d; /^$/d' download/rpz.txt >> result/deny.rpz

	# Обновляем файл в Knot Resolver только если файл deny.rpz изменился
	if [[ -f result/deny.rpz ]] && ! diff -q result/deny.rpz /etc/knot-resolver/deny.rpz; then
		cp -f result/deny.rpz /etc/knot-resolver/deny.rpz.tmp
		mv -f /etc/knot-resolver/deny.rpz.tmp /etc/knot-resolver/deny.rpz
	fi

	echo "Hosts..."

	# Обрабатываем конфигурационные файлы
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/exclude-hosts.txt config/exclude-hosts.txt | sort -u > result/exclude-hosts.txt
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/include-hosts.txt config/include-hosts.txt > temp/include-hosts.txt

	# Обрабатываем список заблокированных ресурсов из github.com/zapret-info
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	cut -d ';' -f 2 download/dump.csv | \
	iconv -f cp1251 -t utf8 | \
	grep -P '\.[а-яА-Яa-zA-Z]' | \
	sed -E 's/^[[:punct:]]+//; s/[[:punct:]]+$//' | \
	CHARSET=UTF-8 idn --no-tld >> temp/include-hosts.txt

	# Обрабатываем список заблокированных ресурсов из antifilter.download
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	sed -e 's/\.$//' -e 's/"//g' download/domains.lst | \
	CHARSET=UTF-8 idn --no-tld >> temp/include-hosts.txt

	# Удаляем не существующие домены и лишние поддомены
	grep -vFxf download/nxdomain.txt temp/include-hosts.txt | \
	sed -E '/\..*\./ s/^([-0-9a-zA-Z]{1,2}|www|msk|spb)[0-9]*\.//' | sort -u > temp/include-hosts2.txt

	# Удаляем лишние домены
	sed -e 's/$/$/' temp/include-hosts2.txt > temp/include-hosts3.txt
	sed -e 's/^/./' temp/include-hosts3.txt > temp/exclude-patterns.txt
	grep -vFf temp/exclude-patterns.txt temp/include-hosts3.txt > temp/include-hosts4.txt

	if [[ "$ROUTE_ALL" = "y" ]]; then
		# Пустим все домены через AntiZapret VPN
		echo '.' > result/include-hosts.txt
		# Удаляем лишние домены
		sed -e 's/^/./' -e 's/$/$/' result/exclude-hosts.txt > temp/exclude-patterns2.txt
		grep -Ff temp/exclude-patterns2.txt temp/include-hosts4.txt > temp/include-hosts5.txt
		sed 's/\$$//' temp/include-hosts5.txt >> result/include-hosts.txt
	else
		sed 's/\$$//' temp/include-hosts4.txt > result/include-hosts.txt
	fi

	# Выводим результат
	echo "$(wc -l < result/include-hosts.txt) - include-hosts.txt"
	echo "$(wc -l < result/exclude-hosts.txt) - exclude-hosts.txt"

	# Создаем файл для Knot Resolver
	echo -e '$TTL 3600\n@ SOA . . (0 0 0 0 0)' > result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME ./; t; s/$/ CNAME ./; p; s/^/*./' result/include-hosts.txt >> result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME rpz-passthru./; t; s/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-hosts.txt >> result/proxy.rpz

	# Обновляем файл в Knot Resolver только если файл proxy.rpz изменился
	if [[ -f result/proxy.rpz ]] && ! diff -q result/proxy.rpz /etc/knot-resolver/proxy.rpz; then
		cp -f result/proxy.rpz /etc/knot-resolver/proxy.rpz.tmp
		mv -f /etc/knot-resolver/proxy.rpz.tmp /etc/knot-resolver/proxy.rpz
	fi
fi

exit 0