#!/bin/bash

cprompt() {
  echo -ne "\e[32;1m$@\e[0m\t"
}

# Install updates and software
cprompt "Installing necessary software..."
sudo apt update
sudo apt install -y openvpn easy-rsa

# Set up the CA directory
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

cprompt "Enter values for the following certificate fields (or ENTER through to accept defaults): "
echo ""
read -p "Country: " _country
_country="${_country:-US}"
read -p "State:   " _state
_state="${_state:-UT}"
read -p "City:    " _city
_city="${_city:-'Salt Lake City'}"
read -p "Org:     " _org
_org="${_org:-DigitalOcean}"
read -p "Email:   " _email
_email="${_email:-admin@localdomain}"
read -p "OU:      " _ou
_ou="${_ou:-Community}"

sed -r -i.bak "/KEY_COUNTRY=/ s/(\"[^\"]+\")/${_country}/" vars
sed -r -i.bak "/KEY_PROVINCE=/ s/(\"[^\"]+\")/${_state}/" vars
sed -r -i.bak "/KEY_CITY=/ s/(\"[^\"]+\")/${_city}/" vars
sed -r -i.bak "/KEY_ORG=/ s/(\"[^\"]+\")/${_org}/" vars
sed -r -i.bak "/KEY_EMAIL=/ s/(\"[^\"]+\")/${_email}/" vars
sed -r -i.bak "/KEY_OU=/ s/(\"[^\"]+\")/${_ou}/" vars
sed -r -i.bak "/KEY_NAME=/ s/(\"[^\"]+\")/server/" vars

# Build the CA 
. vars
./clean-all
./build-ca --batch

# Create server certificate, key, encryption files
cprompt Building server key pair, accept all defaults and answer \"y\" to sign keys && echo ""
./build-key-server server
echo -ne '\e[31;1mWARNING: \e[0m'
cprompt "Building Diffie-Hellman parameters..." && echo ""
./build-dh &>dh-params-output.log
openvpn --genkey --secret keys/ta.key

# Copy necessary files to openvpn server directory
cprompt Copying server files, might need to elevate && echo ""
cd ~/openvpn-ca/keys
sudo cp ca.crt ca.key server.crt server.key ta.key dh2048.pem /etc/openvpn

gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz |	\
	sed -r						\
		-e '/tls-auth/ s/^[#;]//'		\
		-e '/cipher AES-128-CBC/ s/^[;#]//'	\
		-e '/^user\s|^group\s/ s/^[#;]//'	\
		-e '/dhcp-option DNS/ s/^[#;]//'	\
		-e '/redirect-gateway/ s/^[#;]//'	\
		-e '/^port/ s/.*/port 443/'		\
		-e '/^proto/ s/.*/proto tcp/'		\
		-e '$ a key-direction 0'		\
		-e '$ a auth SHA256'			\
		-e '$ a tls-server'			\
		-e '$ a mode server'			\
			| sudo tee /etc/openvpn/server.conf

# Adjust network config
sudo sed -i.bak '/net.ipv4.ip_forward/ s/^#//' /etc/sysctl.conf
sudo sysctl -p

yes | sudo apt autoremove ufw
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
yes | sudo apt install iptables-persistent

sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server
sudo systemctl status openvpn@server | tee /dev/null

# Build client configuration stuff
_server="$(curl -s icanhazip.com)"
cprompt "Building configurations for your clients with a server of '${_server}'"
cd ~/openvpn-ca
. vars

_counter=0
while true; do
  cprompt Enter a name for your client : && read _cname
  _cname="${_cname:=client${_counter}}"
  _counter=$[_counter+1]

  cprompt Building your key, use defaults and answer \"y\" to signing questions. && echo ""
  ./build-key "${_cname}"

  _config="${_cname}.ovpn"
  cat <<-EOF >"${_config}"
	client
	tls-client
	dev tun
	proto tcp
	remote ${_server} 443
	resolv-retry infinite
	nobind
	user nobody
	group nogroup
	persist-key
	persist-tun
	remote-cert-tls server
	cipher AES-128-CBC
	auth SHA256
	comp-lzo
	verb 3
	key-direction 1
	<ca>
	$(cat keys/ca.crt)
	</ca>
	<cert>
	$(cat keys/${_cname}.crt)
	</cert>
	<key>
	$(cat keys/${_cname}.key)
	</key>
	<tls-auth>
	$(cat keys/ta.key)
	</tls-auth>
	EOF

  cp -v "${_config}" ~/

  cprompt Do you want to generate additional client certs? [n] && read _p
  if [[ "${_p:=n}" == "n" ]]; then break; fi
done

# Finished
cd ~
rm -rf openvpn-ca

echo -e '\e[32;1m'
cat <<-EOF
	[+] All finished! Your client configurations have been copied to $(cd ~ && pwd -P)

	To use the configurations, copy them to their respective clients and run:
	  # openvpn --config configname.ovpn

	Alternatively, some Linux GUIs allow you to integrate the VPN functionality
	into the networking icon on the toolbar. Check out the following plugin in
	the apt repositories if you're interested:
	    network-manager-openvpn-gnome	

	EOF
echo -e '\e[0m'
