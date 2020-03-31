#!/bin/bash
PLAN=$1
ENV=$2
if [[ -z "${PLAN}" || -z "${ENV}" ]]; then
    echo "Please input a plan (e.g. basic | premium | ultimate | enterprise) and an environment (e.g. prod | live )"
    exit 1
elif [[ ${PLAN} != "basic" && ${PLAN} != "premium" && ${PLAN} != "ultimate" && ${PLAN} != "enterprise" ]]; then
    echo "Please input VALID plan (e.g. basic | premium | ultimate | enterprise)"
    exit 1
elif [[ ${ENV} != "live" && ${ENV} != "prod" ]]; then
    echo "Please input VALID environment (e.g. prod | live )"
    exit 1
fi


#NOT_OK="     \e[38;5;198mNOT OK: \e[0m"
NOT_OK="     \e[41mNOT OK:\e[0m "
OK="     \e[42mOK:\e[0m "
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

MESS_PHP="   \033[1mPHP-fpm pools\033[0m\n"
MESS_PUB="   \033[1mRoot folder:\033[0m\n"
MESS_MAG_CONFIG="   \033[1mMagento configuration:\033[0m\n"
MESS_VARNISH="   \033[1mVarnish:\033[0m\n"
MESS_REDIS="   \033[1mRedis:\033[0m\n"
MESS_MYSQL="   \033[1mMysql:\033[0m\n"
MESS_SSL="   \033[1mSSL Certificate:\033[0m\n"
MESS_NGINX="   \033[1mNGINX configuration\033[0m\n"



# checks the pools configuration of php, takes user owner and port number of pools. 
#
# 1) check if PHP is version 5 or 7 because they have different directorues for pools: 
#    - For php version 5 = /etc/php5/fpm/pool.d/
#    - For php version 7.x = /etc/php/7.x/fpm/pool.d/
# 2) Check for each config file in pool.d/ directory except clp.conf and global.conf (set by default)
#   2.1) Save the port number and the user in different arrays corresponding that pool config file.
function check_php_fpm_ports {
    PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "-" -f 1 | cut -d "." -f 1-2)
    if [[ ${PHP_VERSION} == *"5."* ]]; then cd /etc/php5/fpm/pool.d/
    else cd /etc/php/${PHP_VERSION}/fpm/pool.d/; fi
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
                MESS_PHP+="${NOT_OK}$File ${FILE} uses port ${NGINX_PORT} (user ${USERS[$i]}) and root folder's owner is ${OWNER_FOLDER}\n"
                # echo -e "${NOT_OK}File ${FILE} uses port ${NGINX_PORT} (user ${USERS[$i]}) and root folder's owner is ${OWNER_FOLDER}"
            else
                MESS_PHP+="${OK}$File ${FILE}\n"
                chmod -R 775 "/${ROOT_DIR}/"
                #MESS_PHP+="${OK}$Directory ${ROOT_DIR} 775 permissions have been set\n"
                #resetting 775 permissions to make sure permissions are right. cannot check that all folders have 775. 
                # echo "     Setting 775 permissions for root folder ${ROOT_DIR}" 
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
            if [[ "${PROTOCOL}" != " https" ]]; then 
                MESS_NGINX+="${NOT_OK}URL ${SERVER_NAME} does not redirect to https\n"
                # echo -e "${NOT_OK}Url ${SERVER_NAME} does not redirect to https"; 
            else 
                MESS_NGINX+="${OK}HTTPS redirection ${SERVER_NAME}\n"
            fi
        fi
        PREV_HOST="${SERVER_NAME}"
    done < <(sed -n "/server_name/p" ${FILE} | head -n 2)
}


