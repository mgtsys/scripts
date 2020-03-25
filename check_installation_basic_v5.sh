#!/bin/bash
input=$1
if [ -z "$input" ]; then
    echo "Please input a plan (e.g. basic | premium | ultimate | enterprise)"
    exit 1
elif [[ $input != "basic" && $input != "premium" && $input != "ultimate" && $input != "enterprise" ]]; then
    echo "Please input VALID plan (e.g. basic | premium | ultimate | enterprise)"
    exit 1
fi


hostname=$(hostname)
private_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
ports=()
owners=()
i=0
root_dir=""
pub=""
file=""
redirection=""
redirection_https="" 
app_folder=""
test=false
magento=0
is_basic_auth=true
num=0



# checks the pools configuration of php, takes user owner and port number of pools. 
function check_ports {
    php_version=$(php -v | head -n 1 | cut -d " " -f 2 | cut -d "-" -f 1 | cut -d "." -f 1-2)
    #check if it is version 5 or 7 of php (because directories of pools are different for 5 and 7 version)
    if [[ $php_version == *"5."* ]]; then cd /etc/php5/fpm/pool.d/
    else cd /etc/php/$php_version/fpm/pool.d/
    fi
    # for each file in the pool.d directory except global.conf and clp.conf (default ones) then get the port and owner and put them in
    # a common array ports() and owners() that later will be chekced in nginx configuration files. 
    for file in *.conf; do
        if [ "$file" != "clp.conf" -a "$file" != "global.conf" ]; then
            port=$(sed -n 2p $file | cut -d ":" -f 2)
            ports+=("$port")
            owner=$(sed -n 3p $file | cut -d " " -f 3)
            owners+=("$owner")
        fi
    done
}

# checks if the ports in the nginx config file are ok and if the ownership of the files corresponds with that port. 
function check_ownership() {
    # get the configured port in nginx file. 
    nginx_port=$(sed -n "/fastcgi_pass/p" $file | awk 'NR == 1' | cut -d ":" -f 2 | cut -d ";" -f 1)
    # checks in the array which user uses that port (taken form php pool) and checks which user is the owner of the root directory  
    # If config is oK then resets permissions 775 just in case. 
    for i in "${!ports[@]}"; do
        if [ "${ports[$i]}" = "${nginx_port}" ]; then
            #echo "${i}";
            nginx_user=${owners[$i]}
            owner_folder=$(ls -lrt "/$root_dir" | awk 'NR == 2' | cut -d " " -f 4)
            if [ "$owner_folder" != "$nginx_user" ]; then
                echo -e "     \e[38;5;198mNOT OK: \e[0mFile ${file} uses port ${nginx_port} (user ${nginx_user}) and root folder's owner is ${owner_folder}"
            else
            #As we can not recursively check all permissions if they are 775 so we prefer to reset them just in case.
                echo "     Setting 775 permissions for root folder {$root_dir}" 
                chmod -R 775 "/$root_dir/"
            fi
        fi
    done
}

