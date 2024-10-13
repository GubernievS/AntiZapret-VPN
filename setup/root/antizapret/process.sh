#!/bin/bash
set -e

cp result/blocked-hosts.conf /etc/knot-resolver/blocked-hosts.conf
systemctl restart kresd@1.service

exit 0
