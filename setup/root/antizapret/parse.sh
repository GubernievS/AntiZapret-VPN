#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

echo "Parse AntiZapret VPN files:"

rm -f temp/*

if [[ -z "$1" || "$1" == "ip" ]]; then
	echo "IPs..."

	# Обрабатываем конфигурационные файлы
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-ips.txt | sort -u > temp/exclude-ips.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-ips.txt download/include-ips.txt | sort -u > temp/include-ips.txt

	# Убираем IP-адреса из исключений
	grep -vFxf temp/exclude-ips.txt temp/include-ips.txt > temp/ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/ips.txt > result/ips.txt

	# Выводим результат
	echo "IPs: $(wc -l result/ips.txt)"

	# Создаем файл для OpenVPN
	echo -n > result/DEFAULT
	while read -r line
	do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
		echo $"push \"route ${IP} ${MASK}\"" >> result/DEFAULT
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

	# Обновляем IP-адреса в ANTIZAPRET-ACCEPT
	if iptables -L ANTIZAPRET-ACCEPT &>/dev/null; then
		iptables -w -F ANTIZAPRET-ACCEPT
		while read -r line
		do
			iptables -w -A ANTIZAPRET-ACCEPT -d "$line" -j ACCEPT
		done < result/ips.txt
	fi
fi

if [[ -z "$1" || "$1" == "ad" ]]; then
	echo "Adblock-hosts..."

	# Обрабатываем список с рекламными доменами для блокировки от AdGuard
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' download/adguard.txt > temp/adblock-hosts.txt
	sed '/^[0-9.]*$/d' temp/adblock-hosts.txt > temp/adblock-hosts2.txt

	# Обрабатываем список с исключениями из блокировки от AdGuard
	sed -n '/\*/!s/^@@||\([^ ]*\)\^.*$/\1/p' download/adguard.txt > temp/adblock-pass-hosts.txt
	sed '/^[0-9.]*$/d' temp/adblock-pass-hosts.txt | sort -u > temp/adblock-pass-hosts2.txt

	# Обрабатываем список с рекламными доменами для блокировки от AdAway
	sed -E '/^\s*#/d; /^\s*$/d; /localhost/d; s/^127\.0\.0\.1 //g' download/adaway.txt > temp/adblock-hosts3.txt

	# Обрабатываем список с рекламными доменами для блокировки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/adblock-hosts.txt download/adblock-hosts.txt > temp/adblock-hosts4.txt

	# Обрабатываем список с исключениями из блокировки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/adblock-pass-hosts.txt download/adblock-pass-hosts.txt > temp/adblock-pass-hosts3.txt

	# Объединяем списки
	(cat temp/adblock-hosts2.txt && cat temp/adblock-hosts3.txt && cat temp/adblock-hosts4.txt) | sort -u > result/adblock-hosts.txt
	(cat temp/adblock-pass-hosts2.txt && cat temp/adblock-pass-hosts3.txt) | sort -u > result/adblock-pass-hosts.txt

	# Выводим результат
	echo "Adblock-hosts: $(wc -l result/adblock-hosts.txt)"
	echo "Adblock-pass-hosts: $(wc -l result/adblock-pass-hosts.txt)"

	# Создаем файл для Knot Resolver
	sed 's/$/ CNAME ./; p; s/^/*./' result/adblock-hosts.txt > result/adblock-hosts.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/adblock-pass-hosts.txt >> result/adblock-hosts.rpz

	# Обновляем файл в Knot Resolver только если файл adblock-hosts.rpz изменился
	if [[ -f result/adblock-hosts.rpz ]] && ! diff -q result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.rpz; then
		cp -f result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.temp
		mv -f /etc/knot-resolver/adblock-hosts.temp /etc/knot-resolver/adblock-hosts.rpz
	fi
fi

if [[ -z "$1" || "$1" == "host" ]]; then
	echo "Hosts..."

	# Обрабатываем список заблокированных ресурсов
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	iconv -f cp1251 -t utf8 download/dump.csv | \
	awk -F ';' '{
		if ($2 ~ /\.[а-яА-Яa-zA-Z]/) {
			sub(/^\*\./, "", $2);	# Удаление *. в начале
			sub(/\.$/, "", $2);		# Удаление . в конце
			gsub(/"/, "", $2);		# Удаление всех двойных кавычек
			print $2				# Выводим только доменные имена
		}
	}' | cat - download/domains.lst | sort -u | CHARSET=UTF-8 idn --no-tld > temp/hosts.txt

	# Удаляем не существующие домены
	grep -vFxf download/nxdomain.txt temp/hosts.txt > temp/hosts2.txt

	# Обрабатываем конфигурационные файлы
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-hosts.txt | sort -u > result/pass-hosts.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-hosts.txt download/include-hosts.txt | sort -u >> temp/hosts2.txt

	# Удаляем домены у которых уже есть домены верхнего уровня
	grep -E '^([^.]*\.){6}[^.]*$' temp/hosts2.txt | sed 's/^/./' > temp/exclude-patterns.txt
	grep -vFf temp/exclude-patterns.txt temp/hosts2.txt | sort -u > temp/hosts3.txt

	grep -E '^([^.]*\.){5}[^.]*$' temp/hosts3.txt | sed 's/^/./' > temp/exclude-patterns2.txt
	grep -vFf temp/exclude-patterns2.txt temp/hosts3.txt | sort -u > temp/hosts4.txt

	grep -E '^([^.]*\.){4}[^.]*$' temp/hosts4.txt | sed 's/^/./' > temp/exclude-patterns3.txt
	grep -vFf temp/exclude-patterns3.txt temp/hosts4.txt | sort -u > temp/hosts5.txt

	grep -E '^([^.]*\.){3}[^.]*$' temp/hosts5.txt | sed 's/^/./' > temp/exclude-patterns4.txt
	grep -vFf temp/exclude-patterns4.txt temp/hosts5.txt | sort -u > temp/hosts6.txt

	grep -E '^([^.]*\.){2}[^.]*$' temp/hosts6.txt | sed 's/^/./' > temp/exclude-patterns5.txt
	grep -vFf temp/exclude-patterns5.txt temp/hosts6.txt | sort -u > temp/hosts7.txt

	grep -E '^([^.]*\.){1}[^.]*$' temp/hosts7.txt | sed 's/^/./' > temp/exclude-patterns6.txt
	grep -vFf temp/exclude-patterns6.txt temp/hosts7.txt | sort -u > temp/hosts8.txt

	grep -E '^([^.]*\.){0}[^.]*$' temp/hosts8.txt | sed 's/^/./' > temp/exclude-patterns7.txt
	grep -vFf temp/exclude-patterns7.txt temp/hosts8.txt | sort -u > result/hosts.txt

	# Выводим результат
	echo "Hosts: $(wc -l result/hosts.txt)"
	echo "Pass-hosts: $(wc -l result/pass-hosts.txt)"

	# Создаем файл для Knot Resolver
	sed 's/$/ CNAME ./; p; s/^/*./' result/hosts.txt > result/hosts.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/pass-hosts.txt >> result/hosts.rpz

	# Обновляем файл в Knot Resolver только если файл hosts.rpz изменился
	if [[ -f result/hosts.rpz ]] && ! diff -q result/hosts.rpz /etc/knot-resolver/hosts.rpz; then
		cp -f result/hosts.rpz /etc/knot-resolver/hosts.temp
		mv -f /etc/knot-resolver/hosts.temp /etc/knot-resolver/hosts.rpz
		echo "cache.clear()" | socat - /run/knot-resolver/control/1 &>/dev/null
	fi
fi

exit 0