#!/bin/bash
INPUT=$1
if [ -z "${INPUT}" ]; then
    echo "Please input a plan (e.g. basic | premium | ultimate | enterprise)"
    exit 1
elif [[ ${INPUT} != "basic" && ${INPUT} != "premium" && ${INPUT} != "ultimate" && ${INPUT} != "enterprise" ]]; then
    echo "Please input VALID plan (e.g. basic | premium | ultimate | enterprise)"
    exit 1
fi

NOT_OK="     \e[38;5;198mNOT OK: \e[0m"
PRIVATE_IP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')

FILE=""
MYSQL_U=""
MYSQL_P=""
MYSQL_DB=""
ROOT_DIR=""
CONFIG_FILE=""
REDIRECTION_HTTPS="" 

PORTS=()
USERS=()

MAGENTO_VERSION=1

TEST=false
IS_BASIC_AUTH=true
IS_MYSQL_WORKING=false



# checks the pools configuration of php, takes user owner and port number of pools. 
function check_php_fpm_ports {
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "-" -f 1 | cut -d "." -f 1-2)
    #check if it is version 5 or 7 of php (because directories of pools are different for 5 and 7 version)
    if [[ ${PHP_VERSION} == *"5."* ]]; then cd /etc/php5/fpm/pool.d/
    else cd /etc/php/${PHP_VERSION}/fpm/pool.d/; fi
    # for each file in the pool.d directory except global.conf and clp.conf (default ones) then get the port and owner and put them in
    # a common array ports() and USERS() that later will be chekced in nginx configuration files. 
    for FPM_FILE in *.conf; do
        if [ "${FPM_FILE}" != "clp.conf" -a "${FPM_FILE}" != "global.conf" ]; then
            PORTS+=($(sed -n 2p ${FPM_FILE} | cut -d ":" -f 2))
            USERS+=($(sed -n 3p ${FPM_FILE} | cut -d " " -f 3))
        fi
    done
}

# checks if the ports in the nginx config file are ok and if the ownership of the files corresponds with that port. 
function check_ownership() {
    # get the configured port in nginx file. 
    NGINX_PORT=$(sed -n "/fastcgi_pass/p" ${FILE} | awk 'NR == 1' | cut -d ":" -f 2 | cut -d ";" -f 1)
    ROOT_DIR=$(sed -n "/root/p" ${FILE} | awk 'NR == 1' | cut -d "/" -f 2-5 | cut -d ";" -f 1)
    # checks in the array which user uses that port (taken form php pool) and checks which user is the owner of the root directory  
    # If config is oK then resets permissions 775 just in case. 
    for i in "${!PORTS[@]}"; do
        if [[ "${PORTS[$i]}" = "${NGINX_PORT}" ]]; then
            OWNER_FOLDER=$(ls -lrt "/${ROOT_DIR}" | awk 'NR == 2' | cut -d " " -f 4)
            if [[ "${OWNER_FOLDER}" != "${USERS[$i]}" ]]; then
                echo -e "${NOT_OK}File ${FILE} uses port ${NGINX_PORT} (user ${USERS[$i]}) and root folder's owner is ${OWNER_FOLDER}"
            else
                #resetting 775 permissions to make sure permissions are right. cannot check that all folders have 775. 
                echo "     Setting 775 permissions for root folder ${ROOT_DIR}" 
                chmod -R 775 "/${ROOT_DIR}/"
            fi
        fi
    done
}

