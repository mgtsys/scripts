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
BASIC_AUTH_USR=""

PORTS=()
USERS=()
DBS_CONNECTIONS=()
DBS=()
CHECKED_DB=()
SERVER_NAMES=()
PERMISSION_SET_DIR=()

MAGENTO_VERSION=1

TEST=false
IS_BASIC_AUTH=true
IS_MYSQL_WORKING=false
MAG_INSTALLATION=true
HASDB=false

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
    ROOT_DIR=$(sed -n "/root/p" ${FILE} | awk 'NR == 1' | cut -d "/" -f 2- | cut -d ";" -f 1)
    APP_ETC=$(echo ${ROOT_DIR} | sed -e 's/\/pub//')
    if [[ ! -d "/${APP_ETC}/app/etc" ]]; then 
        MAG_INSTALLATION=false; 
        MESS_NGINX+="     Skipping file ${FILE} - not a magento installation\n"
        return 1
    fi

    # checks in the array which user uses that port (taken form php pool) and checks which user is the owner of the root directory  
    # If config is oK then resets permissions 775 just in case. 
    if [ -z "${PORTS}" ]; then
        MESS_PHP+="${NOT_OK}There are no pools configured\n"
    else 
        for i in "${!PORTS[@]}"; do
            if [[ "${PORTS[$i]}" = "${NGINX_PORT}" ]]; then
                OWNER_FOLDER=$(ls -lrt "/${ROOT_DIR}" | awk 'NR == 2' | cut -d " " -f 4)
                if [[ "${OWNER_FOLDER}" != "${USERS[$i]}" ]]; then
                    MESS_PHP+="${NOT_OK}$File ${FILE} uses port ${NGINX_PORT} (user ${USERS[$i]}) and root folder's owner is ${OWNER_FOLDER}\n"
                else
                    SET_PERM=false
                    for i in "${!PERMISSION_SET_DIR[@]}"; do
                        if [[ "${ROOT_DIR}" == "${PERMISSION_SET_DIR[$i]}" ]]; then
                            SET_PERM=true
                        fi
                    done
                    if [[ ${SET_PERM} == false ]]; then 
                        MESS_PHP+="${OK}$File ${FILE}\n"
                        chmod -R 775 "/${ROOT_DIR}/"
                        PERMISSION_SET_DIR+=(${ROOT_DIR})
                    fi
                fi
            fi
        done
    fi
}

# check if in magento 2 is pointing to pub folder 
function check_pub_folder() {
    # get the config magento file
    #PUB=$(sed -n "/root/p" ${FILE} | awk 'NR == 1' | cut -d "/" -f 6 | cut -d ";" -f 1)
    CONFIG_FILE=$(ls -lrt "/${APP_ETC}/app/etc/" | sed -n "/local.xml/p;/env.php/p")
    # we know that the file=env.php then is magento2 
    if [[ "${CONFIG_FILE}" = *"env.php"* ]]; then
        CONFIG_FILE="/${APP_ETC}/app/etc/env.php"
        MAGENTO_VERSION=2
        #IS MAGENTO 2 --> root directory should have pub and should be rwo media blocks in nginx. 
        if [[ ${ROOT_DIR} != *pub* ]]; then 
            MESS_NGINX+="${NOT_OK}${FILE} - Root folder does not contain /pub\n"
        fi
        # check if media blocks are in nginx config -> is a warning if there are not to check if images are loading
        MEDIA_BLOCKS=$(sed -n "/location/p" ${FILE} | sed -n "/\/media/p" | wc -l)
        if [[ "${MEDIA_BLOCKS}" == "0" ]]; then 
            MESS_NGINX+="     \e[38;5;198mWARNING: \e[0m${FILE} - You should have 'location /media/' block for 80 and 443 - check if images are loading\n"
        fi
    elif [[ "${CONFIG_FILE}" = *"local.xml"* ]]; then
        # we set the config file (in case there are local.xml.bak etc,...)
        CONFIG_FILE="/${APP_ETC}/app/etc/local.xml"
        MAGENTO_VERSION=1
        # should not have pub configued as in magento1 it does not exist
        if [[ "${PUB}" == "pub" ]]; then 
            MESS_NGINX+="${NOT_OK}${FILE} - Root folder contains /pub and should not because is Magento1\n"
        fi
    fi
}

