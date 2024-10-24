## Documentation: OpenVPN Server Setup Script

### Overview
This bash script automates the process of setting up an OpenVPN server on a Linux system. It installs necessary packages, configures certificates, keys, networking, firewall rules, and starts the OpenVPN service.

### Requirements
- Root or sudo access.
- Ubuntu or Debian-based system.
- Network interface (replace `ens18` with your interface name).
- Arguments `Port Number` `Public IP` `VM IP` `VM Network ID` `VM Subnet Mask`
    - Example 128.187.0.1 10.0.0.2 10.0.0.0 255.255.255.0

### Steps

1. **Update System and Install OpenVPN**:
   - Updates package list and installs OpenVPN and EasyRSA for certificate management.
   
   ```bash
   apt update -y
   apt install openvpn easy-rsa -y
   ```

2. **Create EasyRSA Directory**:
   - Sets up the EasyRSA directory and symbolic links for use in the script.
   
   ```bash
   mkdir /home/$user/easy-rsa
   ln -s /usr/share/easy-rsa/* /home/$user/easy-rsa/
   sudo chown -R vpn:sudo /home/$user/easy-rsa
   sudo chmod -R 700 /home/$user/easy-rsa
   ```

3. **Initialize PKI and Configure CA**:
   - Initializes the Public Key Infrastructure (PKI) and sets variables for the certificate authority (CA).
   
   ```bash
   ./easyrsa init-pki
   echo 'set_var EASYRSA_REQ_COUNTRY "US"' > /home/$user/easy-rsa/vars
   ./easyrsa --batch build-ca nopass
   ```

4. **Generate Server Certificates**:
   - Generates server keys and certificates, and places them in appropriate directories.
   
   ```bash
   ./easyrsa --batch gen-req server nopass
   ./easyrsa --batch sign-req server server
   cp /home/$user/easy-rsa/pki/private/server.key /etc/openvpn/server/
   cp /home/$user/easy-rsa/pki/issued/server.crt /etc/openvpn/server
   ```

5. **TLS Key Generation**:
   - Generates TLS authentication key for secure communication.
   
   ```bash
   openvpn --genkey secret ta.key
   cp ta.key /etc/openvpn/server
   ```

6. **Client Certificates**:
   - Generates client certificates and keys.
   
   ```bash
   ./easyrsa --batch gen-req clientDefault nopass
   ./easyrsa --batch sign-req client clientDefault
   cp /home/$user/easy-rsa/pki/issued/clientDefault.crt /home/$user/client-configs/keys/
   ```

7. **OpenVPN Server Configuration**:
   - Creates OpenVPN server configuration file (`server.conf`).
   
   ```bash
   cat <<EOF > /etc/openvpn/server/server.conf
   # Configuration details (ports, encryption, etc.)
   EOF
   ```

8. **IP Forwarding & Firewall Rules**:
   - Configures IP forwarding and updates UFW rules for OpenVPN traffic.
   
   ```bash
   echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
   sysctl -p
   ufw allow $1/udp
   ufw allow OpenSSH
   ```

9. **Certificate Revocation List (CRL)**:
   - Generates CRL to manage revoked certificates.
   
   ```bash
   ./easyrsa --batch --days=30 gen-crl
   cp /home/$user/easy-rsa/pki/crl.pem /etc/openvpn/server/
   ```

10. **Enable and Start OpenVPN Service**:
    - Starts and enables the OpenVPN server service.
    
    ```bash
    systemctl enable --now openvpn-server@server.service
    ```

11. **Iptables Service**:
    - Configures iptables rules for the OpenVPN server.
    
    ```bash
    systemctl enable --now openvpn-iptables.service
    ```

12. **Client Configuration**:
    - Prepares the client configuration file for download and use on client devices.

    ```bash
    echo "client
    # client config details
    " > /home/$user/client-configs/base.conf
    ```

## Documentation: OpenVPN Client Configuration Script

### Overview
This script creates a complete OpenVPN client configuration file (`.ovpn`) for a specified client. It generates client certificates and combines them with the server configuration to produce a ready-to-use configuration file for the client.

### Arguments
- **First argument (`$1`)**: The client identifier (e.g., client name).

### Steps

1. **Navigate to EasyRSA Directory**:
   - The script starts by changing to the EasyRSA directory, where certificate generation and management happen.
   
   ```bash
   cd /home/$user/easy-rsa
   ```

2. **Generate Client Certificate**:
   - Creates a client certificate and key, valid for 3650 days (approximately 10 years), without requiring a password.
   
   ```bash
   ./easyrsa --batch --days=3650 build-client-full "$1" nopass
   ```

3. **Set Directory Variables**:
   - Defines directories used to store keys, certificates, and the final output configuration file:
     - `SERVER_KEY_DIR`: Directory for server-related keys.
     - `KEY_DIR`: Private keys directory.
     - `ISSUES_DIR`: Issued certificates directory.
     - `OUTPUT_DIR`: Where the final `.ovpn` file is saved.
     - `BASE_CONFIG`: Path to the base client configuration file.

4. **Create `.ovpn` File**:
   - Combines the base client configuration with the client-specific keys and certificates. Each section (CA, certificate, key, and TLS key) is embedded within appropriate `<tags>` to form the final `.ovpn` file.
   
   ```bash
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
   ```

5. **Set Permissions**:
   - Changes ownership and permissions of the generated `.ovpn` file to ensure security and access control.
   
   ```bash
   chown $user:sudo ${OUTPUT_DIR}/$1.ovpn
   chmod 700 ${OUTPUT_DIR}/$1.ovpn
   ```

### Output
- A complete `.ovpn` client configuration file is saved in `/home/$user/client-configs/files/` with the client identifier as its filename (e.g., `client1.ovpn`).