#!/bin/bash
#
#
#

##Define Variables##

PHP_VERSION=$(php --version | cut -d " " -f2 | head -1 | cut -d "." -f1,2)
SERVICES_TO_CHECK=("nginx" "mysql" "php$PHP_VERSION-fpm" "varnish" "cron" "redis" "elasticsearch")

CURRENT_DATE=$(date | awk -v a='/' -F " " '{print $2a$3a$4}')
START_TIME=$(date --date="30 minutes ago" +%H:%M:%S)
END_TIME=$(timedatectl | grep Local | awk -F " " '{print $5}')
TIME_FRAME="in the last 30 mintues"
INTEGER=^[0-9]+$

ABUSE_VALUE="10"

ServicesCheck(){

checkIfServiceIsEnabled(){
  for service in ${SERVICES_TO_CHECK[@]};do
   if ! systemctl is-enabled --quiet $service >/dev/null;then
    echo -ne "\e[31m-> $service is in disabled state \e[00m\n"
   fi
  done
}

checkIfServiceIsRunning(){
  for service in ${SERVICES_TO_CHECK[@]}; do
   if ! systemctl is-active --quiet $service >/dev/null;then
    echo -ne "\e[31m-> $service is in stopped state \e[00m\n"
   fi
  done
}

checkIfServiceIsEnabled
checkIfServiceIsRunning
}