function check_www_nonwww_redirection() {
    if [[ ${REDIRECTION_HTTPS} = *"www"* ]]; then PLAIN_DOMAIN=$(echo ${REDIRECTION_HTTPS} | cut -d "." -f 2-)
    else PLAIN_DOMAIN=${REDIRECTION_HTTPS}; fi 
    # checking curl with non-www
    CURL_NON_WWW=$(curl --resolve ${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    CURL_WWW=$(curl --resolve www.${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://www.${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    #CURL_NON_WWW=$(curl -s -Ik https://"${PLAIN_DOMAIN}" --resolve ${PLAIN_DOMAIN}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    #CURL_WWW=$(curl -s -Ik https://"www.${PLAIN_DOMAIN}" --resolve www.${PLAIN_DOMAIN}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
    # if there is not redirection to www-> nonwww or nonwww -> www then these two variables should not contain any information
    if [[ ! -z ${CURL_NON_WWW} && ! -z ${CURL_WWW} ]]; then 
        MESS_NGINX+="${NOT_OK}${PLAIN_DOMAIN} - You have not set a redirection for www <--> non-www\n"
        # echo -e "${NOT_OK}You have not set a redirection for www <--> non-www"; 
    fi 
}

function check_basic_auth_alias_test() {
    BASIC_AUTH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
    #BASIC_AUTH=$(curl -s -Ik https://"${REDIRECTION_HTTPS}" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
    if [[ "${BASIC_AUTH}" != *"restricted"* ]]; then
        MESS_NGINX+="${NOT_OK}BASIC AUTH ${REDIRECTION_HTTPS} - Please enable Basic auth\n"
        # we set this for when we are checking varnish 
        IS_BASIC_AUTH=false
    else 
        MESS_NGINX+="${OK}BASIC AUTH ${REDIRECTION_HTTPS}\n"
        IS_BASIC_AUTH=true; 
    fi
}

function check_basic_auth_test() {
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} == *"test"* || ${IS_TEST} == *"stage"* ]]; then
        BASIC_AUTH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
        #BASIC_AUTH=$(curl -s -Ik https://"${REDIRECTION_HTTPS}" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
        if [[ "${BASIC_AUTH}" != *"restricted"* ]]; then
            MESS_NGINX+="${NOT_OK}BASIC AUTH ${REDIRECTION_HTTPS} - Please enable Basic auth\n"
            # we set this for when we are checking varnish 
            IS_BASIC_AUTH=false
        else 
            MESS_NGINX+="${OK}BASIC AUTH ${REDIRECTION_HTTPS}\n"
            IS_BASIC_AUTH=true; 
        fi
    fi
}

# checking that the SSL certificate is up to date (valid)
function check_ssl_ww1_test_cert() {
    SSL_CERT=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} --insecure -v https://"${REDIRECTION_HTTPS}:443" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }' | sed -n "/SSL certificate verify/p")
    if [[ ${SSL_CERT} == *expired* ]]; then 
        MESS_SSL+="${NOT_OK}${REDIRECTION_HTTPS} - SSL Certificate not ok -> Set Letsencrypt\n"
      #  echo -e "${NOT_OK}SSL Certificate not ok -> install Letsencrypt"; 
    elif [[ ${SSL_CERT} == *ok* ]]; then 
        MESS_SSL+="${OK}${REDIRECTION_HTTPS}\n"
    fi
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
        if [[ "${PUB}" != "pub" ]]; then 
            MESS_NGINX+="${NOT_OK}${REDIRECTION_HTTPS} - Root folder does not contain /pub\n"
            # echo -e "${NOT_OK}Root folder does not contain /pub"; 
        fi
        # check if media blocks are in nginx config -> is a warning if there are not to check if images are loading
        MEDIA_BLOCKS=$(sed -n "/media/p" ${FILE} | wc -l)
        if [[ "${MEDIA_BLOCKS}" != "2" ]]; then 
            #echo -e "     \e[38;5;198mWARNING: \e[0mYou should have 'location /media/' block for 80 and 443 - check if images are loading"; 
            MESS_NGINX+="     \e[38;5;198mWARNING: ${REDIRECTION_HTTPS} - You should have 'location /media/' block for 80 and 443 - check if images are loading\n"
        fi
    elif [[ "${CONFIG_FILE}" = *"local.xml"* ]]; then
        # we set the config file (in case there are local.xml.bak etc,...)
        CONFIG_FILE="/${ROOT_DIR}/app/etc/local.xml"
        MAGENTO_VERSION=1
        # should not have pub configued as in magento1 it does not exist
        if [[ "${PUB}" == "pub" ]]; then 
            MESS_NGINX+="${NOT_OK}${REDIRECTION_HTTPS} - Root folder contains /pub and should not because is Magento1\n"
            # echo -e "${NOT_OK}Root folder contains /pub and should not because is Magento1"; 
        fi
    fi
}

