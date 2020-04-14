#!/bin/bash

#For Elasticsearch 5
#wget -Nnv 'https://gist.github.com/mgtsys/306543e4eaae0bad9cbac12ec13fbfe8/raw/elasticsearch.sh' && sh elasticsearch.sh 5 && rm -f elasticsearch.sh
#For Elasticsearch 6
#wget -Nnv 'https://gist.github.com/mgtsys/306543e4eaae0bad9cbac12ec13fbfe8/raw/elasticsearch.sh' && sh elasticsearch.sh 6 && rm -f elasticsearch.sh
#For Elasticsearch 7
#wget -Nnv 'https://gist.github.com/mgtsys/306543e4eaae0bad9cbac12ec13fbfe8/raw/elasticsearch.sh' && sh elasticsearch.sh 7 && rm -f elasticsearch.sh

die()
{
  /bin/echo -e "ERROR: $*" &>/dev/null
  exit 1
}

version=$1
if [ -z "$version" ]; then
    version="6"
    echo "Version does not exist"
fi
# Checking whether user has enough permission to run this script
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

installJava() {
java -version
if [ $? -ne 0 ]
    then
        # Installing Java 11 if it's not installed
        sudo apt-get update  >/dev/null 2>&1
        sudo apt-get install openjdk-11-jre  -y  >/dev/null 2>&1
 fi
}
installElasticsearch() {
    echo "Installing elasticsearch ..."
    # resynchronize the package index files from their sources.
    sudo apt-get update >/dev/null 2>&1
    # Downloading debian package of elasticsearch
    wget -q https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add >/dev/null 2>&1
    repo_url=https://artifacts.elastic.co/packages/$version.x/apt >/dev/null 2>&1
    repository="deb "$repo_url" stable main" >/dev/null 2>&1
    {
      echo $repository | sudo tee -a /etc/apt/sources.list.d/elastic-$version.x.list
    } > /dev/null 2>&1
    # Install elasticsearch debian package
    #apt-get update 2>&1 && sudo apt-get install elasticsearch >/dev/null 2>&1
    {
      apt-get update && sudo apt-get install elasticsearch
    } > /dev/null 2>&1
    #Installation for the pluginshistor
    cd /usr/share/elasticsearch
    bin/elasticsearch-plugin install analysis-phonetic >/dev/null 2>&1
    bin/elasticsearch-plugin install analysis-icu >/dev/null 2>&1
    # Starting The Services
    sudo systemctl restart elasticsearch >/dev/null 2>&1
    sudo systemctl enable elasticsearch >/dev/null 2>&1
}
configuration() {
    echo "Configuring elasticsearch ..."
    echo $version
    if [ ${version} -eq "7" ]; then
	ex -s -c '54i|network.host: 0.0.0.0' -c x /etc/elasticsearch/elasticsearch.yml
   	ex -s -c '55i|discovery.seed_hosts: [127.0.0.1]' -c x /etc/elasticsearch/elasticsearch.yml
   else
  # Change the Elasticsearch parameters
   	ex -s -c '54i|network.host: 0.0.0.0' -c x /etc/elasticsearch/elasticsearch.yml
   fi
  # Configure symlink
  mv /var/lib/elasticsearch /home/ >/dev/null 2>&1
  cd /var/lib >/dev/null 2>&1
  ln -s /home/elasticsearch . >/dev/null 2>&1
  chown -h elasticsearch:elasticsearch elasticsearch
  /etc/init.d/elasticsearch restart >/dev/null 2>&1
  sleep 10
}
showSuccessMessage()
{
  IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
  check_version=$IP:9200
  sleep 3
  elasticsearch_version=$(curl -s -X GET  $check_version | sed -n '6p')
  elasticsearch_version=$(echo "$elasticsearch_version" | cut -d ':' -f 2)
  if [ ! -z "$elasticsearch_version" ]; then
    printf "\n\n"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
    printf "The installation of Elasticsearch is complete!\n\n"
    printf "Elasticsearch  $elasticsearch_version is installed. You can now access Elasticsearch in $IP port 9200\n"
    printf "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n"
  else
    printf "\n$elasticsearch_version"
    printf "\nFAILED\n"
  fi
}
checkRoot
checkOperatingSystem
installJava >/dev/null 2>&1
installElasticsearch
configuration
sleep 7
showSuccessMessage
