#!/bin/bash

###

if [[ -f /etc/sysctl.d/99-antizapret.conf ]]; then

echo "# AntiZapret parameters modification
kernel.printk=3 4 1 3
kernel.panic=1
kernel.panic_on_oops=1
kernel.softlockup_panic=1
kernel.hardlockup_panic=1
kernel.sched_autogroup_enabled=1
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=0
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.ipv4.tcp_rmem=16384 131072 4194304
net.ipv4.tcp_wmem=16384 131072 4194304
net.ipv4.tcp_no_metrics_save=1
net.core.netdev_budget=600
net.ipv4.tcp_fastopen=3
net.ipv4.ip_local_port_range=10000 50000
net.netfilter.nf_conntrack_max=131072
net.core.netdev_budget_usecs=8000
net.core.dev_weight=64
net.ipv4.tcp_max_syn_backlog=1024
net.netfilter.nf_conntrack_buckets=32768
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.core.netdev_max_backlog=5000
net.core.somaxconn=4096
net.ipv4.tcp_syncookies=1
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.core.optmem_max=131072
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_slow_start_after_idle=0
net.netfilter.nf_conntrack_tcp_timeout_established=86400
net.core.rmem_default=262144
net.core.wmem_default=262144" > /etc/sysctl.d/99-antizapret.conf

sysctl --system &>/dev/null

fi

###

set -e
shopt -s nullglob

# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

if [[ -n "$1" && "$1" != "ip" && "$1" != "ips" && "$1" != "host" && "$1" != "hosts" && "$1" != "noclear" && "$1" != "noclean" ]]; then
	echo "Ignored invalid parameter: $1"
	set -- ""
fi

echo 'Parse AntiZapret VPN files:'

export LC_ALL=C

cd /root/antizapret

