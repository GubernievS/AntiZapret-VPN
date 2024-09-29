#!/bin/bash
#
# Патч для обхода блокировки протокола OpenVPN
# Работает только для UDP соединений
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh
#
set -e
if [[ "$1" == "1" || "$1" == "2" ]]; then
	ALGORITHM="$1"
else
	echo ""
	echo "Choose a version of the anti-censorship patch for OpenVPN (UDP only):"
	echo "    1) Strong     - Recommended for default"
	echo "    2) Error-free - If the strong patch causes a connection error on your device or router"
	until [[ $ALGORITHM =~ ^[1-2]$ ]]; do
		read -rp "Version choice [1-2]: " -e -i 1 ALGORITHM
	done
fi
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt autoremove -y
version=$(openvpn --version | head -n 1 | awk '{print $2}')
DEBIAN_FRONTEND=noninteractive apt install --reinstall -y curl tar build-essential libssl-dev pkg-config libsystemd-dev libpam0g-dev automake libnl-genl-3-dev libcap-ng-dev
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
#define ALGORITHM '"$ALGORITHM"'\
	uint16_t buffer_sent = 0;\
	uint8_t opcode = *BPTR(buf) >> 3;\
if (opcode == 7 || opcode == 8 || opcode == 10)\
{\
	if (ALGORITHM == 2) {\
#ifdef _WIN32\
		buffer_sent =+ link_socket_write_win32(sock, buf, to);\
#else\
		buffer_sent =+ link_socket_write_udp_posix(sock, buf, to);\
#endif\
	}\
	uint16_t buffer_len = BLEN(buf);\
	srand(time(NULL));\
	for (int i = 0; i < 2; i++) {\
		uint16_t data_len = rand() % 101 + buffer_len;\
		uint8_t data[data_len];\
		struct buffer data_buffer;\
		if (ALGORITHM == 1) {\
			data_buffer = alloc_buf(data_len);\
			if (i == 0) {\
				data[0] = 1;\
				data[1] = 0;\
				data[2] = 0;\
				data[3] = 0;\
				data[4] = 1;\
				for (int k = 5; k < data_len; k++) {\
					data[k] = rand() % 256;\
				}\
			}\
			else {\
				for (int k = 0; k < data_len; k++) {\
					data[k] = rand() % 256;\
				}\
			}\
		}\
		else {\
			data_buffer = clone_buf(buf);\
			buf_read(&data_buffer, data, buffer_len);\
			buf_clear(&data_buffer);\
			data[0] = 40;\
			for (int k = buffer_len; k < data_len; k++) {\
				data[k] = rand() % 256;\
			}\
		}\
		buf_write(&data_buffer, data, data_len);\
		int data_repeat = rand() % 101 + 100;\
		for (int j = 0; j < data_repeat; j++) {\
#ifdef _WIN32\
			buffer_sent =+ link_socket_write_win32(sock, &data_buffer, to);\
#else\
			buffer_sent =+ link_socket_write_udp_posix(sock, &data_buffer, to);\
#endif\
		}\
		free_buf(&data_buffer);\
		usleep(data_repeat * 1000);\
	}\
}\
#ifdef _WIN32\
	buffer_sent =+ link_socket_write_win32(sock, buf, to);\
#else\
	buffer_sent =+ link_socket_write_udp_posix(sock, buf, to);\
#endif\
	return buffer_sent;\
}\
\
\/\* write a TCP or UDP packet to link \*\/' "/root/openvpn/src/openvpn/socket.h"
cd /root/openvpn
chmod +x ./configure
./configure --enable-systemd=yes --disable-debug --disable-lzo --disable-lz4
make
make install
systemctl daemon-reload
systemctl restart openvpn-server@*
echo ""
echo "OpenVPN patch installed successfully!"