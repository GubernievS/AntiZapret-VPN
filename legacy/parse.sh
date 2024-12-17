#!/bin/bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

rm -f temp/*

if [[ -z "$1" || "$1" == "ip" ]]; then
	echo "Parse ips..."

	# Подготавливаем исходные файлы для обработки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-ips.txt | sort -u > temp/exclude-ips.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-ips.txt download/include-ips.txt | sort -u > temp/include-ips.txt

	# Убираем IP-адреса из исключений
	grep -vFxf temp/exclude-ips.txt temp/include-ips.txt > temp/ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/ips.txt > result/ips.txt

	# Создаем файл для OpenVPN
	echo -n > result/DEFAULT
	while read -r line
	do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
		echo $"push \"route ${IP} ${MASK}\"" >> result/DEFAULT
	done < result/ips.txt

	# Обновляем файл
	cp result/DEFAULT /etc/openvpn/server/ccd/DEFAULT

	# Создаем файл для WireGuard/AmneziaWG
	awk '{printf ", %s", $0}' result/ips.txt > result/ips
	# Обновляем файл
	cp result/ips /etc/wireguard/ips

	# Создаем файл для ferm
	echo "@def \$WHITELIST = (" > result/whitelist.conf
	cat result/ips.txt >> result/whitelist.conf
	echo ");" >> result/whitelist.conf

	# Выводим результат
	echo "Ips: $(wc -l result/ips.txt)"
fi

if [[ -z "$1" || "$1" == "host" ]]; then
	echo "Parse hosts..."

	# Обрабатываем список заблокированных ресурсов
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	iconv -f cp1251 -t utf8 download/dump.csv | \
	awk -F ';' '{
		if ($2 ~ /\.[а-яА-Яa-zA-Z]/) {
			sub(/^\*\./, "", $2);	# Удаление *. в начале
			sub(/\.$/, "", $2);		# Удаление . в конце
			print $2				# Выводим только доменные имена
		}
	}' | sort -u | CHARSET=UTF-8 idn --no-tld > temp/hosts.txt

	# Очищаем список доменов
	awk -f download/exclude-hosts.awk temp/hosts.txt > temp/hosts2.txt

	# Подготавливаем исходные файлы для обработки
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/exclude-hosts.txt download/nxdomain.txt | sort -u > temp/exclude-hosts.txt
	sed -E '/^#/d; s/\r//; s/[[:space:]]+//g; /^$/d' config/include-hosts.txt download/include-hosts.txt temp/hosts2.txt | sort -u > temp/include-hosts.txt

	# Убираем домены из исключений
	grep -vFxf temp/exclude-hosts.txt temp/include-hosts.txt > temp/hosts3.txt

	# Находим дубли и если домен повторяется больше 10 раз добавляем домен верхнего уровня
	# Пропускаем домены типа co.uk, net.ru, msk.ru и тд - длинна которых меньше или равна 6
	cp temp/hosts3.txt temp/hosts4.txt
	awk -F '.' '{ key = $(NF-1) "." $NF; if (length(key) > 6) count[key]++ } END { for (k in count) if (count[k] > 10) print k }' temp/hosts3.txt >> temp/hosts4.txt
	awk -F '.' 'NF >= 3 { key = $(NF-2) "." $(NF-1) "." $NF; count[key]++ } END { for (k in count) if (count[k] > 10) print k }' temp/hosts3.txt >> temp/hosts4.txt

	# Убираем домены у которых уже есть домены верхнего уровня
	grep -E '^([^.]*\.){2}[^.]*$' temp/hosts4.txt | sed 's/^/./' > temp/exclude-patterns.txt
	grep -vFf temp/exclude-patterns.txt temp/hosts4.txt | sort -u > temp/hosts5.txt

	grep -E '^([^.]*\.){1}[^.]*$' temp/hosts5.txt | sed 's/^/./' > temp/exclude-patterns2.txt
	grep -vFf temp/exclude-patterns2.txt temp/hosts5.txt | sort -u > temp/hosts6.txt

	grep -E '^([^.]*\.){0}[^.]*$' temp/hosts6.txt | sed 's/^/./' > temp/exclude-patterns3.txt
	grep -vFf temp/exclude-patterns3.txt temp/hosts6.txt | sort -u > result/hosts.txt

	# Создаем файл для Knot Resolver
	echo 'hosts = {' > result/hosts.conf
	while read -r line
	do
		line="$line."
		echo "${line@Q}," >> result/hosts.conf
	done < result/hosts.txt
	echo '}' >> result/hosts.conf

	# Выводим результат
	echo "Hosts: $(wc -l result/hosts.txt)"
fi

if [[ -z "$1" || "$1" == "ad" ]]; then
	echo "Parse adblock-hosts..."

	# Обрабатываем список с рекламными доменами для блокировки
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' download/adblock-hosts.txt | sort -u > temp/adblock-hosts.txt
	sed '/^[0-9.]*$/d' temp/adblock-hosts.txt > result/adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки
	sed -n '/\*/!s/^@@||\([^ ]*\)\^.*$/\1/p' download/adblock-hosts.txt | sort -u > temp/adblock-pass-hosts.txt
	sed '/^[0-9.]*$/d' temp/adblock-pass-hosts.txt > result/adblock-pass-hosts.txt

	# Создаем файл для Knot Resolver
	sed 's/$/ CNAME ./; p; s/^/*./' result/adblock-hosts.txt > result/adblock-hosts.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/adblock-pass-hosts.txt >> result/adblock-hosts.rpz

	# Выводим результат
	echo "Adblock-hosts: $(wc -l result/adblock-hosts.txt)"
fi

# Обновляем файл и перезапускаем сервисы ferm, dnsmap и kresd@1 только если файл whitelist.conf изменился
if [[ -f result/whitelist.conf ]] && ! diff -q result/whitelist.conf /etc/ferm/whitelist.conf; then
	cp result/whitelist.conf /etc/ferm/whitelist.conf
	RESTART_FERM_DNSMAP=true
	RESTART_KRESD=true
fi

# Обновляем файл и перезапускаем сервис kresd@1 только если файл hosts.conf изменился
if [[ -f result/hosts.conf ]] && ! diff -q result/hosts.conf /etc/knot-resolver/hosts.conf; then
	cp result/hosts.conf /etc/knot-resolver/hosts.conf
	RESTART_KRESD=true
fi

# Обновляем файл и перезапускаем сервис kresd@1 только если файл adblock-hosts.rpz изменился
if [[ -f result/adblock-hosts.rpz ]] && ! diff -q result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.rpz; then
	cp result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.temp
	mv -f /etc/knot-resolver/adblock-hosts.temp /etc/knot-resolver/adblock-hosts.rpz
	RESTART_KRESD=true
fi

if [[ "$RESTART_FERM_DNSMAP" == true ]]; then
	if systemctl is-active --quiet ferm; then
		echo "Restart ferm"
		systemctl restart ferm
	fi
	if systemctl is-active --quiet dnsmap; then
		echo "Restart dnsmap"
		systemctl restart dnsmap
	fi
fi

if [[ "$RESTART_KRESD" == true ]]; then
	if systemctl is-active --quiet kresd@1; then
		echo "Restart kresd@1"
		systemctl restart kresd@1
	fi
fi

exit 0