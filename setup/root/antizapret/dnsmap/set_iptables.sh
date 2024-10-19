#!/bin/bash
# ./set_iptables.sh REAL_ADDR FAKE_ADDR
REAL_ADDR="$1"
FAKE_ADDR="$2"
iptables-legacy -w -t nat -A dnsmap -d "$FAKE_ADDR" -j DNAT --to "$REAL_ADDR"