function check_production_mode() {
    MAGE_MODE=$(sed -n "/MAGE_MODE/p" ${CONFIG_FILE} | sed -n "/production/p")
    # we get the mage mode (we will only have something if it is magento2 and there is prodution in the ouput)
    if [[ "${MAGENTO_VERSION}" = 2 && -z "${MAGE_MODE}" ]]; then 
        MESS_MAG_CONFIG+="${NOT_OK}${REDIRECTION_HTTPS} - Magento mode in ${CONFIG_FILE} is not set to Production\n"
        #echo -e "${NOT_OK}Magento mode in ${CONFIG_FILE} is not set to Production"; 
    fi
    # we can also check it with bin/magento -> but we need more lines of code
}

# check if the admin path is the same in vhost and env.php/local.xml
function check_admin_config() {
    # in env.pphp file the format is --> 'frontName' => 'admin_xk9j7q'
    # in local.xml the format is     --> <frontName><![CDATA[dashboard]]></frontName>
    ADMIN_PATH=$(sed -n "/frontName/p" ${CONFIG_FILE} | cut -d ">" -f 2 | cut -d "'" -f 2)
    # using cli
    # ADMIN_PATH=$(/${ROOT_DIR}/bin/magento info:adminuri | sed -n '/URI/p' | cut -d "/" -f 2)
    if [[ "${MAGENTO_VERSION}" = 1 ]]; then ADMIN_PATH=$(sed -n "/frontName/p" ${CONFIG_FILE} | cut -d "[" -f 3 | cut -d "]" -f 1); fi
    if [[ ${ADMIN_PATH} ]]; then
        # check if in vhost there is this admin path
        IS_ADMIN=$(sed -n "/"${ADMIN_PATH}"/p" ${FILE} | sed -n "/location/p")
        # if the admin paht is not in the vhost -> not ok 
        if [[ -z ${IS_ADMIN} ]]; then 
            MESS_NGINX+="${NOT_OK}${REDIRECTION_HTTPS} - In ${CONFIG_FILE} admin path is ${ADMIN_PATH} and in vhost is not this one\n"
            # echo -e "${NOT_OK}In ${CONFIG_FILE} admin path is ${ADMIN_PATH} and in vhost is not this one"; 
        fi
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
        MESS_NGINX+="${NOT_OK}Check the Database configuration in ${CONFIG_FILE}\n"
        # echo -e "${NOT_OK}Check the Database configuration in ${CONFIG_FILE}"; 
    else    
        MYSQL_CONNECT=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e exit)
        if [[ ${MYSQL_CONNECT} == "*ERROR*" ]]; then 
            if [[ ${MYSQL_CONNECT} == "*1044*" ]]; then 
                MESS_NGINX+="${NOT_OK} MYSQL - Database name does not exist\n"
                # echo -e "${NOT_OK}Database name does not exist";  
            elif [[ ${MYSQL_CONNECT} == "*1045*" ]]; then  
                MESS_NGINX+="${NOT_OK}MYSQL - Credentials (username - password) are NOT OK\n"
                # echo -e "${NOT_OK}Credentials (username - password) are NOT OK";  
            else 
                MESS_MYSQL+="${NOT_OK}MYSQL - DB = ${MYSQL_DB}, USER = ${MYSQL_U} - connection not working\n"; 
                # echo -e "${NOT_OK}MYSQL connection not working"; 
            fi
        else
            MESS_MYSQL+="${OK} DB = ${MYSQL_DB}\n"; 
        fi
    fi
}

function check_secure_unsecure_url() {
    #web/unsecure/base_url
    # get the base_urls from the database:
    while read -r BASE_URL; do
        UNSECURE_URL=$(echo ${BASE_URL} | cut -d ":" -f 1)
        # we just  check that if there is something appart from www. then we consider it is an alias 
        if [[ -z "${UNSECURE_URL}" || "${UNSECURE_URL}" == "http" ]]; then 
            MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set https in unsecure url in the database \n"
        fi
    done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%/unsecure/base_url%'" | tail -n+1)
}

