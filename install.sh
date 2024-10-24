#!/bin/bash

apt update -y
apt install openvpn easy-rsa -y

mkdir /home/$6/easy-rsa

ln -s /usr/share/easy-rsa/* /home/$6/easy-rsa/

sudo chown -R vpn:sudo /home/$6/easy-rsa
sudo chmod -R 700 /home/$6/easy-rsa

cd /home/$6/easy-rsa
./easyrsa init-pki

echo 'set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "Utah"
set_var EASYRSA_REQ_CITY       "Provo"
set_var EASYRSA_REQ_ORG        ""
set_var EASYRSA_REQ_EMAIL      ""
set_var EASYRSA_REQ_OU         ""
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
set_var EASYRSA_REQ_CN 		   ""'> /home/$6/easy-rsa/vars

./easyrsa --batch build-ca nopass

cp /home/$6/easy-rsa/pki/ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

./easyrsa --batch gen-req server nopass

cp /home/$6/easy-rsa/pki/private/server.key /etc/openvpn/server/

./easyrsa --batch sign-req server server

cp /home/$6/easy-rsa/pki/issued/server.crt /etc/openvpn/server
cp /home/$6/easy-rsa/pki/ca.crt /etc/openvpn/server

openvpn --genkey secret ta.key

cp ta.key /etc/openvpn/server

mkdir -p /home/$6/client-configs/keys
chmod -R 700 -R /home/$6/client-configs
chown vpn:sudo -R /home/$6/client-configs

./easyrsa --batch gen-req clientDefault nopass
mv /home/$6/easy-rsa/pki/private/clientDefault.key /home/$6/client-configs/keys/

./easyrsa --batch sign-req client clientDefault
mv /home/$6/easy-rsa/pki/issued/clientDefault.crt /home/$6/client-configs/keys/

cp /home/$6/easy-rsa/ta.key /home/$6/client-configs/keys/

cp /etc/openvpn/server/ca.crt /home/$6/client-configs/keys/
chown vpn:sudo /home/$6/client-configs/keys/

cat <<EOF > /etc/openvpn/server/server.conf
port $1
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh none
topology subnet
server 10.8.0.0 255.255.255.0
push "route 10.8.0.0 255.255.255.0"
push "route $4 $5"
ifconfig-pool-persist /var/log/openvpn/ipp.txt
keepalive 10 60
tls-crypt ta.key
cipher AES-256-GCM
auth SHA256
max-clients 100
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
log-append /var/log/openvpn/openvpn.log
verb 6
crl-verify /etc/openvpn/server/crl.pem
explicit-exit-notify 1
EOF

echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

echo "# START OPENVPN RULES
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]
# Allow traffic from OpenVPN client to ens18 (change to the interface you discovered!)
-A POSTROUTING -s 10.8.0.0/8 -o ens18 -j MASQUERADE
COMMIT
# END OPENVPN RULES" > temp_file
cat /etc/ufw/before.rules >> temp_file
mv temp_file /etc/ufw/before.rules

sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

ufw allow $1/udp
ufw allow OpenSSH
ufw disable
ufw enable

useradd nobody
groupadd nobody

./easyrsa --batch --days=30 gen-crl
cp /home/$6/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem

chown nobody:nobody /etc/openvpn/server/crl.pem

systemctl -f enable openvpn-server@server.service
systemctl start openvpn-server@server.service
systemctl status openvpn-server@server.service


mkdir /home/$6/client-configs/files
chown vpn:sudo /home/$6/client-configs/files
chmod 700 /home/$6/client-configs/files

touch /home/$6/client-configs/base.conf
chown vpn:sudo /home/$6/client-configs/base.conf
chmod 700 /home/$6/client-configs/base.conf

echo "client
dev tun
proto udp
remote $2 $1
user nobody
group nobody
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
verb 1
key-direction 1
; script-security 2
; up /etc/openvpn/update-resolv-conf
; down /etc/openvpn/update-resolv-conf
; script-security 2
; up /etc/openvpn/update-systemd-resolved
; down /etc/openvpn/update-systemd-resolved
; down-pre
; dhcp-option DOMAIN-ROUTE ." >  /home/$6/client-configs/base.conf

echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $3
ExecStart=/usr/sbin/iptables -I INPUT -p udp --dport $1 -j ACCEPT
ExecStart=/usr/sbin/iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStart=/usr/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/usr/sbin/iptables -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $3
ExecStop=/usr/sbin/iptables -D INPUT -p udp --dport $1 -j ACCEPT
ExecStop=/usr/sbin/iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
ExecStop=/usr/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" > /etc/systemd/system/openvpn-iptables.service

echo "RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/openvpn-iptables.service
		systemctl enable --now openvpn-iptables.service
