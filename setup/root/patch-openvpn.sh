#!/bin/bash
#
# Патч для обхода блокировки протокола OpenVPN
# Работает только для UDP соединений
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh
#
set -e
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -o Dpkg::Options::="--force-confdef"
apt-get autoremove -y
version=$(openvpn --version | head -n 1 | awk '{print $2}')
DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar perl build-essential libssl-dev pkg-config libsystemd-dev libpam0g-dev automake libnl-genl-3-dev libcap-ng-dev
rm -rf /root/openvpn
mkdir -p /root/openvpn
curl -L -o openvpn.tar.gz https://build.openvpn.net/downloads/releases/openvpn-$version.tar.gz
tar --strip-components=1 -xvzf openvpn.tar.gz -C /root/openvpn
rm -f /root/openvpn.tar.gz
sed -i '/link_socket_write_udp(struct link_socket \*sock/,/\/\* write a TCP or UDP packet to link \*\//c\
link_socket_write_udp(struct link_socket *sock,\
                      struct buffer *buf,\
                      struct link_socket_actual *to)\
{\
    uint16_t stuffing_sent = 0;\
    uint8_t opcode = *BPTR(buf) >> 3;\
if (opcode == 7 || opcode == 8 || opcode == 10)\
{\
    uint8_t stuffing_data[] = {0x01, 0x00, 0x00, 0x00, 0x01};\
    size_t stuffing_len = sizeof(stuffing_data);\
    struct buffer stuffing_buf = clone_buf(buf);\
    buf_clear(&stuffing_buf);\
    buf_write(&stuffing_buf, stuffing_data, stuffing_len);\
    for (int i=0; i<100; i++)\
    {\
#ifdef _WIN32\
        stuffing_sent =+ link_socket_write_win32(sock, &stuffing_buf, to);\
#else\
        stuffing_sent =+ link_socket_write_udp_posix(sock, &stuffing_buf, to);\
#endif\
    }\
    free_buf(&stuffing_buf);\
}\
#ifdef _WIN32\
    stuffing_sent =+ link_socket_write_win32(sock, buf, to);\
#else\
    stuffing_sent =+ link_socket_write_udp_posix(sock, buf, to);\
#endif\
    return stuffing_sent;\
}\
\
\/\* write a TCP or UDP packet to link \*\/' "/root/openvpn/src/openvpn/socket.h"
cd /root/openvpn
chmod +x ./configure
./configure --enable-systemd=yes --disable-debug --disable-lzo --disable-lz4
make
make install
rm -rf /root/openvpn
echo ""
echo "Patch successful installation! Rebooting..."
reboot