# checks if the https redirection (from http -> https) is working. 
function check_https_redirection() {
    # we take the server names from the nginx config file (as we can have more than one www1, www or without www)
    while read -r LINE; do
        # we get one of the server name
        SERVER_NAME=$(echo ${LINE} | cut -d " " -f 2 | cut -d ";" -f 1)
        # we make sure we have not checked this server name before 
        if [[ $PREV_HOST != *"${SERVER_NAME}"* ]]; then
            # we get the response of curl with http
            #REDIRECTION=$(curl -s -Ik http://"${SERVER_NAME}" --resolve ${SERVER_NAME}:${PRIVATE_IP})
            REDIRECTION=$(curl --resolve ${SERVER_NAME}:80:${PRIVATE_IP} http://${SERVER_NAME}:80 -Ik -s)
            # we get the server_name redirected (in case we are doing it with www and it redirects to without or with www1...)
            REDIRECTION_HTTPS=$(echo "${REDIRECTION,,}" | grep "location" | cut -d "/" -f 3)
            # get the protocol of the redirection (https or http) -> should be https 
            PROTOCOL=$(echo "${REDIRECTION,,}" | grep "location" | cut -d ":" -f 2)
            if [[ "${PROTOCOL}" != " https" ]]; then echo -e "${NOT_OK}Url ${SERVER_NAME} does not redirect to https"; fi
        fi
        PREV_HOST="${SERVER_NAME}"
    done < <(sed -n "/server_name/p" ${FILE} | head -n 2)
}

# as it is a new config we check that alias (www1) is right configured.
function check_alias() {
    # as test does not need alias -> we skip it 
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} != *"test"* ]]; then
        # now we connect using https instead of http
        #CURL_HTTPS=$(curl -s -Ik https://"${REDIRECTION_HTTPS}" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP})
        CURL_HTTPS=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -s -Ik)
        # just make sure that one of the sever_name has www1 in nginx config file
        ALIAS_WWW1=$(sed -n "/server_name/p" ${FILE} | sed -n "/www1/p" | wc -l)
        if [[ ${ALIAS_WWW1} == "0" ]]; then echo -e "${NOT_OK}You don't have set an alias - www1";
        # another option: 
        # ALIAS_WWW1=$(sed -n "/server_name/p" ${FILE} | sed -n "/www1/p")
        # if [[ -z ${ALIAS_WWW1} ]]; then echo -e "${NOT_OK}You don't have set an alias - www1";
        else
            # check the redirection of https
            REDIRECTION_WWW1=$(echo "${CURL_HTTPS,,}" | sed -n "/location/p" | cut -d "/" -f 3)
            # if $redirection_https has www1 then we should not have location in the response
            # but if we do not have www1 in the https redirection then in the location we should have www1, if we don't is not oK
            if [[ ${REDIRECTION_HTTPS} != *"www1"* && ${REDIRECTION_WWW1} != *"www1"* ]]; then 
                echo -e "${NOT_OK}You don't have set an alias - www1 as domain"; 
            fi 
        fi
    elif [[ ${IS_TEST} = *"test"* || ${IS_TEST} = *"stage"* ]]; then TEST=true; fi
    # we want to know if the file we are checking is test or not 
}

