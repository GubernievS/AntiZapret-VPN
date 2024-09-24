#!/bin/bash
#
# Патч для обхода блокировки протокола OpenVPN
# Работает только для UDP соединений
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh
#
set -e
apt update
DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt autoremove -y
version=$(openvpn --version | head -n 1 | awk '{print $2}')
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y curl tar perl build-essential libssl-dev pkg-config libsystemd-dev libpam0g-dev automake libnl-genl-3-dev libcap-ng-dev
rm -rf /root/openvpn
mkdir -p /root/openvpn
curl -L -o /root/openvpn.tar.gz https://build.openvpn.net/downloads/releases/openvpn-$version.tar.gz
tar --strip-components=1 -xvzf /root/openvpn.tar.gz -C /root/openvpn
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
	srand(time(NULL));\
	for (int i=0; i<2; i++) {\
		int stuffing_len = rand() % 91 + 10;\
		uint8_t stuffing_data[100];\
		for (int j=0; j<stuffing_len; j++) {\
			stuffing_data[j] = rand() % 256;\
		}\
		struct buffer stuffing_buf = alloc_buf(100);\
		buf_write(&stuffing_buf, stuffing_data, stuffing_len);\
		for (int j=0; j<100; j++) {\
#ifdef _WIN32\
			stuffing_sent =+ link_socket_write_win32(sock, &stuffing_buf, to);\
#else\
			stuffing_sent =+ link_socket_write_udp_posix(sock, &stuffing_buf, to);\
#endif\
		}\
		free_buf(&stuffing_buf);\
	}\
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
chmod +x /root/openvpn/configure
/root/openvpn/configure --enable-systemd=yes --disable-debug --disable-lzo --disable-lz4
make -C /root/openvpn
make -C /root/openvpn install
echo ""
echo "Patch successful installation!"
if [[ "$1" != "noreboot" ]]; then
	echo "Rebooting..."
	reboot
fi