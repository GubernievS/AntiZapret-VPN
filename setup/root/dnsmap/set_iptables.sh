#!/bin/bash
# ./set_iptables.sh REAL_ADDR FAKE_ADDR
real_addr="$1"
fake_addr="$2"
iptables -w -t nat -A dnsmap -d "$fake_addr" -j DNAT --to "$real_addr"