function check_www_nonwww_redirection() {
    if [[ ${REDIRECTION_HTTPS} = *"www."* ]]; then PLAIN_DOMAIN=$(echo ${REDIRECTION_HTTPS} | cut -d "." -f 2-)
    else PLAIN_DOMAIN=${REDIRECTION_HTTPS}; fi 
    # checking curl with non-www
    CURL_NON_WWW=$(curl --resolve ${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    CURL_WWW=$(curl --resolve www.${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://www.${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    #CURL_NON_WWW=$(curl -s -Ik https://"${PLAIN_DOMAIN}" --resolve ${PLAIN_DOMAIN}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    #CURL_WWW=$(curl -s -Ik https://"www.${PLAIN_DOMAIN}" --resolve www.${PLAIN_DOMAIN}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    # if there is not redirection to www-> nonwww or nonwww -> www then these two variables should not contain any information
    if [[ ! -z ${CURL_NON_WWW} && ! -z ${CURL_WWW} ]]; then echo -e "${NOT_OK}You have not set a redirection for www <--> non-www"; fi 
}

function check_basic_auth() {
    BASIC_AUTH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
    #BASIC_AUTH=$(curl -s -Ik https://"${REDIRECTION_HTTPS}" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
    if [[ "${BASIC_AUTH}" != *"restricted"* ]]; then
        echo -e "${NOT_OK}Please enable Basic auth"
        # we set this for when we are checking varnish 
        IS_BASIC_AUTH=false
    else IS_BASIC_AUTH=true; fi
}

# checking that the SSL certificate is up to date (valid)
function check_ssl_ww1_test_cert() {
    SSL_CERT=$(curl --insecure -v https://"${REDIRECTION_HTTPS}" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }' | sed -n "/SSL certificate verify/p")
    if [[ ${SSL_CERT} == *expired* ]]; then echo -e "${NOT_OK}SSL Certificate not ok -> install Letsencrypt"; fi
}

# check if in magento 2 is pointing to pub folder 
function check_pub_folder() {
    # get the config magento file
    PUB=$(sed -n "/root/p" ${FILE} | awk 'NR == 1' | cut -d "/" -f 6 | cut -d ";" -f 1)
    CONFIG_FILE=$(ls -lrt "/${ROOT_DIR}/app/etc/" | sed -n "/local.xml/p;/env.php/p")
    # we know that the file=env.php then is magento2 
    if [[ "${CONFIG_FILE}" = *"env.php"* ]]; then
        CONFIG_FILE="/${ROOT_DIR}/app/etc/env.php"
        MAGENTO_VERSION=2
        #IS MAGENTO 2 --> root directory should have pub and should be rwo media blocks in nginx. 
        if [[ "${PUB}" != "pub" ]]; then echo -e "${NOT_OK}Root folder does not contain /pub"; fi
        # check if media blocks are in nginx config -> is a warning if there are not to check if images are loading
        MEDIA_BLOCKS=$(sed -n "/media/p" ${FILE} | wc -l)
        if [[ "${MEDIA_BLOCKS}" != "2" ]]; then echo -e "     \e[38;5;198mWARNING: \e[0mYou should have 'location /media/' block for 80 and 443 - check if images are loading"; fi
    elif [[ "${CONFIG_FILE}" = *"local.xml"* ]]; then
        # we set the config file (in case there are local.xml.bak etc,...)
        CONFIG_FILE="/${ROOT_DIR}/app/etc/local.xml"
        MAGENTO_VERSION=1
        # should not have pub configued as in magento1 it does not exist
        if [[ "${PUB}" == "pub" ]]; then echo -e "${NOT_OK}Root folder contains /pub and should not because is Magento1"; fi
    fi
}

function check_production_mode() {
    MAGE_MODE=$(sed -n "/MAGE_MODE/p" ${CONFIG_FILE} | sed -n "/production/p")
    # we get the mage mode (we will only have something if it is magento2 and there is prodution in the ouput)
    if [[ "${MAGENTO_VERSION}" = 2 && -z "${MAGE_MODE}" ]]; then echo -e "${NOT_OK}Magento mode in ${CONFIG_FILE} is not set to Production"; fi
    # we can also check it with bin/magento -> but we need more lines of code
}

# check if the admin path is the same in vhost and env.php/local.xml
function check_admin_config() {
    # in env.pphp file the format is --> 'frontName' => 'admin_xk9j7q'
    # in local.xml the format is     --> <frontName><![CDATA[dashboard]]></frontName>
    ADMIN_PATH=$(sed -n "/frontName/p" ${CONFIG_FILE} | cut -d ">" -f 2 | cut -d "'" -f 2)
    if [[ "${MAGENTO_VERSION}" = 1 ]]; then ADMIN_PATH=$(sed -n "/frontName/p" ${CONFIG_FILE} | cut -d "[" -f 3 | cut -d "]" -f 1); fi
    if [[ ${ADMIN_PATH} ]]; then
        # check if in vhost there is this admin path
        IS_ADMIN=$(sed -n "/"${ADMIN_PATH}"/p" ${FILE} | sed -n "/location/p")
        # if the admin paht is not in the vhost -> not ok 
        if [[ -z ${IS_ADMIN} ]]; then echo -e "${NOT_OK}In ${CONFIG_FILE} admin path is ${ADMIN_PATH} and in vhost is not this one"; fi
    fi
}

function check_mysql_connection() {
    MYSQL_U=$(sed -n '/<connection>/,/<\/connection>/p' ${CONFIG_FILE} | sed -n "/username/p" | cut -d "[" -f 3 | cut -d "]" -f 1)
    MYSQL_P=$(sed -n '/<connection>/,/<\/connection>/p' ${CONFIG_FILE} | sed -n "/password/p" | cut -d "[" -f 3 | cut -d "]" -f 1)
    MYSQL_DB=$(sed -n '/<connection>/,/<\/connection>/p' ${CONFIG_FILE} | sed -n "/dbname/p" | cut -d "[" -f 3 | cut -d "]" -f 1)
    if [[ "${MAGENTO_VERSION}" = 2 ]]; then 
        MYSQL_U=$(sed -n "/'db' => \[/,/engine/p" ${CONFIG_FILE} | sed -n "/username/p" | cut -d ">" -f 2 | cut -d "'" -f 2)
        MYSQL_P=$(sed -n "/'db' => \[/,/engine/p" ${CONFIG_FILE} | sed -n "/password/p" | cut -d ">" -f 2 | cut -d "'" -f 2)
        MYSQL_DB=$(sed -n "/'db' => \[/,/engine/p" ${CONFIG_FILE} | sed -n "/dbname/p" | cut -d ">" -f 2 | cut -d "'" -f 2)
    fi  
    if [[ -z ${MYSQL_U} || -z ${MYSQL_P} || -z ${MYSQL_DB} ]]; then
        echo -e "${NOT_OK}Check the Database configuration in ${CONFIG_FILE}"; 
    else    
        MYSQL_CONNECT=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e exit)
        if [[ ${MYSQL_CONNECT} == "*ERROR*" ]]; then 
            if [[ ${MYSQL_CONNECT} == "*1044*" ]]; then echo -e "${NOT_OK}Database name does not exist";  
            elif [[ ${MYSQL_CONNECT} == "*1045*" ]]; then  echo -e "${NOT_OK}Credentials (username - password) are NOT OK";  
            else echo -e "${NOT_OK}MYSQL connection not working"; fi
        fi
    fi
}

# check varnish config 
function check_varnish() {
    #disable basic auth as when absic auth is enable we cannot check it
    if [[ $IS_BASIC_AUTH == true ]]; then
        # we comment the basic auth config in nginx config file
        sed -i "s/auth_basic_user_file/# auth_basic_user_file/g" ${FILE}
        AUTH_LINE=$(sed -n "/auth_basic/p" ${FILE} | grep -v "#" | grep -v "off")
        sed -i "s/${AUTH_LINE}/#${AUTH_LINE}/g" ${FILE}
        # we check ginx config is ok and then if it is we restart NGINX
        NGINX_OK=$(echo  $(nginx -t 2>&1) | sed -n "/successful/p")
        if [[ "${NGINX_OK}" = *"successful"* ]]; then
            /etc/init.d/nginx restart > /dev/null
            echo "     Restarting NGINX"
        else 
            echo "An error has occurred: cannot restart nginx. check nginx -t"
        fi
    fi
    sleep 1
    # we check if we received x-cache-age -> if varnish is working properly we should receive a number higher than 0 (the 2nd curl)
    #VARNISH=$(curl -s -Ik https://${REDIRECTION_HTTPS} --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1)
    VARNISH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s)
    #VARNISH=$(curl -s -Ik https://${REDIRECTION_HTTPS} --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/x-cache-age/p" | cut -d " " -f 2)
    VARNISH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/x-cache-age/p" | cut -d " " -f 2)
    #varnish=$(echo "${curl_https,,}" | grep "x-cache-age" | cut -d " " -f 2)
    if [[ ${VARNISH} == "0"* || -z ${VARNISH} ]]; 
        then echo -e "${NOT_OK}Varnish is not working"; 
    #    we should check thath the MGT extension of varnish is there --> if it is not working only.  
        if [[ "${MAGENTO_VERSION}" = 2 && ! -d "/${ROOT_DIR}/app/code/Mgt/Varnish" ]]; then echo -e "${NOT_OK}You don't have the Varnish extension of Mgt"; 
        elif [[ "${MAGENTO_VERSION}" = 1 && ! -d "/${ROOT_DIR}/app/code/community/Mgt/Varnish" ]]; then echo -e "${NOT_OK}You don't have the Varnish extension of Mgt"; fi    
    fi
    # enable basic auth AGAIN
    if [[ $IS_BASIC_AUTH == true ]]; then
        sed -i "s/# auth_basic_user_file/auth_basic_user_file/g" ${FILE}
        sed -i "s/#${AUTH_LINE}/${AUTH_LINE}/g" ${FILE}
        # now restart NGINX
        NGINX_OK=$(echo $(nginx -t 2>&1) | sed -n "/successful/p")
        if [[ "${NGINX_OK}" = *"successful"* ]]; then
            /etc/init.d/nginx restart > /dev/null
            echo "     Restarting NGINX"
        else 
            echo "An error has occurred: cannot restart nginx. check nginx -t"
        fi
    fi
}

# CHECK redis configuration (session and cache)
function check_redis() {
    # first we check if we have entries in redis: 
    command=$(redis-cli info | sed -n "/db/p" | grep -v "rdb")
    if [[ -z $command ]]; then 
        echo -e "${NOT_OK}Cache and Session Redis not working properly."
    else 
        # check in the env.php or local.xml the redis satabases (db1 and db2 for session & cache)
        DB_1=$(sed -n "/database/p" ${CONFIG_FILE} | head -n 1 | cut -d ">" -f 2)
        DB_2=$(sed -n "/database/p" ${CONFIG_FILE} | tail -n 1 | cut -d ">" -f 2)
        HAS_DB_1=false
        HAS_DB_2=false
        # we run the command redis-cli info and check how many databases we have there. FOr each one of them we make sure that the two db in the file are there 
        while read -r l; do
            DB=$(echo $l | cut -d ":" -f 1 | cut -c 3-)
            if [[ "${DB_1}" == *"${DB}"* ]]; then HAS_DB_1=true
            elif [[ "${DB_2}" == *"${DB}"* ]]; then HAS_DB_2=true; fi
            if [[ "${DB_1}" == *"${DB}"* && "${DB_2}" == *"${DB}"* ]]; then 
                # In this case the configuration for session and redis is the same and the databases numbers should be different (because it is localhost - single server)
                echo -e "${NOT_OK}In config file the db for redis is the same for session and cache. The dbs should be different"; 
            fi 
        done < <(redis-cli info | sed -n "/db/p" | grep -v "rdb")
        if [[ ${HAS_DB_1} == false && ${HAS_DB_2} == false ]]; then echo -e "${NOT_OK}Cache and Session Redis not working properly."
        elif [[ ${HAS_DB_1} == false || ${HAS_DB_2} == false ]]; then echo -e "${NOT_OK}Cache OR Session Redis is not working properly. Please check it "; fi
    fi
}

function check_cache_enabled() {
    # check if cahce is enabled
    cd /${ROOT_DIR}/
    if [[ "${MAGENTO_VERSION}" = 2 ]]; then
        #cache_res=$(bin/magento cache:status | cut -d ": "-f 2) 
        while read -r l; do
            CNAME=$(echo $l | cut -d ":" -f 1)
            CNUM=$(echo $l | cut -d ":" -f 2)
            if [[ "${CNAME}" = *"config_integration:"* || "${CNAME}" = *"config_integration_api"* || "${CNAME}" = *"target_rule"* || "${CNAME}" = *"config_webservice"* || "$cname" = *"translate"* ]]; then
                if [[ "${CNUM}" = *"0"* ]]; then echo -e "${NOT_OK}Cache ${CNAME} is ${CNUM} and should be 1"; fi
            fi
        done < <(bin/magento cache:status) 
    else 
        # we will save the data of the table "core_cache_option" in these two arrays
        CACHE_TYPES=()
        CACHE_VALUE=()
        j=0
        #Get all the cache types of the database 
        while read -r l; do CACHE_TYPES+=(${l}); done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT code FROM core_cache_option")
        # for each line check if ti si 0 and if it is then we fire error message saying that this cache type is disabled. 
        while read -r l; do
            if [[ ${l} = 0 ]]; then echo -e "${NOT_OK}Cache Type ${CACHE_TYPES[$j]} is set to 0"; fi
            j=$((i+1))
        done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_cache_option")
    fi
}

function global() {
    check_ownership
    check_pub_folder
    check_admin_config
    check_mysql_connection
    check_https_redirection
    check_alias
    check_www_nonwww_redirection
    check_basic_auth
    check_cache_enabled
}

# For each file in nginx (except back, only those ending with conf we check everything )
function check_nginx_files() {
    for FILE in /etc/nginx/sites-enabled/*.conf; do
        if [[ "${FILE}" = *"conf." ]]; then continue; fi
        printf "\n Checking nginx configuration file : ${FILE}:\n"
        global
        case ${INPUT} in
            ultimate)   
                check_varnish 
                check_redis
                ;;
            enterprise)    
                check_varnish 
                check_redis
                check_ssl_cert
                ;;
            *) ;;
        esac
    done
    if [[ ${INPUT} != "basic" && ${TEST} == false ]]; then echo -e "${NOT_OK}There should be test or stage environments"; fi
}

check_php_fpm_ports
check_nginx_files
printf "\nCompleted"