# as it is a new config we check that alias (www1) is right configured.
function check_alias() {
    # as test does not need alias -> we skip it 
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} != *"test"* &&  ${IS_TEST} != *"stage"* ]]; then
        # get the base_urls from the database:
        while read -r BASE_URL; do
            ALIAS=$(echo ${BASE_URL} | cut -d "/" -f 3 | cut -d "." -f 1)
            # we just  check that if there is something appart from www. then we consider it is an alias 
            if [[ -z "${ALIAS}" || "${ALIAS}" == "www" ]]; then 
                MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set an alias url in the Database "${MYSQL_DB}" (e.g. www1) \n"
            elif [[ "${ALIAS}" != "www1" ]]; then 
                MESS_NGINX+="         If ${ALIAS} is not an alias, please set an alias ${REDIRECTION_HTTPS} - You don't have set an alias (e.g. www1) \n"
            else
                MESS_NGINX+="${OK}${BASE_URL} - Alias ${BASE_URL}"
            fi
        done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%/secure/base_url%'" | tail -n+1)
    elif [[ ${IS_TEST} = *"test"* || ${IS_TEST} = *"stage"* ]]; then 
        TEST=true; 
    fi
    # we want to know if the file we are checking is test or not 
}

function check_live_domain() {
    # as test does not need alias -> we skip it 
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} != *"test"* ]]; then
        # get the base_urls from the database:
        while read -r BASE_URL; do
            IS_ALIAS=$(echo ${BASE_URL} | cut -d "/" -f 3 | cut -d "." -f 1)
            # we just  check that if there is something appart from www. then we consider it is an alias 
            if [[ ! (-z "${ALIAS}" || "${ALIAS}" == "www") ]]; then 
                MESS_NGINX+="${NOT_OK}${BASE_URL} - You should set live domain instead of an alias.\n"
            else
                MESS_NGINX+="${OK}${BASE_URL} - Live domain"
            fi
        done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%/secure/base_url%'" | tail -n+2)
    elif [[ ${IS_TEST} = *"test"* || ${IS_TEST} = *"stage"* ]]; then 
        TEST=true; 
    fi
    # we want to know if the file we are checking is test or not 
}

function check_admin_user() {
    USER=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT username FROM admin_user WHERE username LIKE '%admin%'"| tail -n+1)
    if [[ -z ${USER} ]]; then
        MESS_MAG_CONFIG+="${NOT_OK}${BASE_URL} - There isn't any "admin" user for the backend\n"
    fi
}

function check_mgt_user() {
    USER=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT username FROM admin_user WHERE username LIKE '%mgt%'"| tail -n+1)
    if [[ -z ${USER} ]]; then
        MESS_MAG_CONFIG+="${NOT_OK}${BASE_URL} - There isn't any "mgtcommerce" user for the backend\n"
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
        if [[ "${NGINX_OK}" = *"successful"* ]]; then /etc/init.d/nginx restart > /dev/null
        else  
            MESS_NGINX+="         \e[41mAn error has occurred: cannot restart nginx. Check 'nginx -t'\e[0m\n"
            # echo -e "         \e[41mAn error has occurred: cannot restart nginx. Check 'nginx -t'\e[0m"
        fi
    fi
    sleep 1
    # we check if we received x-cache-age -> if varnish is working properly we should receive a number higher than 0 (the 2nd curl)
    #VARNISH=$(curl -s -Ik https://${REDIRECTION_HTTPS} --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1)
    VARNISH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s)
    #VARNISH=$(curl -s -Ik https://${REDIRECTION_HTTPS} --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/x-cache-age/p" | cut -d " " -f 2)
    VARNISH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/x-cache-age/p" | cut -d " " -f 2)
    #varnish=$(echo "${curl_https,,}" | grep "x-cache-age" | cut -d " " -f 2)
    if [[ ${VARNISH} == "0"* || -z ${VARNISH} ]]; then 
        MESS_VARNISH+="${NOT_OK}${REDIRECTION_HTTPS} - Varnish is not working\n"; 
        # echo -e "${NOT_OK}Varnish is not working"; 
    #    we should check thath the MGT extension of varnish is there --> if it is not working only.  
        if [[ ("${MAGENTO_VERSION}" = 2 && ! -d "/${ROOT_DIR}/app/code/Mgt/Varnish") || 
              ("${MAGENTO_VERSION}" = 1 && ! -d "/${ROOT_DIR}/app/code/community/Mgt/Varnish") ]]; then 
            MESS_VARNISH+="         \e[41m * \e[0m /${ROOT_DIR} - You don't have the Varnish extension of Mgt\n"; 
            # echo -e "${NOT_OK}You don't have the Varnish extension of Mgt"
        fi
        # If Varnish is NOT working check if in the database Varnish is enabled
        MYSQL_VARNISH=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%mgt_varnish%is_enabled%'")
        if [[ "${MYSQL_VARNISH}" = "0" ]]; then 
            MESS_VARNISH+="         \e[41m * \e[0m Varnish is not enabled in the backend (database ${MYSQL_DB})\n"
        fi
            # echo -e "${NOT_OK}Varnish is not enabled in the backend"; fi
        # cehck if it is #pass commented
        VARNISH_CONF=$(sed -n '/vcl_recv/,/return/p' /etc/varnish/default.vcl | sed -n '/return/p' | sed -n '/#/p')
        if [[ -z "${VARNISH_CONF}" ]]; then 
            MESS_VARNISH+="         \e[41m * \e[0m Please comment 'return (pass);' in '/etc/varnish/default.vcl'\n"
            # echo -e "${NOT_OK}Please comment 'return (pass);' in '/etc/varnish/default.vcl'"; 
        fi
    else 
        MESS_VARNISH+="${OK}${REDIRECTION_HTTPS}\n"
        # echo -e "${OK}Varnish"; 
    fi
    # enable basic auth AGAIN
    if [[ $IS_BASIC_AUTH == true ]]; then
        sed -i "s/# auth_basic_user_file/auth_basic_user_file/g" ${FILE}
        sed -i "s/#${AUTH_LINE}/${AUTH_LINE}/g" ${FILE}
        # now restart NGINX
        NGINX_OK=$(echo $(nginx -t 2>&1) | sed -n "/successful/p")
        if [[ "${NGINX_OK}" = *"successful"* ]]; then /etc/init.d/nginx restart > /dev/null
        else  
            MESS_NGINX+="         \e[41mAn error has occurred: cannot restart nginx. Check 'nginx -t'\e[0m\n"
            # echo -e "         \e[41mAn error has occurred: cannot restart nginx. Check 'nginx -t'\e[0m"
        fi
    fi
}