# checks if the https redirection (from http -> https) is working. 
function check_https_redirection() {
    # we take the server names from the nginx config file (as we can have more than one www1, www or without www)
    SERVER_NAMES=()
    while read -r LINE; do
        # we get one of the server name
        SERVER_NAME=$(echo ${LINE} | cut -d " " -f 2 | cut -d ";" -f 1)
        # we make sure we have not checked this server name before 
        if [[ $PREV_HOST != *"${SERVER_NAME}"* ]]; then
            SERVER_NAMES+=(${SERVER_NAME})
            # we get the response of curl with http
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
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${SERVER_NAME} == *www* ]]; then
        if [[ ${REDIRECTION_HTTPS} = *"www"* ]]; then PLAIN_DOMAIN=$(echo ${REDIRECTION_HTTPS} | cut -d "." -f 2-)
        else PLAIN_DOMAIN=${REDIRECTION_HTTPS}; fi 
        # checking curl with non-www
        CURL_NON_WWW=$(curl --resolve ${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
        CURL_WWW=$(curl --resolve www.${PLAIN_DOMAIN}:443:${PRIVATE_IP} https://www.${PLAIN_DOMAIN}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" | cut -d "/" -f 3)
        # if there is not redirection to www-> nonwww or nonwww -> www then these two variables should not contain any information
        if [[ -z ${CURL_NON_WWW} && -z ${CURL_WWW} ]]; then 
            MESS_NGINX+="${NOT_OK}${PLAIN_DOMAIN} - You have not set a redirection for www <--> non-www\n"
        elif [[ ! -z ${CURL_NON_WWW} ]]; then REDIRECTION_HTTPS=${CURL_NON_WWW}
        else REDIRECTION_HTTPS=${CURL_WWW}
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
    else   
        HASDB=false 
        for i in "${!DBS_CONNECTIONS[@]}"; do
            if [[ "${MYSQL_DB}" = "${DBS_CONNECTIONS[$i]}" ]]; then
                HASDB=true
            fi
        done
        if [[ ${HASDB} = false ]]; then
            MYSQL_CONNECT=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e exit)
            if [[ ${MYSQL_CONNECT} == "*ERROR*" ]]; then 
                if [[ ${MYSQL_CONNECT} == "*1044*" ]]; then MESS_NGINX+="${NOT_OK} MYSQL - Database name does not exist\n"
                elif [[ ${MYSQL_CONNECT} == "*1045*" ]]; then MESS_NGINX+="${NOT_OK}MYSQL - Credentials (username - password) are NOT OK\n"
                else MESS_MYSQL+="${NOT_OK}MYSQL - DB = ${MYSQL_DB}, USER = ${MYSQL_U} - connection not working\n"; fi
            else
                MESS_MYSQL+="${OK} DB = ${MYSQL_DB}\n"; 
            fi
            DBS_CONNECTIONS+=(${MYSQL_DB})
        fi
    fi
}

function check_secure_unsecure_url() {
    #web/unsecure/base_url
    # get the base_urls from the database:
    while read -r BASE_URL; do
        UNSECURE_URL=$(echo ${BASE_URL} | cut -d ":" -f 1)
        # we just  check that if there is something appart from www. then we consider it is an alias 
        if [[ ${UNSECURE_URL} == *${SERVER_NAME}* ]]; then
            if [[ -z "${UNSECURE_URL}" || "${UNSECURE_URL}" == "http" ]]; then 
                MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set https in unsecure url in the database \n"
            fi
        fi
    done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%/unsecure/base_url%'" | tail -n+1)
}


function check_basic_auth_alias_test() {
    BASIC_AUTH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
    if [[ "${BASIC_AUTH}" != *"restricted"* ]]; then
        MESS_NGINX+="${NOT_OK}BASIC AUTH ${REDIRECTION_HTTPS} - Please enable Basic auth\n"
        # we set this for when we are checking varnish 
    else 
        MESS_NGINX+="${OK}BASIC AUTH ${REDIRECTION_HTTPS}\n"
        get_basic_auth_credentials
    fi
}

function check_basic_auth_test() {
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} == *"test"* || ${IS_TEST} == *"stage"* ]]; then
        BASIC_AUTH=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s 2>&1 | 
                     sed -e 's/\(.*\)/\L\1/' | sed -n "/restricted/p" | cut -d '"' -f 2)
        if [[ "${BASIC_AUTH}" != *"restricted"* ]]; then
            MESS_NGINX+="${NOT_OK}BASIC AUTH ${REDIRECTION_HTTPS} - Please enable Basic auth\n"
            # we set this for when we are checking varnish 
        else 
            MESS_NGINX+="${OK}BASIC AUTH ${REDIRECTION_HTTPS}\n"
            get_basic_auth_credentials
        fi
    fi
}

