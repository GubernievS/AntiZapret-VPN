#!/bin/bash
set -e

cp result/knot-aliases-alt.conf /etc/knot-resolver/knot-aliases-alt.conf
systemctl restart kresd@1.service

cp result/openvpn-blocked-ranges.txt /etc/openvpn/server/ccd/DEFAULT
iptables-legacy -F azvpnwhitelist
while read -r line
do
    iptables-legacy -w -A azvpnwhitelist -d "$line" -j ACCEPT
done < result/blocked-ranges.txt

exit 0
