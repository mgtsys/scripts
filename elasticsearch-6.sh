#!/bin/bash

#ONE LINE
#sudo wget -Nnv 'https://gist.github.com/mgtsys/scripts/elasticsearch-6.sh' && bash elasticsearch-6.sh && rm -f elasticsearch-6.sh

# Checking whether user has enough permission to run this script
die()
{
  /bin/echo -e "ERROR: $*" >&2
  exit 1
}
checkRoot()
{
  if [ `id -u` -ne 0 ]; then
    die "You should have superuser privileges to install Java and Elasticsearch"
  fi
}
checkOperatingSystem()
{
  local debianVersion
  local debianMainVersion

  if [ ! -f '/etc/debian_version' ]; then
    die "Operating system is not supported. Only Debian is supported."
  else
    debianVersion=$(cat /etc/debian_version)
    debianMainVersion=`echo $debianVersion | cut -d "." -f -1`
    if [ "$debianMainVersion" -ne "10" ]; then
      die "Only Debian Buster is supported"
    fi
  fi
}
setIp()
{
  IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
  IP=$(echo "$IP" | cut -d"," -f1)
}
installJava() {
java -version
if [ $? -ne 0 ]
    then
        # Installing Java 11 if it's not installed
        sudo apt-get update
        sudo apt-get install openjdk-11-jre  -y
 fi
}
installElasticsearch() {
    # resynchronize the package index files from their sources.
    sudo apt-get update
    # Downloading debian package of elasticsearch
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
    echo "deb https://artifacts.elastic.co/packages/6.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-6.x.list
    # Install elasticsearch debian package
    apt-get update && sudo apt-get install elasticsearch
    #Installation for the pluginshistor
    cd /usr/share/elasticsearch
    bin/elasticsearch-plugin install analysis-phonetic
    bin/elasticsearch-plugin install analysis-icu
    # Starting The Services
    sudo systemctl restart elasticsearch
    sudo systemctl enable elasticsearch
}
configuration() {
  # Change the Elasticsearch parameters
   ex -s -c '54i|network.host: 0.0.0.0' -c x /etc/elasticsearch/elasticsearch.yml
  # Configure symlink
  mv /var/lib/elasticsearch /home/
  cd /var/lib
  ln -s /home/elasticsearch .
  chown -h elasticsearch:elasticsearch elasticsearch
  /etc/init.d/elasticsearch restart
}
showSuccessMessage()
{
  IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
  IP=$(echo "$IP" | cut -d"," -f1)
  check_version=$IP:9200
  elasticsearch_version=$(curl -X GET  $check_version)
  elasticsearch_version==$(echo "$elasticsearch_status" | sed -n '6p';)
  if [ -f "elasticsearch_version" ]; then
    printf "\n\n"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
    printf "The installation of Elasticsearch is complete!\n\n"
    printf "Elasticsearch  $elasticsearch_version is installed. You can now access Elasticsearch in $IP port 9200"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
  fi
}
checkRoot
checkOperatingSystem
installJava
installElasticsearch
configuration
showSuccessMessage