# checking that the SSL certificate is up to date (valid)
function check_ssl_ww1_test_cert() {
    SSL_CERT=$(curl --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} --insecure -v https://"${REDIRECTION_HTTPS}:443" --resolve ${REDIRECTION_HTTPS}:${PRIVATE_IP} 2>&1 | 
               awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }' | 
               sed -n "/SSL certificate verify/p")
    if [[ ${SSL_CERT} == *expired* ]]; then 
        MESS_SSL+="${NOT_OK}${REDIRECTION_HTTPS} - SSL Certificate not ok -> Set Letsencrypt\n"
    elif [[ ${SSL_CERT} == *ok* ]]; then 
        MESS_SSL+="${OK}${REDIRECTION_HTTPS}\n"
    fi
}

function check_production_mode() {
    MAGE_MODE=$(sed -n "/MAGE_MODE/p" ${CONFIG_FILE} | sed -n "/production/p")
    # we get the mage mode (we will only have something if it is magento2 and there is prodution in the ouput)
    if [[ "${MAGENTO_VERSION}" = 2 && -z "${MAGE_MODE}" ]]; then 
        MESS_MAG_CONFIG+="${NOT_OK}${REDIRECTION_HTTPS} - Magento mode in ${CONFIG_FILE} is not set to Production\n"
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
        IS_ADMIN=$(sed -n "/${ADMIN_PATH}/p" ${FILE} | sed -n "/location/p")
        # if the admin paht is not in the vhost -> not ok 
        if [[ -z ${IS_ADMIN} ]]; then 
            MESS_NGINX+="${NOT_OK}${REDIRECTION_HTTPS} - In ${CONFIG_FILE} admin path is ${ADMIN_PATH} and in vhost is not this one\n"
            # echo -e "${NOT_OK}In ${CONFIG_FILE} admin path is ${ADMIN_PATH} and in vhost is not this one"; 
        fi
    fi
}

