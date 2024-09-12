#!/bin/bash
#
# Патч для обхода ПОЛНОЙ блокировки протокола OpenVPN на ТСПУ
# Работает только для UDP соединений
# Если подключение блокируется с каких то определенных серверов, а с других работает - патч скорее всего не поможет
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh
#
set -e
apt-get update && apt-get full-upgrade -y && apt-get autoremove -y
version=$(openvpn --version | head -n 1 | awk '{print $2}')
apt-get install -y curl tar perl build-essential libssl-dev pkg-config libsystemd-dev libpam0g-dev automake libnl-genl-3-dev libcap-ng-dev
rm -rf /root/openvpn
mkdir -p /root/openvpn
curl -L -o openvpn.tar.gz https://build.openvpn.net/downloads/releases/openvpn-$version.tar.gz
tar --strip-components=1 -xvzf openvpn.tar.gz -C /root/openvpn
rm -f /root/openvpn.tar.gz
mv /root/openvpn/src/openvpn/socket.h /root/openvpn/src/openvpn/socket
perl -0777 -pe 's/(link_socket_write_udp\(struct link_socket \*sock,\s*struct buffer \*buf,\s*struct link_socket_actual \*to\)\s*{)/$1\n    uint8_t opcode = *BPTR(buf) >> 3;\nif (opcode == 7\n    || opcode == 8\n    || opcode == 10)\n{\n    uint8_t stuffing_data[] = {0x01, 0x00, 0x00, 0x00, 0x01};\n    size_t stuffing_len = sizeof(stuffing_data);\n    struct buffer stuffing_buf = clone_buf(buf);\n    buf_clear(&stuffing_buf);\n    buf_write(&stuffing_buf, stuffing_data, stuffing_len);\n#ifdef _WIN32\n    link_socket_write_win32(sock, &stuffing_buf, to);\n#else\n    link_socket_write_udp_posix(sock, &stuffing_buf, to);\n#endif\n    free_buf(&stuffing_buf);\n}/gs' /root/openvpn/src/openvpn/socket > /root/openvpn/src/openvpn/socket.h
cd /root/openvpn
chmod +x ./configure
./configure --enable-systemd=yes --disable-debug --disable-lzo --disable-lz4
make
make install
rm -rf /root/openvpn
systemctl daemon-reload
systemctl restart openvpn-server@antizapret-udp
systemctl restart openvpn-server@antizapret-tcp
systemctl restart openvpn-server@vpn-udp
systemctl restart openvpn-server@vpn-tcp
echo ""
echo "Patch successful installation!"