CpuCheck(){

CPU_UTILIZATION=$(top -bn1 | grep "Cpu(s)" | awk -F "," '{print $4}' | cut -d " " -f2 | cut -d "." -f1 | awk '{print 100 - $1}')
  if  [ "$CPU_UTILIZATION" -ge "75" ];then

topFiveProcesses(){

LIST_PROCESSES=$(ps -eo pid,user,comm --sort=-%cpu | head -n $1)
  echo -ne "\n\e[33m-> Top Five Processes Utilizing CPU: \e[00m\n"
  echo -ne "\n$LIST_PROCESSES\n"
}

topTenIps(){

LIST_IPS=$(cat /home/cloudpanel/logs/*/*/access.log | awk '$4 >= "['$CURRENT_DATE':'$START_TIME'" && $4 < "['$CURRENT_DATE':'$END_TIME'"' |  awk -F" " '{print $1}' | sort | uniq -c | sort -k1 -n |tail -$1)

  echo -ne "\n\e[33m-> Top Ten IPs accessing all domains $TIME_FRAME: \e[00m\n"

    for LIST_IP in ${LIST_IPS[@]};do
      if ! [[ $LIST_IP =~ $INTEGER ]];then
DNS_LOOKUP=$(host $LIST_IP)
        echo -ne "\n$LIST_IP ($DNS_LOOKUP)\n" | sed '/^$/d'
      else
IP_HIT_COUNT=$LIST_IP
        echo -ne "\n$IP_HIT_COUNT "
      fi
    done
}

topTenBots(){

LIST_BOTS=$(cat /home/cloudpanel/logs/*/*/access.log | awk '$4 >= "['$CURRENT_DATE':'$START_TIME'" && $4 < "['$CURRENT_DATE':'$END_TIME'"' |  grep -oh -E "\w*Bot\w*|\w*bot" |sort | uniq -c | sort -k1 -n |tail -$1)
  echo -ne "\n\e[33m-> Top Ten Bots accessing all domains $TIME_FRAME: \e[00m\n"
  echo -ne "\n$LIST_BOTS\n"
}

checkAbuseIps(){

LIST_IPS=$(cat /home/cloudpanel/logs/*/*/access.log | awk '$4 >= "['$CURRENT_DATE':'$START_TIME'" && $4 < "['$CURRENT_DATE':'$END_TIME'"' |  awk -F" " '{print $1}' | sort | uniq | sort -k1 -n |tail -$1)

  echo -ne "\n\e[33m-> Top Ten IPs with Abuse Score greater than $ABUSE_VALUE $TIME_FRAME: \e[00m\n"
     for IP in ${LIST_IPS[@]}; do

API=$(curl -s -G https://api.abuseipdb.com/api/v2/check --data-urlencode "ipAddress=$IP" -d maxAgeInDays=90 -d verbose  -H "Key: d8dc9983dc9b8364f5208f6b706dcbed4dda697e9a6cf922636a49c6b865054aaf70c75ee5147939" -H "Accept: application/json")

ABUSE_SCORE=$(echo $API | awk -F [:] '{print $7}' | cut -d "," -f1)
       if  [ "$ABUSE_SCORE" -ge "$ABUSE_VALUE" ];then
         echo -ne "\n\e[93mIP Address: $IP\e[00m"
         echo -ne "\n Abuse Score: $ABUSE_SCORE% \n"
ORIGIN_COUNTRY=$(echo $API | awk -F [:] '{print $13}' | cut -d "," -f1)
         echo -ne " Origin Country: $ORIGIN_COUNTRY \n"
DOMAIN_NAME=$(echo $API | awk -F [:] '{print $11}' | cut -d "," -f1)
         echo -ne " Domain Name: $DOMAIN_NAME \n"
       fi
     done
}

checkIfMagentoCachesAreEnabled(){

VHOSTS=$(grep -Rli root /etc/nginx/sites-enabled)
  echo -ne "\n\e[33m-> Magento caches are  disabled for the following domains:  \e[00m\n"
    for VHOST in ${VHOSTS[@]};do

DOMAIN_NAME=$(grep -Ri root $VHOST | head -1 | sed 's/^.*\/htdocs//' | awk -F "/" '{print $2}' | awk -F ";" '{print $1}')
ENV_FILE="/home/cloudpanel/htdocs/"$DOMAIN_NAME"/app/etc/env.php"

      if  [ -f "$ENV_FILE" ];then
CACHES_COUNT=$(cat $ENV_FILE | sed -e '1,/cache_types/d' | head -15 | awk -F "=>" '{print $2}' |  cut -d " " -f2 | cut -d "," -f1 | grep "^0" | wc -l)
        if [ "$CACHES_COUNT" -ge "$1" ];then
          echo -ne "\n"$DOMAIN_NAME"\n" | sed '/^$/d'
        fi
      fi
    done
}

checkIfSlowLogsAreGenerated(){

SLOW_LOG_ENABLED=$(grep -Ri "slow_query_log_file" /etc/mysql/. | grep ";")


  if ! [[ "$?" == "0" ]];then

SLOW_LOG_PATH=$(grep -Ri "slow_query_log_file" /etc/mysql/. | awk -F "=" '{print $2}' | head -1)
SLOW_LOG_COUNT=$(grep 'Query_time:' $SLOW_LOG_PATH | wc -l)

    if [[ $SLOW_LOG_COUNT -gt 0 ]];then

LAST_SLOW_LOG_DATE=$(grep '# Time:' $SLOW_LOG_PATH | cut -d ":" -f2 | cut -d "T" -f1 | sed 's/^[ \t]*//' | tail -1)
LAST_SLOW_LOG_TIME=$(grep '# Time:' $SLOW_LOG_PATH | cut -d "T" -f3 | cut -d "." -f1 | tail -1)

      if [ -f "$SLOW_LOG_PATH" ];then

        echo -ne "\n\e[33m-> Slow Logs:  \e[00m\n"
        echo -ne "\n Total Slow Logs Generated: $SLOW_LOG_COUNT"
        echo -ne "\n Last Slow Log Generated at: $LAST_SLOW_LOG_TIME:$LAST_SLOW_LOG_DATE"
        echo -ne "\n To Verify Slow logs: tail -n$1 -f $SLOW_LOG_PATH\n"

      fi
    fi
  fi
}

topFiveProcesses 5
topTenIps 10
topTenBots 10
checkAbuseIps 10
checkIfMagentoCachesAreEnabled 14
checkIfSlowLogsAreGenerated 100
fi
}

##Establish the Run Order
Main(){
ServicesCheck
CpuCheck
}

Main 
