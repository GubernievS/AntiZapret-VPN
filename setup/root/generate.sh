#!/bin/bash
set -e
HERE="$(dirname "$(readlink -f "${0}")")"
cd "$HERE/easyrsa3"

export EASYRSA_CERT_EXPIRE=3650

set +e

SERVER=""
for i in 1 2 3 4 5;
do
    SERVER="$(curl -s -4 icanhazip.com)"
    [[ "$?" == "0" ]] && break
    sleep 2
done
[[ ! "$SERVER" ]] && echo "Can't determine global IP address!" && exit

set -e

render() {
    local IFS=''
    local File="$1"
    while read -r line ; do
        while [[ "$line" =~ (\$\{[a-zA-Z_][a-zA-Z_0-9]*\}) ]] ; do
        local LHS=${BASH_REMATCH[1]}
        local RHS="$(eval echo "\"$LHS\"")"
        line=${line//$LHS/$RHS}
        done
        echo "$line"
    done < $File
}

load_key() {
    CA_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/server/keys/ca.crt")
    CLIENT_CERT=$(grep -A 999 'BEGIN CERTIFICATE' -- "/etc/openvpn/client/keys/antizapret-client.crt")
    CLIENT_KEY=$(cat -- "/etc/openvpn/client/keys/antizapret-client.key")
    TLS_CRYPT=$(cat -- "/etc/openvpn/server/keys/tls-crypt.key")
    if [ ! "$CA_CERT" ] || [ ! "$CLIENT_CERT" ] || [ ! "$CLIENT_KEY" ] || [ ! "$TLS_CRYPT" ]
    then
        echo "Can't load client keys!"
        exit
    fi
}

build_pki() {
    rm -rf ./pki/
    /usr/share/easy-rsa/easyrsa init-pki
    echo -e "set_var EASYRSA_ALGO ec\nset_var EASYRSA_CURVE prime256v1" > ./pki/vars
    EASYRSA_CA_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch --req-cn="AntiZapret CA" build-ca nopass
    EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-server-full "antizapret-server" nopass
    EASYRSA_CERT_EXPIRE=3650 /usr/share/easy-rsa/easyrsa --batch build-client-full "antizapret-client" nopass
    EASYRSA_CRL_DAYS=3650 /usr/share/easy-rsa/easyrsa gen-crl
    openvpn --genkey secret ./pki/tls-crypt.key
}

copy_keys() {
    cp ./pki/ca.crt /etc/openvpn/server/keys/ca.crt
    cp ./pki/issued/antizapret-server.crt /etc/openvpn/server/keys/antizapret-server.crt
    cp ./pki/private/antizapret-server.key /etc/openvpn/server/keys/antizapret-server.key
    cp ./pki/issued/antizapret-client.crt /etc/openvpn/client/keys/antizapret-client.crt
    cp ./pki/private/antizapret-client.key /etc/openvpn/client/keys/antizapret-client.key
    cp ./pki/crl.pem /etc/openvpn/server/keys/crl.pem
    cp ./pki/tls-crypt.key /etc/openvpn/server/keys/tls-crypt.key
}

if [[ ! -f /etc/openvpn/server/keys/ca.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.crt ]] || \
   [[ ! -f /etc/openvpn/server/keys/antizapret-server.key ]] || \
   [[ ! -f /etc/openvpn/client/keys/antizapret-client.crt ]] || \
   [[ ! -f /etc/openvpn/client/keys/antizapret-client.key ]] || \
   [[ ! -f /etc/openvpn/server/keys/crl.pem ]] || \
   [[ ! -f /etc/openvpn/server/keys/tls-crypt.key ]]
then
    build_pki
    copy_keys
fi

load_key
render "/etc/openvpn/client/templates/openvpn-udp-unified.conf" > "/etc/openvpn/client/antizapret-client-udp.ovpn"
render "/etc/openvpn/client/templates/openvpn-tcp-unified.conf" > "/etc/openvpn/client/antizapret-client-tcp.ovpn"
