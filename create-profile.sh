#!/bin/bash
 
# First argument: Client identifier

cd /home/$2/easy-rsa

./easyrsa --batch --days=3650 build-client-full "$1" nopass

SERVER_KEY_DIR=/home/$2/client-configs/keys
KEY_DIR=/home/$2/easy-rsa/pki/private/
ISSUES_DIR=/home/$2/easy-rsa/pki/issued/
OUTPUT_DIR=/home/$2/client-configs/files
BASE_CONFIG=/home/$2/client-configs/base.conf

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${SERVER_KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${ISSUES_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-crypt>') \
    ${SERVER_KEY_DIR}/ta.key \
    <(echo -e '</tls-crypt>') \
    > ${OUTPUT_DIR}/$1.ovpn

chown $2:sudo ${OUTPUT_DIR}/$1.ovpn
chmod 700 ${OUTPUT_DIR}/$1.ovpn