# checks if the https redirection (from http -> https) is working. 
function check_https_redirection() {
    # we take the server names from the nginx config file (as we can have more than one www1, www or without www)
    while read -r line; do
        # we get one of the server name
        server_name=$(echo $line | cut -d " " -f 2 | cut -d ";" -f 1)
        # we make sure we have not checked this server name before 
        if [[ $prev_host == *"${server_name}"* ]]; then
            # we add it in entry host 
            echo "${private_ip}     ${server_name}" >> /etc/hosts
            # num var is used to delete the entry hosts later (delete /etc/hosts lines we add in here)
            num=$((num+1))
            # we get the response of curl with http
            redirection=$(curl -s -Ik http://"${server_name}")
            # we get the server_name redirected (in case we are doing it with www and it redirects to without or with www1...)
            redirection_https=$(echo "${redirection,,}" | grep "location" | cut -d "/" -f 3)
            # get the protocol of the redirection (https or http) -> should be https 
            protocol=$(echo "${redirection,,}" | grep "location" | cut -d ":" -f 2)
            if [[ "${protocol}" != " https" ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mUrl ${server_name} does not redirect to https"; fi
        fi
        prev_host="${server_name}"
    done < <(sed -n "/server_name/p" $file | head -n 2)
}

# as it is a new config we check that alias (www1) is right configured.
function check_alias() {
    # as test does not need alias -> we skip it 
    is_test=$(echo "$file" | cut -d "." -f 1)
    if [[ $is_test != *"test"* ]]; then
        # now we connect using https instead of http
        curl_https=$(curl -s -Ik https://"${redirection_https}")
        # just make sure that one of the sever_name has www1 in nginx config file
        alias_www1=$(sed -n "/server_name/p" $file | sed -n "/www1/p" | wc -l)
        if [[ ${alias_www1} == "0" ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mYou don't have set an alias - www1"; 
        else
            # check the redirection of https
            redirection_www1=$(echo "${curl_https,,}" | sed -n "/location/p" | cut -d "/" -f 3)
            # if $redirection_https has www1 then we should not have location in the response
            # but if we do not have www1 in the https redirection then in the location we should have www1, if we don't is not oK
            if [[ ${redirection_https} != *"www1"* && ${redirection_www1} != *"www1"* ]]; then 
                echo -e "     \e[38;5;198mNOT OK: \e[0mYou don't have set an alias - www1 as domain"; 
            fi 
        fi
    elif [[ $is_test == "test" || $is_test == "stage" ]]; then test=true; fi
    # we want to know if the file we are checking is test or not 
}

function check_basic_auth() {
    curl_https=$(curl -s -Ik https://"${redirection_https}")
    basic_auth=$(echo "${curl_https,,}" | sed -n "/restricted/p" | cut -d '"' -f 2)
    if [ "${basic_auth}" != "restricted" ]; then
        echo -e "     \e[38;5;198mNOT OK: \e[0mPlease enable Basic auth"
        # we set this for when we are checking varnish
        is_basic_auth=false
    fi
}

# checking that the SSL certificate is up to date (valid)
function check_ssl_cert() {
    ssl_cert=$(curl --insecure -v https://"${redirection_https}" 2>&1 | awk 'BEGIN { cert=0 } /^\* SSL connection/ { cert=1 } /^\*/ { if (cert) print }' | sed -n "/SSL certificate verify/p")
    if [[ $ssl_cert == *expired* ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mSSL Certificate not ok -> install Letsencrypt"; fi
}

# check if in magento 2 is pointing to pub folder 
function check_pub_folder() {
    # get the config magento file
    #app_folder=$(ls -lrt "/${root_dir}/app/etc/" | sed -n "/local.xml/p;/env.php/p" | grep -v "xml." | grep -v "php." | cut -d " " -f 11)
    app_folder=$(ls -lrt "/${root_dir}/app/etc/" | sed -n "/local.xml/p;/env.php/p")
    # we know that the file=env.php then is magento2 
    if [[ "${app_folder}" = *"env.php"* ]]; then
        app_folder="env.php"
        magento=2
        #IS MAGENTO 2 --> root directory should have pub and should be rwo media blocks in nginx. 
        if [[ "${pub}" != "pub" ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mRoot folder does not contain /pub"; fi
        # check if media blocks are in nginx config -> is a warning if there are not to check if images are loading
        media_blocks=$(sed -n "/media/p" $file | wc -l)
        if [ "${media_blocks}" != "2" ]; then echo -e "     \e[38;5;198mWARNING: \e[0mYou should have 'location /media/' block for 80 and 443 - check if images are loading"; fi
    elif [[ "${app_folder}" = *"local.xml"* ]]; then
        # we set the config file (in case there are local.xml.bak etc,...)
        app_folder="local.xml"
        magento=1
        # should not have pub configued as in magento1 it does not exist
        if [[ "${pub}" == "pub" ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mRoot folder contains /pub and should not because is Magento1"; fi
    fi
}

# check varnish config 
function check_varnish() {
    #disable basic auth as when absic auth is enable we cannot check it
    if [[ $is_basic_auth == true ]]; then
        # we comment the basic auth config in nginx config file
        sed -i "s/auth_basic_user_file/# auth_basic_user_file/g" $file
        auth=$(sed -n "/auth_basic/p" $file | grep -v "#" | grep -v "off")
        sed -i "s/${auth}/#${auth}/g" $file
        # we check ginx config is ok and then if it is we restart NGINX
        nginx_ok=$(echo  $(nginx -t 2>&1) | sed -n "/successful/p")
        if [[ "${nginx_ok}" = *"successful"* ]]; then
            /etc/init.d/nginx restart
            echo "Restarting NGINX"
        else 
            echo "An error has occurred: cannot restart nginx. check nginx -t"
        fi
    fi
    sleep 1
    # we check if we received x-cache-age -> if varnish is working properly we should receive a number higher than 0 (the 2nd curl)
    curl_https=$(curl -s -Ik https://${redirection_https})
    curl_https=$(curl -s -Ik https://${redirection_https})
    varnish=$(echo "${curl_https,,}" | grep "x-cache-age" | cut -d " " -f 2)
    if [[ $varnish == "0"* || -z $varnish ]]; 
        then echo -e "     \e[38;5;198mNOT OK: \e[0mVarnish is not working"; 
    #    we should check thath the MGT extension of varnish is there --> if it is not working only.  
        if [[ "${magento}" = 2 ]]; then
            if [ ! -d "/${root_dir}/app/code/Mgt/Varnish" ]; then echo -e "     \e[38;5;198mNOT OK: \e[0mYou don't have the Varnish extension of Mgt"; fi    
        else 
            if [ ! -d "/${root_dir}/app/code/community/Mgt/Varnish" ]; then echo -e "     \e[38;5;198mNOT OK: \e[0mYou don't have the Varnish extension of Mgt"; fi    
        fi
    fi
    # enable basic auth AGAIN
    if [[ $is_basic_auth == true ]]; then
        sed -i "s/# auth_basic_user_file/auth_basic_user_file/g" $file
        sed -i "s/#${auth}/${auth}/g" $file
        # now restart NGINX
        nginx_ok=$(echo  $(nginx -t 2>&1) | sed -n "/successful/p")
        if [[ "${nginx_ok}" = *"successful"* ]]; then
            /etc/init.d/nginx restart
            echo "Restarting NGINX"
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
        echo -e "     \e[38;5;198mNOT OK: \e[0mCache and Session Redis not working properly."
    else 
        # check in the env.php or local.xml the redis satabases (db1 and db2 for session & cache)
        config_file="/${root_dir}/app/etc/${app_folder}"
        db1=$(sed -n "/database/p" $config_file | head -n 1 | cut -d ">" -f 2)
        db2=$(sed -n "/database/p" $config_file | tail -n 1 | cut -d ">" -f 2)
        contains_db1=false
        contains_db2=false
        # we run the command redis-cli info and check how many databases we have there. FOr each one of them we make sure that the two db in the file are there 
        while read -r l; do
            db=$(echo $l | cut -d ":" -f 1 | cut -c 3-)
            if [[ "$db1" == *"$db"* ]]; then contains_db1=true
            elif [[ "$db2" == *"$db"* ]]; then contains_db2=true; fi
            if [[ "$db1" == *"$db"* && "$db2" == *"$db"* ]]; then 
                # In this case the configuration for session and redis is the same and the databases numbers should be different (because it is localhost - single server)
                echo -e "     \e[38;5;198mNOT OK: \e[0mIn config file the db for redis is the same for session and cache. The dbs should be different"; 
            fi 
        done < <(redis-cli info | sed -n "/db/p" | grep -v "rdb")
        if [[ $contains_db1 == false && $contains_db2 == false ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mCache and Session Redis not working properly."
        elif [[ $contains_db1 == false || $contains_db2 == false ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mCache OR Session Redis is not working properly. Please check it "; fi
    fi
}

# For each file in nginx (except back, only those ending with conf we check everything )
function check_nginx_files() {
    cd /etc/nginx/sites-enabled/
    for file in *.conf; do
        if [[ "$file" = *"conf." ]]; then continue; fi
        printf "\n Checking nginx configuration file : ${file}:\n"
        
        root_dir=$(sed -n "/root/p" $file | awk 'NR == 1' | cut -d "/" -f 2-5 | cut -d ";" -f 1)
        pub=$(sed -n "/root/p" $file | awk 'NR == 1' | cut -d "/" -f 6 | cut -d ";" -f 1)
        nginx_port=$(sed -n "/fastcgi_pass/p" $file | awk 'NR == 1' | cut -d ":" -f 2 | cut -d ";" -f 1)
        
        check_ownership
        check_pub_folder
        check_https_redirection
        check_alias
        check_basic_auth
        if [[ $input != "basic" && $input != "premium" ]]; then
            check_varnish
            check_redis
        fi
        if [[ $input == "enterprise" ]]; then check_ssl_cert; fi
        # remove all the entry hosts that we have put in /etc/hosts
        for (( i=0; i<$num; ++i)); do sed -i '$ d' /etc/hosts; done
    done
    if [[ $input != "basic" && $test == false ]]; then echo -e "     \e[38;5;198mNOT OK: \e[0mThere should be test or stage environments"; fi
}



check_ports
check_nginx_files
printf "\nCompleted"
