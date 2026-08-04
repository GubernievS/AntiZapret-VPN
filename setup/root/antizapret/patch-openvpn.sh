#!/bin/bash
#
# Патч для обхода блокировки протокола OpenVPN
# Работает только для UDP соединений
#
# chmod +x patch-openvpn.sh && ./patch-openvpn.sh [0-3]
#
set -e
export LC_ALL=C

handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

if [[ "$1" =~ ^[0-3]$ ]]; then
	ALGORITHM="$1"
else
	echo
	echo 'Choose anti-censorship patch for OpenVPN (UDP only):'
	echo '    0) None        - Do not install anti-censorship patch, or remove if already installed'
	echo '    1) Random      - Recommended by default, randomly selects Strong or Error-Free'
	echo '    2) Strong      - Better protocol masking'
	echo '    3) Error-Free  - Use if Strong patch causes connection error, recommended for routers'
	until [[ "$ALGORITHM" =~ ^[0-3]$ ]]; do
		read -rp 'Version choice [0-3]: ' -e -i 1 ALGORITHM
	done
fi

export DEBIAN_FRONTEND=noninteractive

if [[ "$ALGORITHM" == '0' ]]; then
	if [[ -d /usr/local/src/openvpn ]]; then
		make -C /usr/local/src/openvpn uninstall || true
		rm -rf /usr/local/src/openvpn
		apt-get update
		apt-get dist-upgrade -y
		apt-get install -y openvpn
		apt-get autoremove --purge -y
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
fi

if [[ "$ALGORITHM" == '1' ]]; then
	PATCH_MODE='		_Bool error_free = random() & 1;'
elif [[ "$ALGORITHM" == '2' ]]; then
	PATCH_MODE='		_Bool error_free = 0;'
else
	PATCH_MODE='		_Bool error_free = 1;'
fi

make -C /usr/local/src/openvpn uninstall || true
rm -rf /usr/local/src/openvpn
apt-get update
apt-get dist-upgrade -y
apt-get install -y openvpn curl tar build-essential pkg-config libssl-dev libsystemd-dev libnl-genl-3-dev libcap-ng-dev
apt-get autoremove --purge -y
apt-get clean
VERSION="$(openvpn --version | head -n 1 | awk '{print $2}')"
mkdir -p /usr/local/src/openvpn
curl -fL --connect-timeout 30 https://build.openvpn.net/downloads/releases/openvpn-$VERSION.tar.gz -o /usr/local/src/openvpn.tar.gz || curl -fL --connect-timeout 30 https://github.com/OpenVPN/openvpn/releases/download/v$VERSION/openvpn-$VERSION.tar.gz -o /usr/local/src/openvpn.tar.gz
tar --strip-components=1 -xvzf /usr/local/src/openvpn.tar.gz -C /usr/local/src/openvpn
rm -f /usr/local/src/openvpn.tar.gz

sed -i '/link_socket_write_udp(struct link_socket \*sock/,/^$/c\
link_socket_write_udp(struct link_socket *sock,\
					struct buffer *buf,\
					struct link_socket_actual *to)\
{\
	int opcode = *BPTR(buf) >> 3;\
	if (opcode == 7 || opcode == 8 || opcode == 10)\
	{\
'"$PATCH_MODE"'\
		ssize_t buffer_sent = 0;\
		if (error_free) {\
#ifdef _WIN32\
			buffer_sent = link_socket_write_win32(sock, buf, to);\
#else\
			buffer_sent = link_socket_write_udp_posix(sock, buf, to);\
#endif\
			if (buffer_sent < 0)\
				return buffer_sent;\
		}\
		int buffer_len = BLEN(buf);\
		for (int i = 0; i < 3; i++) {\
			int data_len = (int)(random() % 81 + buffer_len);\
			uint8_t data[data_len];\
			if (error_free) {\
				memcpy(data, BPTR(buf), buffer_len);\
				data[0] = (uint8_t)40;\
				for (int k = buffer_len; k < data_len; k++) {\
					data[k] = (uint8_t)(random() % 256);\
				}\
			} else {\
				uint8_t first_byte;\
				do {\
					first_byte = (uint8_t)(random() % 256);\
				} while ((first_byte >> 3) >= 1 && (first_byte >> 3) <= 11);\
				data[0] = first_byte;\
				for (int k = 1; k < data_len; k++) {\
					data[k] = (uint8_t)(random() % 256);\
				}\
			}\
			struct buffer data_buffer = alloc_buf(data_len);\
			buf_write(&data_buffer, data, data_len);\
			for (int j = 0; j < 50; j++) {\
#ifdef _WIN32\
				(void)link_socket_write_win32(sock, &data_buffer, to);\
#else\
				(void)link_socket_write_udp_posix(sock, &data_buffer, to);\
#endif\
			}\
			free_buf(&data_buffer);\
		}\
		if (error_free)\
			return buffer_sent;\
	}\
#ifdef _WIN32\
	return link_socket_write_win32(sock, buf, to);\
#else\
	return link_socket_write_udp_posix(sock, buf, to);\
#endif\
}\
' /usr/local/src/openvpn/src/openvpn/socket.h

(
	cd /usr/local/src/openvpn
	chmod +x ./configure
	./configure \
		--enable-systemd \
		--enable-dco \
		--enable-comp-stub \
		--enable-small \
		--enable-port-share \
		--disable-static \
		--disable-debug \
		--disable-dns-updown-by-default \
		--disable-lzo \
		--disable-lz4 \
		--disable-ofb-cfb \
		--disable-plugins \
		--disable-fragment \
		--disable-unit-tests \
		--disable-ntlm \
		--disable-wolfssl-options-h \
		--disable-pam-dlopen \
		--disable-plugin-auth-pam \
		--disable-pkcs11 \
		--disable-selinux \
		--disable-plugin-down-root
	make
	make install
)
systemctl daemon-reload
systemctl restart openvpn-server@*
echo
echo 'OpenVPN patch installed successfully!'
exit 0