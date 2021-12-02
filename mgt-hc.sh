#!/bin/bash
#
#
#

PHP_VERSION=$(php --version | cut -d " " -f2 | head -1 | cut -d "." -f1,2)
SERVICES_TO_CHECK=("nginx" "mysql" "php$PHP_VERSION-fpm" "varnish" "cron" "redis" "elasticsearch")

ServicesCheck(){

checkIfServiceIsEnabled(){

for service in ${SERVICES_TO_CHECK[@]};do

if ! systemctl is-enabled --quiet $service >/dev/null;then
 echo -ne "\e[31m $service is in disabled state \e[00m\n"
fi

done
}

checkIfServiceIsRunning(){

for service in ${SERVICES_TO_CHECK[@]};do

if ! systemctl is-active --quiet $service >/dev/null;then
 echo -ne "\e[31m $service is in stopped state \e[00m\n"
fi

done
}

checkIfServiceIsEnabled
checkIfServiceIsRunning
}

##Establish the Run Order
Main(){
ServicesCheck
}

Main