# CHECK redis configuration (session and cache)
function check_redis() {
    DB_CACHE=$(sed -n '/<cache>/,/<\/cache>/p' ${CONFIG_FILE} | sed -n "/database/p")
    DB_SESSION=$(sed -n '/<redis_session>/,/<\/redis_session>/p' ${CONFIG_FILE} | sed -n "/database/p" )
    if [[ "${MAGENTO_VERSION}" = 2 ]]; then
        DB_SESSION=$(sed -n "/'session' =>/,/database/p" ${CONFIG_FILE} | sed -n "/database/p")
        DB_CACHE=$(sed -n "/'cache' =>/,/database/p" ${CONFIG_FILE} | sed -n "/database/p")
    fi
    if [[ -z ${DB_SESSION} ]]; then MESS_REDIS+="${NOT_OK}${REDIRECTION_HTTPS} - Block Redis SESSION is not set in ${CONFIG_FILE}\n"; fi 
    if [[ -z ${DB_CACHE} ]]; then MESS_REDIS+="${NOT_OK}${REDIRECTION_HTTPS} - Block Redis CACHE is not set in ${CONFIG_FILE}\n"; fi 
    HAS_DB_CACHE=false
    HAS_DB_SESSION=false
    # first we check if we have entries in redis: 
    # we run the command redis-cli info and check how many databases we have there. FOr each one of them we make sure that the two db in the file are there 
    if [[ ${DB_SESSION} && ${HAS_DB_CACHE} ]]; then 
        while read -r l; do
            DB=$(echo $l | cut -d ":" -f 1 | cut -c 3-)
            if [[ "${DB_CACHE}" == *"${DB}"* ]]; then HAS_DB_CACHE=true
            elif [[ "${DB_SESSION}" == *"${DB}"* ]]; then HAS_DB_SESSION=true; fi
            if [[ "${DB_CACHE}" == *"${DB}"* && "${DB_SESSION}" == *"${DB}"* ]]; then 
                # In this case the configuration for session and redis is the same and the databases numbers should be different (because it is localhost - single server)
                MESS_MAG_CONFIG+="${NOT_OK}In ${CONFIG_FILE} db for redis is the same for session and cache. The dbs should be different\n"
                # echo -e "${NOT_OK}In config file the db for redis is the same for session and cache. The dbs should be different"; 
            fi 
        done < <(redis-cli info | sed -n "/Keyspace/,//p" | tail -n+2)
    fi
    if [[ ${HAS_DB_SESSION} == true && ${HAS_DB_CACHE} == true ]]; then MESS_REDIS+="${OK}${REDIRECTION_HTTPS}\n"; fi
    if [[ ${HAS_DB_SESSION} == false ]]; then MESS_REDIS+="${NOT_OK}${REDIRECTION_HTTPS} - Database for Redis SESSION is not working\n"; fi
        # echo -e "${NOT_OK}Cache and Session Redis not working properly."
    if [[ ${HAS_DB_CACHE} == false ]]; then MESS_REDIS+="${NOT_OK}${REDIRECTION_HTTPS} - Database for Redis CACHE is not working\n"; fi
        # echo -e "${NOT_OK}Cache OR Session Redis is not working properly. Please check it "
}

