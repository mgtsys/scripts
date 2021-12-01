#!/bin/bash
#
#
#

##To Check default PHP version
php=$(php --version | cut -d " " -f2 | head -1 | cut -d "." -f1,2)


ServicesCheck(){

##Verify the Services are in Enabled state
checkIfserviceIsenabled(){
services=("$1" "$2" "$3$php-fpm" "$4" "$5")

for services in ${services[@]};do

if ! systemctl is-enabled $services >/dev/null;then
 echo -ne "\e[31m $services is in disabled state \e[00m\n"
fi

done
}

##Verify if the Services are in the Running State
checkIfserviceIsrunning(){
services=("$1" "$2" "$3$php" "$4" "$5")

for services in ${services[@]}; do

if  ! pgrep -x $services >/dev/null;then
  echo -ne "\e[31m $services is in stopped state\e[00m\n"
fi

done
}

checkIfserviceIsenabled nginx mysql php varnish cron
checkIfserviceIsrunning nginx mysqld php-fpm varnishd cron
}

##Establish the Run Order
Main(){
ServicesCheck
}

Main

