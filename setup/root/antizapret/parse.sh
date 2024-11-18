#!/bin/bash
set -e

handle_error() {
	echo ""
	echo -e "\e[1;31mError occurred at line $1 while executing: $2\e[0m"
	echo ""
	echo "$(lsb_release -d | awk -F'\t' '{print $2}') $(uname -r) $(date)"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

if [[ -z "$1" || "$1" == "ip" ]]; then
	echo "Parse blocked ips"

	# Подготавливаем исходные файлы для обработки
	sed -E '/^#/d; s/[[:space:]]+//g' config/include-ips-*.txt | sort -u > temp/include-ips.txt
	sed -E '/^#/d; s/[[:space:]]+//g' config/exclude-ips-*.txt | sort -u > temp/exclude-ips.txt

	# Убираем IP-адреса из исключений
	awk 'NR==FNR {exclude[$0]; next} !($0 in exclude)' temp/exclude-ips.txt temp/include-ips.txt > temp/blocked-ips.txt

	# Заблокированные IP-адреса
	awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/blocked-ips.txt > result/blocked-ips.txt

	# Создаем файл для OpenVPN
	echo -n > result/DEFAULT
	while read -r line
	do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
		echo $"push \"route ${IP} ${MASK}\"" >> result/DEFAULT
	done < result/blocked-ips.txt

	# Обновляем файл
	cp result/DEFAULT /etc/openvpn/server/ccd/DEFAULT

	# Создаем файл для WireGuard/AmneziaWG
	awk '{printf ", %s", $0}' result/blocked-ips.txt > result/ips
	# Обновляем файл
	cp result/ips /etc/wireguard/ips

	# Создаем файл для ferm
	echo "@def \$WHITELIST = (" > result/whitelist.conf
	cat result/blocked-ips.txt >> result/whitelist.conf
	echo ");" >> result/whitelist.conf

	# Выводим результат
	echo "Blocked ips: $(wc -l result/blocked-ips.txt)"
fi

if [[ -z "$1" || "$1" == "blocked" ]]; then
	echo "Parse blocked hosts"

	# Обрабатываем список заблокированных ресурсов
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	iconv -f cp1251 -t utf8 temp/blocked.csv | \
	awk -F ';' '{
		if ($2 ~ /\.[а-яА-Яa-zA-Z]/) {
			sub(/^\*\./, "", $2);	# Удаление *. в начале
			sub(/\.$/, "", $2);		# Удаление . в конце
			print $2				# Выводим только доменные имена
		}
	}' | CHARSET=UTF-8 idn --no-tld | sort -u > temp/blocked-hosts.txt

	# Очищаем список доменов
	awk -f config/exclude-regexp-dist.awk temp/blocked-hosts.txt > temp/blocked-hosts2.txt

	# Подготавливаем исходные файлы для обработки
	( sed -E '/^#/d; s/[[:space:]]+//g' config/exclude-hosts-*.txt && \
		echo && \
		cat temp/nxdomain.txt ) | sort -u > temp/exclude-hosts.txt
	( sed -E '/^#/d; s/[[:space:]]+//g' config/include-hosts-*.txt && \
		echo && \
		cat temp/blocked-hosts2.txt) | sort -u > temp/include-hosts.txt

	# Убираем домены из исключений
	awk 'NR==FNR {exclude[$0]; next} !($0 in exclude)' temp/exclude-hosts.txt temp/include-hosts.txt > temp/blocked-hosts3.txt

	# Находим дубли и если домен повторяется больше 10 раз добавляем домен верхнего уровня
	# Пропускаем домены типа co.uk, net.ru, msk.ru и тд - длинна которых меньше или равна 6
	cp temp/blocked-hosts3.txt temp/blocked-hosts4.txt
	awk -F '.' '{ key = $(NF-1) "." $NF; if (length(key) > 6) count[key]++ } END { for (k in count) if (count[k] > 10) print k }' \
		temp/blocked-hosts3.txt >> temp/blocked-hosts4.txt
	awk -F '.' 'NF >= 3 { key = $(NF-2) "." $(NF-1) "." $NF; count[key]++ } END { for (k in count) if (count[k] > 10) print k }' \
		temp/blocked-hosts3.txt >> temp/blocked-hosts4.txt

	# Убираем домены у которых уже есть домены верхнего уровня
	grep -E '^([^.]*\.){2}[^.]*$' temp/blocked-hosts4.txt | sed 's/^/./' > temp/exclude-patterns.txt
	grep -vFf temp/exclude-patterns.txt temp/blocked-hosts4.txt | sort -u > temp/blocked-hosts5.txt

	grep -E '^([^.]*\.){1}[^.]*$' temp/blocked-hosts5.txt | sed 's/^/./' > temp/exclude-patterns2.txt
	grep -vFf temp/exclude-patterns2.txt temp/blocked-hosts5.txt | sort -u > temp/blocked-hosts6.txt

	grep -E '^([^.]*\.){0}[^.]*$' temp/blocked-hosts6.txt | sed 's/^/./' > temp/exclude-patterns3.txt
	grep -vFf temp/exclude-patterns3.txt temp/blocked-hosts6.txt | sort -u > result/blocked-hosts.txt

	# Создаем файл для knot-resolver
	echo 'blocked_hosts = {' > result/blocked-hosts.conf
	while read -r line
	do
		line="$line."
		echo "${line@Q}," >> result/blocked-hosts.conf
	done < result/blocked-hosts.txt
	echo '}' >> result/blocked-hosts.conf

	# Выводим результат
	echo "Blocked hosts: $(wc -l result/blocked-hosts.txt)"
