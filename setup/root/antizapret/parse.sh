#!/bin/bash
set -e

handle_error() {
	echo ""
	echo -e "\e[1;31mError occurred at line $1 while executing: $2\e[0m"
	echo ""
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE"

# Обрабатываем список заблокированных ресурсов
# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
awk -F ';' '{
	if ($2 ~ /\./ && $2 ~ /^[а-яА-Яa-zA-Z0-9\-_\.\*]+$/) {
		gsub(/^\*\./, "", $2);	# Удаление *. в начале
		gsub(/\.$/, "", $2);	# Удаление . в конце
		print $2				# Выводим только доменные имена
	}
}' temp/list.csv | CHARSET=UTF-8 idn --no-tld > temp/list.txt

# Удалим домены больше 4-ого уровня и дубли
sed -E 's/^.*\.(.*\..*\..*\..*)$/\1/' temp/list.txt | sort -u > temp/blocked-hosts.txt

# Подготавливаем исходные файлы для обработки
( sed -E '/^#/d; /^[[:space:]]*$/d; s/^[[:space:]]+//; s/[[:space:]]+$//' config/exclude-hosts-{dist,custom}.txt && cat temp/nxdomain.txt ) > temp/exclude-hosts.txt
( sed -E '/^#/d; /^[[:space:]]*$/d; s/^[[:space:]]+//; s/[[:space:]]+$//' config/include-hosts-{dist,custom}.txt && cat temp/blocked-hosts.txt) > temp/include-hosts.txt
sed -E '/^#/d; /^[[:space:]]*$/d; s/^[[:space:]]+//; s/[[:space:]]+$//' config/include-ips-{dist,custom}.txt > temp/include-ips.txt

# Очищаем список доменов
awk -f scripts/getzones.awk temp/include-hosts.txt > temp/getzones.txt
awk 'NR==FNR {exclude[$0]; next} !($0 in exclude)' temp/exclude-hosts.txt temp/getzones.txt > temp/blocked-hosts.txt
grep -vFf <(grep -E '^([^.]*\.){0,1}[^.]*$' temp/blocked-hosts.txt | sed 's/^/./') temp/blocked-hosts.txt > result/blocked-hosts.txt

# Заблокированные IP-адреса
awk '/([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}/ {print $0}' temp/include-ips.txt > result/blocked-ranges.txt

# Generate OpenVPN route file
echo -n > result/openvpn-blocked-ranges.txt
while read -r line
do
	IP="$(echo $line | awk -F '/' '{print $1}')"
	MASK="$(sipcalc -- "$line" | awk '/Network mask/ {print $4; exit;}')"
	echo $"push \"route ${IP} ${MASK}\"" >> result/openvpn-blocked-ranges.txt
done < result/blocked-ranges.txt

# Generate knot-resolver aliases
echo 'blocked_hosts = {' > result/blocked-hosts.conf
while read -r line
do
	line="$line."
	echo "${line@Q}," >> result/blocked-hosts.conf
done < result/blocked-hosts.txt
echo '}' >> result/blocked-hosts.conf

# Print results
echo "Blocked domains: $(wc -l result/blocked-hosts.txt)"

exit 0