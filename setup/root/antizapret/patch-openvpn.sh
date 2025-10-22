#!/bin/bash
#
# Патч для обхода блокировки протокола OpenVPN
# Работает только для UDP соединений
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh [0-2]
#
set -e

handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

export LC_ALL=C

if [[ "$1" =~ ^[0-2]$ ]]; then
	ALGORITHM="$1"
else
	echo
	echo 'Choose anti-censorship patch for OpenVPN (UDP only):'
	echo '    0) None        - Do not install anti-censorship patch, or remove if already installed'
	echo '    1) Strong      - Recommended by default'
	echo '    2) Error-free  - Use if Strong patch causes connection error, recommended for Mikrotik routers'
	until [[ "$ALGORITHM" =~ ^[0-2]$ ]]; do
		read -rp 'Version choice [0-2]: ' -e -i 1 ALGORITHM
	done
fi

export DEBIAN_FRONTEND=noninteractive

if [[ "$ALGORITHM" == "0" ]]; then
	if [[ -d "/usr/local/src/openvpn" ]]; then
		make -C /usr/local/src/openvpn uninstall || true
		rm -rf /usr/local/src/openvpn
		apt-get update
		apt-get dist-upgrade -y
		apt-get install --reinstall -y openvpn
		apt-get autoremove -y
		apt-get clean
		systemctl daemon-reload
		systemctl restart openvpn-server@*
		echo
		echo 'OpenVPN patch remove successfully!'
		exit 0
	fi
	echo
	echo 'OpenVPN patch not installed!'
	exit 0
elif [[ "$ALGORITHM" == "2" ]]; then
    ERROR_FREE="#define ERROR_FREE"
else
    ERROR_FREE="#undef ERROR_FREE"
fi

apt-get update
apt-get dist-upgrade -y
apt-get install --reinstall -y curl tar build-essential libssl-dev pkg-config libsystemd-dev automake libnl-genl-3-dev libcap-ng-dev
apt-get autoremove -y
apt-get clean
VERSION="$(openvpn --version | head -n 1 | awk '{print $2}')"
rm -rf /usr/local/src/openvpn
mkdir -p /usr/local/src/openvpn
curl -fL https://build.openvpn.net/downloads/releases/openvpn-$VERSION.tar.gz -o /usr/local/src/openvpn.tar.gz
tar --strip-components=1 -xvzf /usr/local/src/openvpn.tar.gz -C /usr/local/src/openvpn
rm -f /usr/local/src/openvpn.tar.gz

sed -i '/link_socket_write_udp(struct link_socket \*sock/,/\/\* write a TCP or UDP packet to link \*\//c\
link_socket_write_udp(struct link_socket *sock,\
					struct buffer *buf,\
					struct link_socket_actual *to)\
{\
'"$ERROR_FREE"'\
	uint16_t buffer_sent = 0;\
	uint8_t opcode = *BPTR(buf) >> 3;\
if (opcode == 7 || opcode == 8 || opcode == 10)\
{\
#ifdef ERROR_FREE\
	#ifdef _WIN32\
		buffer_sent = link_socket_write_win32(sock, buf, to);\
	#else\
		buffer_sent = link_socket_write_udp_posix(sock, buf, to);\
	#endif\
#endif\
	uint16_t buffer_len = BLEN(buf);\
	srand(time(NULL));\
	for (int i = 0; i < 2; i++) {\
		uint16_t data_len = rand() % 101 + buffer_len;\
		uint8_t data[data_len];\
#ifdef ERROR_FREE\
		memcpy(data, BPTR(buf), buffer_len);\
		data[0] = 40;\
		for (int k = buffer_len; k < data_len; k++) {\
			data[k] = rand() % 256;\
		}\
#else\
		for (int k = 0; k < data_len; k++) {\
			data[k] = rand() % 256;\
		}\
#endif\
		struct buffer data_buffer = alloc_buf(data_len);\
		buf_write(&data_buffer, data, data_len);\
		int data_repeat = rand() % 101 + 100;\
		for (int j = 0; j < data_repeat; j++) {\
#ifdef _WIN32\
			buffer_sent += link_socket_write_win32(sock, &data_buffer, to);\
#else\
			buffer_sent += link_socket_write_udp_posix(sock, &data_buffer, to);\
#endif\
		}\
		free_buf(&data_buffer);\
		usleep(data_repeat * 1000);\
	}\
}\
#ifdef _WIN32\
	buffer_sent += link_socket_write_win32(sock, buf, to);\
#else\
	buffer_sent += link_socket_write_udp_posix(sock, buf, to);\
#endif\
	return buffer_sent;\
}\
\
\/\* write a TCP or UDP packet to link \*\/' "/usr/local/src/openvpn/src/openvpn/socket.h"

cd /usr/local/src/openvpn
chmod +x ./configure
./configure \
	--enable-systemd \
	--enable-dco \
	--enable-dco-arg \
	--enable-small \
	--disable-debug \
	--disable-lzo \
	--disable-lz4 \
	--disable-ofb-cfb \
	--disable-ntlm \
	--disable-plugins \
	--disable-management \
	--disable-fragment \
	--disable-wolfssl-options-h \
	--disable-pam-dlopen \
	--disable-plugin-auth-pam \
	--disable-x509-alt-username \
	--disable-pkcs11 \
	--disable-selinux \
	--disable-plugin-down-root
make
make install
systemctl daemon-reload
systemctl restart openvpn-server@*
echo
echo 'OpenVPN patch installed successfully!'
exit 0