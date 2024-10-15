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
	if ($2 ~ /\.[а-яА-Яa-zA-Z]/) {
		gsub(/^\*\./, "", $2);	# Удаление *. в начале
		gsub(/\.$/, "", $2);	# Удаление . в конце
		print $2				# Выводим только доменные имена
	}
}' temp/list.csv | CHARSET=UTF-8 idn --no-tld > temp/blocked-hosts.txt

# Подготавливаем исходные файлы для обработки
( sed -E '/^#/d; s/[[:space:]]+//g' config/exclude-hosts-{dist,custom}.txt && echo && cat temp/nxdomain.txt ) | sort -u > temp/exclude-hosts.txt
( sed -E '/^#/d; s/[[:space:]]+//g' config/include-hosts-{dist,custom}.txt && echo && cat temp/blocked-hosts.txt) | sort -u > temp/include-hosts.txt

# Очищаем список доменов
awk -f config/exclude-regexp-dist.awk temp/include-hosts.txt > temp/blocked-hosts2.txt

# Убираем домены из исключений
awk 'NR==FNR {exclude[$0]; next} !($0 in exclude)' temp/exclude-hosts.txt temp/blocked-hosts2.txt > temp/blocked-hosts3.txt

cp temp/blocked-hosts3.txt temp/blocked-hosts4.txt
# Находим дубли и если домен повторяется больше 2-х раз добавляем домен верхнего уровня
# Пропускаем домены типа co.uk, net.ru, msk.ru и тд - длинна которых меньше или равна 6
awk -F '.' '{ key = $(NF-1) "." $NF; if (length(key) > 6) count[key]++ } END { for (k in count) if (count[k] > 1) print k }' temp/blocked-hosts3.txt >> temp/blocked-hosts4.txt
awk -F '.' 'NF >= 3 { key = $(NF-2) "." $(NF-1) "." $NF; count[key]++ } END { for (k in count) if (count[k] > 1) print k }' temp/blocked-hosts3.txt >> temp/blocked-hosts4.txt

# Убираем домены у которых уже есть домены верхнего уровня
grep -vFf <(grep -E '^([^.]*\.){0,2}[^.]*$' temp/blocked-hosts4.txt | sed 's/^/./') temp/blocked-hosts4.txt > temp/blocked-hosts5.txt

# Еще раз убираем домены из исключений
awk 'NR==FNR {exclude[$0]; next} !($0 in exclude)' temp/exclude-hosts.txt temp/blocked-hosts5.txt | sort -u > result/blocked-hosts.txt

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