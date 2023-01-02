#!/bin/bash
echo ""
echo "Please provide the hostname for the server."
echo ""
echo "Use openvpn-project-name format for the hostname"
echo ""
sleep 1
read -p "Please enter hostname for the server: " host_name
echo "Changing the hostname of the server.."
echo "$host_name" > /etc/hostname
echo "127.0.0.1 $host_name" >> /etc/hosts
hostnamectl set-hostname $host_name
sleep 2
echo "Server Hostname updated successfully..!"
sleep 2
echo ""

echo "Installing OpenVPN server.."
sleep 3
apt-get update -y && apt-get -y upgrade && apt-get -y install openvpn-as > /home/mgt/creds.txt
sleep 2
echo ""
echo "OpenVPN server installed successfully!"
sleep 2
echo ""
echo "Updating Public IP address for OpenVPN.."
sleep 2
ipinfo=$(curl http://checkip.amazonaws.com)
/usr/local/openvpn_as/scripts/sacli --key "host.name" --value "$ipinfo" Configput
/usr/local/openvpn_as/scripts/sacli --key "vpn.daemon.0.listen.port" --value "1194" Configput
/usr/local/openvpn_as/scripts/sacli --key "vpn.daemon.0.listen.protocol" --value "udp" Configput
/usr/local/openvpn_as/scripts/sacli --key "vpn.server.daemon.enable" --value "false" Configput
/usr/local/openvpn_as/scripts/sacli --key "vpn.server.port_share.enable" --value "false" Configput
/usr/local/openvpn_as/scripts/sacli --key "vpn.server.daemon.protocols" --value "udp" Configput
systemctl restart openvpnas.service
echo ""
echo "Public IP updated for OpenVPN."
echo ""
echo "Generating credentials for OpenVPN.."
sleep 5
echo "" > /home/mgt/bitwarden.txt
echo "SSH Credentials" >> /home/mgt/bitwarden.txt
echo "---------------------------" >> /home/mgt/bitwarden.txt
echo "ssh mgtsys@$ipinfo" >> /home/mgt/bitwarden.txt
echo "Use default mgtsys password." >> /home/mgt/bitwarden.txt
echo "" >> /home/mgt/bitwarden.txt
echo "Admin UI" >> /home/mgt/bitwarden.txt
echo "---------------------------" >> /home/mgt/bitwarden.txt
echo "https://$ipinfo:943/admin" >> /home/mgt/bitwarden.txt
echo "" >> /home/mgt/bitwarden.txt
echo "Client UI" >> /home/mgt/bitwarden.txt
echo "---------------------------" >> /home/mgt/bitwarden.txt
echo "https://$ipinfo:943" >> /home/mgt/bitwarden.txt
echo "" >> /home/mgt/bitwarden.txt
sed "$(( $(wc -l <creds.txt)-4+1 )),$ d" /home/mgt/creds.txt > /home/mgt/temp.txt
tail -n 2 /home/mgt/temp.txt >> /home/mgt/bitwarden.txt
echo ""
echo "OpenVPN credentials are generated."
rm /home/mgt/temp.txt
rm /home/mgt/creds.txt
sleep 3
echo ""
echo ""
echo "---------------------------------------------------------------------"
echo "Add credentials from /home/mgt/bitwarden.txt file to the bitwarden."
echo "---------------------------------------------------------------------"
rm /home/mgt/openvpn.sh