rm -f temp/*

source setup

for file in config/*.txt; do
	sed -i -e '$a\' "$file"
done

if [[ -z "$1" || "$1" == "ip" || "$1" == "ips" || "$1" == "noclear" || "$1" == "noclean" ]]; then
	echo 'IPs...'

	# Обрабатываем конфигурационные файлы
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' config/*exclude-ips.txt | sort -u > temp/exclude-ips.txt
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' download/*ips.txt config/*include-ips.txt | sort -u > temp/include-ips.txt

	# Убираем IPv4-адреса из исключений
	comm -13 temp/exclude-ips.txt temp/include-ips.txt > temp/route-ips.txt

	# Обрабатываем конфигурационные файлы
	awk -F'[/.]' 'NF==5 && $1>=0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>=0 && $4<=255 && $5>=1 && $5<=32 {print}' temp/route-ips.txt > result/route-ips.txt

	# Выводим результат
	echo "$(wc -l < result/route-ips.txt) - route-ips.txt"

	# Создаем файл для OpenVPN и файлы маршрутов для роутеров
	[[ "$ALTERNATIVE_IP" == "y" ]] && IP_A="172" || IP_A="10"
	> result/DEFAULT
	echo -e "route 0.0.0.0 128.0.0.0 net_gateway\nroute 128.0.0.0 128.0.0.0 net_gateway\nroute ${IP_A}.29.0.0 255.255.248.0\nroute ${IP_A}.30.0.0 255.254.0.0" > result/tp-link-openvpn-routes.txt
	echo -e "route ADD DNS_IP_1 MASK 255.255.255.255 ${IP_A}.29.8.1\nroute ADD DNS_IP_2 MASK 255.255.255.255 ${IP_A}.29.8.1\nroute ADD ${IP_A}.30.0.0 MASK 255.254.0.0 ${IP_A}.29.8.1" > result/keenetic-wireguard-routes.txt
	echo "/ip route add dst-address=${IP_A}.30.0.0/15 gateway=${IP_A}.29.8.1 distance=1 comment=\"antizapret-wireguard\"" > result/mikrotik-wireguard-routes.txt
	while read -r line; do
		IP="$(echo $line | awk -F '/' '{print $1}')"
		MASK="$(sipcalc -- $line | awk '/Network mask/ {print $4; exit;}')"
		echo "push \"route ${IP} ${MASK}\"" >> result/DEFAULT
		echo "route ${IP} ${MASK}" >> result/tp-link-openvpn-routes.txt
		echo "route ADD ${IP} MASK ${MASK} ${IP_A}.29.8.1" >> result/keenetic-wireguard-routes.txt
		echo "/ip route add dst-address=${line} gateway=${IP_A}.29.8.1 distance=1 comment=\"antizapret-wireguard\"" >> result/mikrotik-wireguard-routes.txt
	done < result/route-ips.txt

	# Обновляем файл DEFAULT в OpenVPN только если файл изменился
	if [[ -f result/DEFAULT ]] && ! diff -q result/DEFAULT /etc/openvpn/server/ccd/DEFAULT; then
		cp -f result/DEFAULT /etc/openvpn/server/ccd/DEFAULT
	fi

	# Создаем файл ips для WireGuard/AmneziaWG
	awk '{printf ", %s", $0}' result/route-ips.txt > result/ips

	# Обновляем файл ips в WireGuard/AmneziaWG только если файл изменился
	if [[ -f result/ips ]] && ! diff -q result/ips /etc/wireguard/ips; then
		cp -f result/ips /etc/wireguard/ips
	fi

	if [[ "$RESTRICT_FORWARD" == "y" ]]; then
		# Обрабатываем конфигурационные файлы
		sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' config/*forward-ips.txt temp/route-ips.txt | sort -u \
		| awk -F'[/.]' 'NF==5 && $1>=0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>=0 && $4<=255 && $5>=1 && $5<=32 {print}' > result/forward-ips.txt

		# Выводим результат
		echo "$(wc -l < result/forward-ips.txt) - forward-ips.txt"

		# Обновляем ipset antizapret-forward
		{
			echo 'create antizapret-forward hash:net -exist'
			echo 'flush antizapret-forward'
			while read -r line; do
				echo "add antizapret-forward $line -exist"
			done < result/forward-ips.txt
		} | ipset restore
	fi

	if [[ "$ATTACK_PROTECTION" == "y" ]]; then
		# Обрабатываем конфигурационные файлы
		sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d' config/*allow-ips.txt | sort -u \
		| awk -F'[/.]' 'NF==5 && $1>=0 && $1<=255 && $2>=0 && $2<=255 && $3>=0 && $3<=255 && $4>=0 && $4<=255 && $5>=1 && $5<=32 {print}' > result/allow-ips.txt

		# Выводим результат
		echo "$(wc -l < result/allow-ips.txt) - allow-ips.txt"

		# Обновляем ipset antizapret-allow
		{
			echo 'create antizapret-allow hash:net -exist'
			echo 'flush antizapret-allow'
			while read -r line; do
				echo "add antizapret-allow $line -exist"
			done < result/allow-ips.txt
		} | ipset restore
	fi
fi

if [[ -z "$1" || "$1" == "host" || "$1" == "hosts" || "$1" == "noclear" || "$1" == "noclean" ]]; then
	echo 'Hosts...'

	# Обрабатываем список с рекламными доменами для блокировки
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/[]_~:/?#\[@!$&'\''()*+,;=].*//; s/.*/\L&/' download/oisd.txt download/*include-adblock-hosts.txt config/*include-adblock-hosts.txt > temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/[]_~:/?#\[@!$&'\''()*+,;=].*//; s/.*/\L&/' download/*exclude-adblock-hosts.txt config/*exclude-adblock-hosts.txt > temp/exclude-adblock-hosts.txt

	# Обрабатываем список с рекламными доменами для блокировки от AdGuard
	sed -n '/\*/!s/^||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed -E 's/.*/\L&/; /^[0-9.]+$/d' >> temp/include-adblock-hosts.txt

	# Обрабатываем список с исключениями из блокировки от AdGuard
	sed -n '/\*/!s/^@@||\([^ ]*\)\^.*$/\1/p' download/adguard.txt | sed -E 's/.*/\L&/; /^[0-9.]+$/d' >> temp/exclude-adblock-hosts.txt

	# Удаляем дубли и сортируем
	sort -u temp/include-adblock-hosts.txt > result/include-adblock-hosts.txt
	sort -u temp/exclude-adblock-hosts.txt > result/exclude-adblock-hosts.txt

	# Выводим результат
	echo "$(wc -l < result/include-adblock-hosts.txt) - include-adblock-hosts.txt"
	echo "$(wc -l < result/exclude-adblock-hosts.txt) - exclude-adblock-hosts.txt"

	# Создаем файлы deny.rpz и deny2.rpz для Knot Resolver
	echo -e '$TTL 10800\n@ SOA . . (1 1 1 1 10800)' > result/deny.rpz
	echo -e '$TTL 10800\n@ SOA . . (1 1 1 1 10800)' > result/deny2.rpz
	sed 's/$/ CNAME ./; p; s/^/*./' result/include-adblock-hosts.txt >> result/deny.rpz
	sed 's/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-adblock-hosts.txt >> result/deny.rpz
	sed 's/\r//g; /^;/d; /^$/d' download/*rpz.txt config/*rpz.txt >> result/deny.rpz
	sed 's/\r//g; /^;/d; /^$/d' download/*rpz2.txt config/*rpz2.txt >> result/deny2.rpz

	# Обновляем файл deny.rpz в Knot Resolver только если файл изменился
	if [[ -f result/deny.rpz ]] && ! diff -q result/deny.rpz /etc/knot-resolver/deny.rpz; then
		cp -f result/deny.rpz /etc/knot-resolver/deny.rpz.tmp
		mv -f /etc/knot-resolver/deny.rpz.tmp /etc/knot-resolver/deny.rpz
		sleep 5
	fi

	# Обновляем файл deny2.rpz в Knot Resolver только если файл изменился
	if [[ -f result/deny2.rpz ]] && ! diff -q result/deny2.rpz /etc/knot-resolver/deny2.rpz; then
		cp -f result/deny2.rpz /etc/knot-resolver/deny2.rpz.tmp
		mv -f /etc/knot-resolver/deny2.rpz.tmp /etc/knot-resolver/deny2.rpz
		sleep 5
	fi

	# Обрабатываем конфигурационные файлы
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/[]_~:/?#\[@!$&'\''()*+,;=].*//; s/.*/\L&/' download/*include-hosts.txt config/*include-hosts.txt > temp/include-hosts.txt
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/[]_~:/?#\[@!$&'\''()*+,;=].*//; s/.*/\L&/' download/*exclude-hosts.txt config/*exclude-hosts.txt | sort -u > temp/exclude-hosts.txt
	sed -E 's/[\r[:space:]]+//g; /^[[:punct:]]/d; /^$/d; s/[]_~:/?#\[@!$&'\''()*+,;=].*//; s/.*/\L&/' download/*remove-hosts.txt config/*remove-hosts.txt | sort -u > temp/remove-hosts.txt

	# Обрабатываем список заблокированных ресурсов
	# Удаляем лишнее и преобразуем доменные имена содержащие международные символы в формат Punycode
	sed -n 's/^[[:punct:]]\+//; s/[[:punct:]]\+$//; /\./{s/.*/\L&/; /^[а-яa-z0-9.-]\+$/p}' download/domain.txt \
	| CHARSET=UTF-8 idn --no-tld >> temp/include-hosts.txt

	# Удаляем домены казино и букмекеров
	if [[ "$CLEAR_HOSTS" == "y" ]]; then
		grep -Evi '[ck]a+[szc3]+[iley1]+n+[0-9o]|[vw][uy]+[l1]+[kc]a+n|[vw]a+[vw]+a+d+a|x-*bet|most-*bet|leon-*bet|rio-*bet|mel-*bet|ramen-*bet|marathon-*bet|max-*bet|bet-*win|gg-*bet|spin-*bet|banzai-*bet|1iks-*bet|x-*slot|sloto-*zal|max-*slot|bk-*leon|gold-*fishka|play-*fortuna|dragon-*money|poker-*dom|1-*win|crypto-*bos|free-*spin|fair-*spin|no-*deposit|igrovye|avtomaty|bookmaker|zerkalo|official|slottica|sykaaa|admiral-*x|x-*admiral|pinup-*bet|pari-*match|betting|partypoker|jackpot|bonus|azino[0-9-]|888-*starz|zooma[0-9-]|zenit-*bet|eldorado|slots|vodka|newretro|platinum|igrat|flagman|arkada' temp/include-hosts.txt | sort -u > temp/include-hosts2.txt
	else
		sort -u temp/include-hosts.txt > temp/include-hosts2.txt
	fi

	# Удаляем не существующие домены
	comm -13 temp/remove-hosts.txt temp/include-hosts2.txt > temp/include-hosts3.txt
	comm -13 temp/remove-hosts.txt temp/exclude-hosts.txt > result/exclude-hosts.txt

	# Удаляем избыточные поддомены
	if [[ "$ROUTE_ALL" = "y" ]]; then
		sed -E '/\..*\./ s/^([0-9]*www[0-9]*|hd[0-9]*|[A-Za-z]|[0-9]+)\.//' temp/include-hosts3.txt > temp/include-hosts4.txt
	else
		# Добавляем исключённые домены для дальнейшего удаления избыточных доменов
		sed -E '/\..*\./ s/^([0-9]*www[0-9]*|hd[0-9]*|[A-Za-z]|[0-9]+)\.//' temp/include-hosts3.txt result/exclude-hosts.txt > temp/include-hosts4.txt
	fi

	# Удаляем избыточные домены
	rev temp/include-hosts4.txt | \
	sort -t '.' -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 -k7,7 -k8,8 -k9,9 -k10,10 -k11,11 -k12,12 -k13,13 -k14,14 -k15,15 -k16,16 -k17,17 -k18,18 -k19,19 -k20,20 | \
	awk 'BEGIN { last = "" }
	{
		if (last != "" && index($0, last ".") == 1) {
			next
		}
		last = $0
		print $0
	}' | rev | sort -u > temp/include-hosts5.txt

	if [[ "$ROUTE_ALL" = "y" ]]; then
		# Пустим все домены через AntiZapret VPN
		sed '1i.' temp/include-hosts5.txt > result/include-hosts.txt
	else
		# Удаляем исключённые домены
		comm -23 temp/include-hosts5.txt result/exclude-hosts.txt > result/include-hosts.txt
	fi

	# Выводим результат
	echo "$(wc -l < result/include-hosts.txt) - include-hosts.txt"
	echo "$(wc -l < result/exclude-hosts.txt) - exclude-hosts.txt"

	# Создаем файл proxy.rpz для Knot Resolver
	echo -e '$TTL 10800\n@ SOA . . (1 1 1 1 10800)' > result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME ./; t; s/$/ CNAME ./; p; s/^/*./' result/include-hosts.txt >> result/proxy.rpz
	sed '/^\.$/ s/.*/*. CNAME rpz-passthru./; t; s/$/ CNAME rpz-passthru./; p; s/^/*./' result/exclude-hosts.txt >> result/proxy.rpz

	# Обновляем файл proxy.rpz в Knot Resolver только если файл изменился
	if [[ -f result/proxy.rpz ]] && ! diff -q result/proxy.rpz /etc/knot-resolver/proxy.rpz; then
		cp -f result/proxy.rpz /etc/knot-resolver/proxy.rpz.tmp
		mv -f /etc/knot-resolver/proxy.rpz.tmp /etc/knot-resolver/proxy.rpz
		sleep 5
		if [[ "$1" != "noclear" && "$1" != "noclean" ]]; then
			# Очищаем кэш Knot Resolver
			count="$(echo 'cache.clear()' | socat - /run/knot-resolver/control/1 | grep -oE '[0-9]+' || echo 0)"
			echo "DNS cache cleared: $count entries"
		fi
	fi
fi

./custom-parse.sh "$1" || true

exit 0