fi

if [[ -z "$1" || "$1" == "adblock" ]]; then
	echo "Parse ad blocking hosts"

	sed -E 's/(\|[^-.]*)\*\./\1./g' temp/adblock.txt > temp/adblock2.txt
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' temp/adblock2.txt | sort -u > temp/adblock3.txt
	sed '/^[0-9.]*$/d' temp/adblock3.txt > result/adblock-hosts.txt
	sed 's/$/ CNAME ./; p; s/^/*./' result/adblock-hosts.txt > result/adblock-hosts.rpz

	# Выводим результат
	echo "Ad blocking hosts: $(wc -l result/adblock-hosts.txt)"
fi

# Обновляем файл и перезапускаем сервисы ferm, dnsmap и kresd@1 только если файл whitelist.conf изменился
if [[ -f result/whitelist.conf ]] && ! diff -q result/whitelist.conf /etc/ferm/whitelist.conf; then
	cp result/whitelist.conf /etc/ferm/whitelist.conf
	RESTART_FERM_DNSMAP=true
	RESTART_KRESD=true
fi

# Обновляем файл и перезапускаем сервис kresd@1 только если файл blocked-hosts.conf изменился
if [[ -f result/blocked-hosts.conf ]] && ! diff -q result/blocked-hosts.conf /etc/knot-resolver/blocked-hosts.conf; then
	cp result/blocked-hosts.conf /etc/knot-resolver/blocked-hosts.conf
	RESTART_KRESD=true
fi

# Обновляем файл и перезапускаем сервис kresd@1 только если файл adblock-hosts.rpz изменился
if [[ -f result/adblock-hosts.rpz ]] && ! diff -q result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.rpz; then
	cp result/adblock-hosts.rpz /etc/knot-resolver/adblock-hosts.rpz
	RESTART_KRESD=true
fi

if [[ "$RESTART_FERM_DNSMAP" = true ]]; then
	if systemctl is-active --quiet ferm; then
		echo "Restart ferm"
		systemctl restart ferm
	fi
	if systemctl is-active --quiet dnsmap; then
		echo "Restart dnsmap"
		systemctl restart dnsmap
	fi
fi

if [[ "$RESTART_KRESD" = true ]]; then
	if systemctl is-active --quiet kresd@1; then
		echo "Restart kresd@1"
		systemctl restart kresd@1
	fi
fi

exit 0