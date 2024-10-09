#!/bin/bash
set -e

cp result/blocked-hosts.conf /etc/knot-resolver/blocked-hosts.conf
systemctl restart kresd@1.service

#iptables-legacy -F azvpnwhitelist
#while read -r line
#do
#    iptables-legacy -w -A azvpnwhitelist -d "$line" -j ACCEPT
#done < result/blocked-ranges.txt

exit 0