# as it is a new config we check that alias (www1) is right configured.
function check_alias() {
    # as test does not need alias -> we skip it 
    IS_TEST=$(echo "${FILE}" | cut -d "." -f 1)
    if [[ ${IS_TEST} != *"test"* &&  ${IS_TEST} != *"stage"* ]]; then
        # get the base_urls from the database:
        while read -r BASE_URL; do
            if [[ ${#SERVER_NAMES[@]} == 2 && ( ${BASE_URL} == *${SERVER_NAMES[0]}* || ${BASE_URL} == *${SERVER_NAMES[1]}* ) ]] || [[ ${BASE_URL} == *${SERVER_NAME}* ]]; then 
                ALIAS=$(echo ${BASE_URL} | cut -d "/" -f 3 | cut -d "." -f 1)
                if [[ ${#SERVER_NAMES[@]} == 2 ]]; then 
                    PRE_1=$(echo ${SERVER_NAMES[0]} | cut -d "." -f 1) 
                    PRE_2=$(echo ${SERVER_NAMES[1]} | cut -d "." -f 1) 
                    if [[ ${PRE_1} == *${PRE_2}* && ${PRE_1} == *1* && ${PRE_1} == *${ALIAS}* ]] ||
                    [[ ${PRE_2} == *${PRE_1}* && ${PRE_2} == *1* && ${PRE_2} == *${ALIAS}* ]]; then  
                    # then normally if pre1 contains pre2 -> pre1 is an alias (www www1)
                        MESS_NGINX+="${OK}${BASE_URL} - Alias ${ALIAS}\n"
                    else 
                        MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set an alias url in the Database "${MYSQL_DB}" (e.g. www1) \n"
                    fi
                elif [[ -z "${ALIAS}" || "${ALIAS}" == "www" ]]; then 
                    MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set an alias url in the Database "${MYSQL_DB}" (e.g. www1) \n"
                fi 
                # we just  check that if there is something appart from www. then we consider it is an alias 
                #if [[ -z "${ALIAS}" || "${ALIAS}" == "www" ]]; then 
                #    MESS_NGINX+="${NOT_OK}${BASE_URL} - You don't have set an alias url in the Database "${MYSQL_DB}" (e.g. www1) \n"
                #elif [[ "${ALIAS}" != "1" ]]; then 
                #    MESS_NGINX+="         If ${ALIAS} is not an alias, please set an alias ${REDIRECTION_HTTPS} - You don't have set an alias (e.g. www1) \n"
                #else
                #    MESS_NGINX+="${OK}${BASE_URL} - Alias ${BASE_URL}\n"
                #fi
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
            if [[ ${BASE_URL} == *${SERVER_NAME}* ]]; then
                IS_ALIAS=$(echo ${BASE_URL} | cut -d "/" -f 3 | cut -d "." -f 1)
                # we just  check that if there is something appart from www. then we consider it is an alias 
                if [[ ! (-z "${ALIAS}" || "${ALIAS}" == "www") ]]; then 
                    MESS_NGINX+="${NOT_OK}${BASE_URL} - You should set live domain instead of an alias.\n"
                else
                    MESS_NGINX+="${OK}${BASE_URL} - Live domain"
                fi
            fi
        done < <(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%/secure/base_url%'" | tail -n+2)
    elif [[ ${IS_TEST} = *"test"* || ${IS_TEST} = *"stage"* ]]; then 
        TEST=true; 
    fi
    # we want to know if the file we are checking is test or not 
}

function get_basic_auth_credentials() {
    BASIC_AUTH_CREDENTIALS_FILE=$(sed -n '/auth_basic_user_file/p' ${FILE} | cut -d "/" -f 2- | cut -d ";" -f 1)
    BASIC_AUTH_USR=$(cat /${BASIC_AUTH_CREDENTIALS_FILE} | cut -d ":" -f 1)
}

function check_admin_user() {
    HASDB=false 
    for i in "${!DBS[@]}"; do
        if [[ "${MYSQL_DB}" = "${DBS[$i]}" ]]; then HASDB=true; fi
    done
    if [[ ${HASDB} = false ]]; then
        USER=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT username FROM admin_user WHERE username LIKE '%admin%'" | tail -n+1)
        if [[ -z ${USER} ]]; then 
            MESS_MAG_CONFIG+="${NOT_OK}${REDIRECTION_HTTPS} - DB:${MYSQL_DB} - There isn't any admin user for the backend\n"
        else 
            MESS_MAG_CONFIG+="${OK}${REDIRECTION_HTTPS} - DB:${MYSQL_DB} - User admin for backend\n"; 
        fi
        DBS+=(${MYSQL_DB})
    fi
}

function check_mgt_user() {
    HASDB=false 
    for i in "${!DBS[@]}"; do
        if [[ "${MYSQL_DB}" = "${DBS[$i]}" ]]; then HASDB=true; fi
    done
    if [[ ${HASDB} = false ]]; then
        USER=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT username FROM admin_user WHERE username LIKE '%mgt%'"| tail -n+1)
        if [[ -z ${USER} ]]; then MESS_MAG_CONFIG+="${NOT_OK}${REDIRECTION_HTTPS} - There isn't any mgtcommerce user for the backend\n"; fi    
        DBS+=(${MYSQL_DB})
    fi
}

# check varnish config 
function check_varnish() {
    # we check if we received x-cache-age -> if varnish is working properly we should receive a number higher than 0 (the 2nd curl)
    TEST_VARNISH=$(curl -u ${BASIC_AUTH_USR}:'!'${BASIC_AUTH_USR}123'!' -i -H 'Accept:application/json' --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s | sed -e 's/\(.*\)/\L\1/' | sed -n "/location/p" )
    if [[ ! -z ${TEST_VARNISH} ]]; then 
        REDIRECTION_HTTPS=$(echo ${TEST_VARNISH} | cut -d "/" -f 3)
    fi 
    CHECKOUT=$(curl -u ${BASIC_AUTH_USR}:'!'${BASIC_AUTH_USR}123'!' -i -H 'Accept:application/json' --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}/checkout/:443 -Ik -s)
    VARNISH=$(curl -u ${BASIC_AUTH_USR}:'!'${BASIC_AUTH_USR}123'!' -i -H 'Accept:application/json' --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s)
    sleep 2
    VARNISH=$(curl -u ${BASIC_AUTH_USR}:'!'${BASIC_AUTH_USR}123'!' -i -H 'Accept:application/json' --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}:443 -Ik -s | sed -e 's/\(.*\)/\L\1/' | sed -n "/x-cache-age/p" | cut -d " " -f 2)
    if [[ ${VARNISH} == "0"* || -z ${VARNISH} ]]; then 
        MESS_VARNISH+="${NOT_OK}${REDIRECTION_HTTPS} - Varnish is not working\n"; 
    #    we should check thath the MGT extension of varnish is there --> if it is not working only.  
        if [[ ("${MAGENTO_VERSION}" = 2 && ! -d "/${APP_ETC}/app/code/Mgt/Varnish") || 
              ("${MAGENTO_VERSION}" = 1 && ! -d "/${APP_ETC}/app/code/community/Mgt/Varnish") ]]; then 
            MESS_VARNISH+="         \e[41m * \e[0m /${${APP_ETC}} - You don't have the Varnish extension of Mgt\n"; 
        fi
        # If Varnish is NOT working check if in the database Varnish is enabled
        MYSQL_VARNISH=$(mysql -s -h"localhost" -u"${MYSQL_U}" -p"${MYSQL_P}" ${MYSQL_DB} -e "SELECT value FROM core_config_data WHERE path LIKE '%mgt_varnish%is_enabled%'")
        if [[ "${MYSQL_VARNISH}" = "0" ]]; then MESS_VARNISH+="         \e[41m * \e[0m Varnish is not enabled in the backend (database ${MYSQL_DB})\n"; fi
        # cehck if it is #pass commented
        VARNISH_CONF=$(sed -n '/vcl_recv/,/return/p' /etc/varnish/default.vcl | sed -n '/return/p' | sed -n '/#/p')
        if [[ -z "${VARNISH_CONF}" ]]; then MESS_VARNISH+="         \e[41m * \e[0m Please comment 'return (pass);' in '/etc/varnish/default.vcl'\n"; fi
    else 
        MESS_VARNISH+="${OK}${REDIRECTION_HTTPS}\n"
    fi
}

# CHECK redis configuration (session and cache)
function check_redis() {
    if [[ ${HASDB} = false ]]; then
        # we go to checkout so that redis is generating db
        CHECKOUT=$(curl -u ${BASIC_AUTH_USR}:'!'${BASIC_AUTH_USR}123'!' -i -H 'Accept:application/json' --resolve ${REDIRECTION_HTTPS}:443:${PRIVATE_IP} https://${REDIRECTION_HTTPS}/checkout/:443 -Ik -s)
        # get the db of cache and session inide the env.php / local.xml 
        DB_CACHE=$(sed -n '/<cache>/,/<\/cache>/p' ${CONFIG_FILE} | sed -n "/database/p")
        DB_SESSION=$(sed -n '/<redis_session>/,/<\/redis_session>/p' ${CONFIG_FILE} | sed -n "/database/p" )
        if [[ "${MAGENTO_VERSION}" = 2 ]]; then
            DB_SESSION=$(sed -n "/'session' =>/,/database/p" ${CONFIG_FILE} | sed -n "/database/p")
            DB_CACHE=$(sed -n "/'cache' =>/,/database/p" ${CONFIG_FILE} | sed -n "/database/p")
        fi
        # check if the var is empy (which means the vblock is not there - so redis is not configured)
        if [[ -z ${DB_SESSION} ]]; then MESS_REDIS+="${NOT_OK}${CONFIG_FILE} - Block Redis SESSION is not set in ${CONFIG_FILE}\n"; fi 
        if [[ -z ${DB_CACHE} ]]; then MESS_REDIS+="${NOT_OK}${CONFIG_FILE} - Block Redis CACHE is not set in ${CONFIG_FILE}\n"; fi 
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
                    MESS_MAG_CONFIG+="${NOT_OK}In ${CONFIG_FILE} db for redis is the same for session and cache. The dbs should be different\n"
                fi 
            done < <(redis-cli info | sed -n "/Keyspace/,//p" | tail -n+2)
            if [[ ${HAS_DB_SESSION} == true && ${HAS_DB_CACHE} == true ]]; then MESS_REDIS+="${OK}${CONFIG_FILE}\n"; fi
            if [[ ${HAS_DB_SESSION} == false ]]; then MESS_REDIS+="${NOT_OK}${CONFIG_FILE} - Database for Redis SESSION is not working\n"; fi
            if [[ ${HAS_DB_CACHE} == false ]]; then MESS_REDIS+="${NOT_OK}${CONFIG_FILE} - Database for Redis CACHE is not working\n"; fi
        fi
    fi

}

function check_cache_enabled() {
    # check if cahce is enabled
    cd /${APP_ETC}/
    ALL_CACHE_ENABLED=true
    if [[ "${MAGENTO_VERSION}" = 2 ]]; then
        #cache_res=$(bin/magento cache:status | cut -d ": "-f 2) 
        while read -r l; do
            CNAME=$(echo $l | cut -d ":" -f 1)
            CNUM=$(echo $l | cut -d ":" -f 2)
            if [[ "${CNAME}" = *"config_integration:"* 
                || "${CNAME}" = *"config_integration_api"* 
                || "${CNAME}" = *"target_rule"* 
                || "${CNAME}" = *"config_webservice"* 
                || "$cname" = *"translate"* ]]; then
                if [[ "${CNUM}" = *"0"* ]]; then 
                    MESS_MAG_CONFIG+="${NOT_OK}Cache ${CNAME} is ${CNUM} and should be 1\n"
                    ALL_CACHE_ENABLED=false
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
    if [[ ${MAG_INSTALLATION} == true ]]; then 
        check_pub_folder
        check_https_redirection
        check_www_nonwww_redirection
        check_production_mode
        check_mysql_connection
        check_secure_unsecure_url
        if [[ "${ENV}" = prod ]]; then 
            check_alias;
            check_basic_auth_alias_test; 
            check_admin_user;
        else
            check_live_domain;
            check_basic_auth_test;
            check_mgt_user;
        fi
        check_cache_enabled
    fi
}

# For each file in nginx (except back, only those ending with conf we check everything )
function check_nginx_files() {
    for FILE in /etc/nginx/sites-enabled/*.conf; do
        MAG_INSTALLATION=true
        if [[ "${FILE}" = *"conf." ]]; then continue; fi
        MESS_NGINX+="\n   * \033[1mNGINX file ${FILE}\033[0m\n"
        global
        if [[ ${MAG_INSTALLATION} == false ]]; then continue; fi
        case ${PLAN} in
            ultimate)   
                check_admin_config  
                check_varnish 
                check_redis
                ;;
            enterprise)    
                check_admin_config
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

if [[ ${PLAN} == "ultimate" || ${PLAN} == "enterprise" ]];then
    echo -e "${MESS_VARNISH}"
    echo -e "${MESS_REDIS}"
    if [[ ${PLAN} == "enterprise" ]];then
        echo -e "${MESS_SSL}"
    fi
fi



printf "\nCompleted\n"