function check_cache_enabled() {
    # check if cahce is enabled
    cd /${ROOT_DIR}/
    ALL_CACHE_ENABLED=true
    if [[ "${MAGENTO_VERSION}" = 2 ]]; then
        #cache_res=$(bin/magento cache:status | cut -d ": "-f 2) 
        while read -r l; do
            CNAME=$(echo $l | cut -d ":" -f 1)
            CNUM=$(echo $l | cut -d ":" -f 2)
            if [[ "${CNAME}" = *"config_integration:"* || "${CNAME}" = *"config_integration_api"* || "${CNAME}" = *"target_rule"* || "${CNAME}" = *"config_webservice"* || "$cname" = *"translate"* ]]; then
                if [[ "${CNUM}" = *"0"* ]]; then 
                    MESS_MAG_CONFIG+="${NOT_OK}Cache ${CNAME} is ${CNUM} and should be 1\n"
                    ALL_CACHE_ENABLED=false
                    # echo -e "${NOT_OK}Cache ${CNAME} is ${CNUM} and should be 1"
                fi
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
            if [[ ${l} = 0 ]]; then 
                MESS_MAG_CONFIG+="${NOT_OK}Cache Type ${CACHE_TYPES[$j]} is set to 0\n"
                # echo -e "${NOT_OK}Cache Type ${CACHE_TYPES[$j]} is set to 0"
                ALL_CACHE_ENABLED=false
            fi
            j=$((i+1))
        done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_cache_option")
    fi
    if [[ "${ALL_CACHE_ENABLED}" = true ]]; then 
        MESS_MAG_CONFIG+="${OK}CACHES ${REDIRECTION_HTTPS} enabled\n"; 
    fi
}

function global() {
    check_ownership
    check_pub_folder
    check_admin_config
    check_mysql_connection
    check_https_redirection
    check_secure_unsecure_url
    check_www_nonwww_redirection
    check_secure_unsecure_url
    if [[ "${ENV}" = prod ]]; then 
        check_alias;
        check_basic_auth; 
        check_admin_user;
    else
        check_live_domain;
        check_basic_auth_test;
        check_mgt_user;
    fi
    check_cache_enabled
}

# For each file in nginx (except back, only those ending with conf we check everything )
function check_nginx_files() {
    for FILE in /etc/nginx/sites-enabled/*.conf; do
        if [[ "${FILE}" = *"conf." ]]; then continue; fi
        MESS_NGINX+="\n   * \033[1mNGINX file ${FILE}\033[0m\n"
        # printf "\n Checking nginx configuration file : ${FILE}:\n"
        global
        case ${PLAN} in
            ultimate)   
                check_varnish 
                check_redis
                ;;
            enterprise)    
                check_varnish 
                check_redis
                check_ssl_ww1_test_cert
                ;;
            *) ;;
        esac
    done
    if [[ ${INPUT} != "basic" && ${TEST} == false ]]; then 
        echo -e "${NOT_OK}There should be test or stage environments"; 
    fi
}

check_php_fpm_ports
check_nginx_files


# DISPLAY MESSAGES: 
echo -e "${MESS_PHP}"
echo -e "${MESS_NGINX}"
echo -e "${MESS_MAG_CONFIG}"
echo -e "${MESS_MYSQL}"
echo -e "${MESS_VARNISH}"
echo -e "${MESS_REDIS}"
echo -e "${MESS_SSL}"


printf "\nCompleted\n"