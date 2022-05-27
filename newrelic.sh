#!/usr/bin/env bash

install='false'
uninstall='false'

while getopts 'iu' arg; do
  case $arg in
    i) install='true' ;;
    u) uninstall='true' ;;
    *) echo "Usage: cmd [-i] to install [-u] to uninstall"
       exit 1 ;;
  esac
  shift
done

kernel=$(uname -a | cut -f3 -d ' ')
kern_inst=$(uname -a | cut -f3 -d ' ' | cut -c 1-6)
wdir=$(pwd)

function check_kernel {
    echo "Checking Kernel"
    echo "Kernel Version: $kernel"
    if [ $kern_inst = "4.19.0" ] || [ $kern_inst = "5.10.0" ]
    then
        echo -e "\e[0;32mValid Kernel\e[0m"
    else
        echo -e "\e[0;31mUnsupported kernel for available module\e[0m"
        exit 1
    fi
}

function input {
    echo -ne "\nEnter the PHP version: "
    read php_ver
}

function fetch {
    if [ $kern_inst = "4.19.0" ]
    then
        newrelic_php71=$(php7.1 -m | grep newrelic)
        newrelic_php72=$(php7.2 -m | grep newrelic)
        newrelic_php73=$(php7.3 -m | grep newrelic)
        newrelic_php74=$(php7.4 -m | grep newrelic)
        newrelic_php80=$(php8.0 -m | grep newrelic)
        if [ "$php_ver" = "7.1" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.1"
            wget https://www.dropbox.com/s/647jv9pw23vvqg7/newrelic-php71-agent-arm.tar.gz &> /dev/null &&
            php71=$wdir/newrelic-php71-agent-arm.tar.gz
        elif [ "$php_ver" = "7.2" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.2"
            wget https://www.dropbox.com/s/8ur861vrhpz7fjo/newrelic-php72-agent-arm.tar.gz &> /dev/null &&
            php72=$wdir/newrelic-php72-agent-arm.tar.gz
        elif [ "$php_ver" = "7.3" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.3"
            wget https://www.dropbox.com/s/tpv880arnhkjihp/newrelic-php73-agent-arm.tar.gz &> /dev/null &&
            php73=$wdir/newrelic-php73-agent-arm.tar.gz
        elif [ "$php_ver" = "7.4" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.4"
            wget https://www.dropbox.com/s/ltvkbqcv39ye78l/newrelic-php74-agent-arm.tar.gz &> /dev/null &&
            php74=$wdir/newrelic-php74-agent-arm.tar.gz
        elif [ "$php_ver" = "8.0" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 8.0"
            wget https://www.dropbox.com/s/07hys92edhmkrkc/newrelic-php80-agent-arm.tar.gz &> /dev/null &&
            php80=$wdir/newrelic-php80-agent-arm.tar.gz
        fi
    elif [ $kern_inst = "5.10.0" ]
    then
        newrelic_php71=$(php7.1 -m | grep newrelic)
        newrelic_php72=$(php7.2 -m | grep newrelic)
        newrelic_php73=$(php7.3 -m | grep newrelic)
        newrelic_php74=$(php7.4 -m | grep newrelic)
        newrelic_php80=$(php8.0 -m | grep newrelic)
        newrelic_php81=$(php8.1 -m | grep newrelic)
        if [ "$php_ver" = "7.1" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.1"
            wget https://www.dropbox.com/s/uu39zq7txzq91ei/newrelic-php71-agent-arm.tar.gz &> /dev/null &&
            php71=$wdir/newrelic-php71-agent-arm.tar.gz
        elif [ "$php_ver" = "7.2" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.2"
            wget https://www.dropbox.com/s/m4vpojcyp3bumr7/newrelic-php72-agent-arm.tar.gz &> /dev/null &&
            php72=$wdir/newrelic-php72-agent-arm.tar.gz
        elif [ "$php_ver" = "7.3" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.3"
            wget https://www.dropbox.com/s/hsictbo55edlx0o/newrelic-php73-agent-arm.tar.gz &> /dev/null &&
            php73=$wdir/newrelic-php73-agent-arm.tar.gz
        elif [ "$php_ver" = "7.4" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 7.4"
            wget https://www.dropbox.com/s/ts7w3uiwritkqv8/newrelic-php74-agent-arm.tar.gz &> /dev/null &&
            php74=$wdir/newrelic-php74-agent-arm.tar.gz
        elif [ "$php_ver" = "8.0" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 8.0"
            wget https://www.dropbox.com/s/bcf1eg7mp4ad1zt/newrelic-php80-agent-arm.tar.gz &> /dev/null &&
            php80=$wdir/newrelic-php80-agent-arm.tar.gz
        elif [ "$php_ver" = "8.1" ]
        then
            echo -e "\nFetching New Relic php agent for PHP 8.1"
            wget https://www.dropbox.com/s/x227ul6rzr38wh8/newrelic-php81-agent-arm.tar.gz &> /dev/null &&
            php81=$wdir/newrelic-php81-agent-arm.tar.gz
        fi
    else
        echo "No compatible module found for kernel version $kernel"
    fi
}


function extract {
    if [[ "$php_ver" = "7.1" && -f $php71 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php71-agent-arm
        tar -xvzf $php71 -C newrelic-php71-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [[ "$php_ver" = "7.2" && -f $php72 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php72-agent-arm
        tar -xvzf $php72 -C newrelic-php72-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [[ "$php_ver" = "7.3" && -f $php73 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php73-agent-arm
        tar -xvzf $php73 -C newrelic-php73-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [[ "$php_ver" = "7.4" && -f $php74 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php74-agent-arm
        tar -xvzf $php74 -C newrelic-php74-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [[ "$php_ver" = "8.0" && -f $php80 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php80-agent-arm
        tar -xvzf $php80 -C newrelic-php80-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [[ "$php_ver" = "8.1" && -f $php81 ]]
    then
        echo "Unpacking New Relic agent"
        mkdir newrelic-php81-agent-arm
        tar -xvzf $php81 -C newrelic-php81-agent-arm &> /dev/null
        echo -e "\e[0;32mDONE!!!!\e[0m"
    else
        echo -e "\e[0;31mFile cannot be fetched\e[0m"
    fi
}

function install {
    if [ "$php_ver" == "7.1" ] || [ "$php_ver" == "7.2" ] || [ "$php_ver" == "7.3" ] || [ "$php_ver" == "7.4" ] || [ "$php_ver" == "8.0" ] || [ "$php_ver" == "8.1" ] ]
    then
        echo -e "\n\e[0;32mValid PHP Version\e[0m"
    else
        echo -e "\n\e[1;33mPlease choose the correct PHP version ( 7.1 || 7.2 || 7.3 || 7.4 || 8.0 || 8.1 )\e[0m"
        exit 1
    fi
    if [ "$php_ver" = "7.1" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php71-agent-arm/daemon /usr/bin/newrelic-daemon
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php71-agent-arm/newrelic.ini.template /etc/php/7.1/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php71-agent-arm/newrelic.so /usr/lib/php/20160303/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.2" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php72-agent-arm/daemon /usr/bin/newrelic-daemon || exit 0
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php72-agent-arm/newrelic.ini.template /etc/php/7.2/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php72-agent-arm/newrelic.so /usr/lib/php/20170718/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.3" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php73-agent-arm/daemon /usr/bin/newrelic-daemon
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php73-agent-arm/newrelic.ini.template /etc/php/7.3/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php73-agent-arm/newrelic.so /usr/lib/php/20180731/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.4" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php74-agent-arm/daemon /usr/bin/newrelic-daemon
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php74-agent-arm/newrelic.ini.template /etc/php/7.4/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php74-agent-arm/newrelic.so /usr/lib/php/20190902/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "8.0" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php80-agent-arm/daemon /usr/bin/newrelic-daemon
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php80-agent-arm/newrelic.ini.template /etc/php/8.0/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php80-agent-arm/newrelic.so /usr/lib/php/20200930/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "8.1" ]
    then
        killall newrelic-daemon &> /dev/null
        echo "Creating newrelic-daemon....."
        cp $wdir/newrelic-php81-agent-arm/daemon /usr/bin/newrelic-daemon
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.ini....."
        cp $wdir/newrelic-php81-agent-arm/newrelic.ini.template /etc/php/8.1/mods-available/newrelic.ini
        echo -e "\e[0;32mDONE!!!!\e[0m"
        echo "Creating newrelic.so....."
        cp $wdir/newrelic-php81-agent-arm/newrelic.so /usr/lib/php/20210902/newrelic.so
        echo -e "\e[0;32mDONE!!!!\e[0m"
    fi
    if [ -d /var/log/newrelic ] 
    then 
        rm -rf /var/log/newrelic 
    fi
    mkdir /var/log/newrelic
    touch /var/log/newrelic/newrelic-daemon.log /var/log/newrelic/php_agent.log
    if [[ "$php_ver" = "7.1" && "$newrelic_php71" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp71=$(php7.1 -m | grep newrelic)
        echo -e "\n$enphp71 is now enabled"
    elif [[ "$php_ver" = "7.2" && "$newrelic_php72" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp72=$(php7.2 -m | grep newrelic)
        echo -e "\n$enphp72 is now enabled"
    elif [[ "$php_ver" = "7.3" && "$newrelic_php73" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp73=$(php7.3 -m | grep newrelic)
        echo -e "\n$enphp73 is now enabled"
    elif [[ $php_ver = 7.4 && "$newrelic_php74" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp74=$(php7.4 -m | grep newrelic)
        echo -e "\n$enphp74 is now enabled"
    elif [[ $php_ver = 8.0 && "$newrelic_php80" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp74=$(php8.0 -m | grep newrelic)
        echo -e "\n$enphp80 is now enabled"
    elif [[ $php_ver = 8.1 && "$newrelic_php81" != newrelic ]]
    then
        phpenmod newrelic &> /dev/null
        systemctl restart php$php_ver-fpm.service
        enphp74=$(php8.1 -m | grep newrelic)
        echo -e "\n$enphp81 is now enabled"
    fi
    if [ "$php_ver" = "7.1" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php71-agent-arm newrelic-php71-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.2" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php72-agent-arm newrelic-php72-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.3" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php73-agent-arm newrelic-php73-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "7.4" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php74-agent-arm newrelic-php74-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "8.0" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php80-agent-arm newrelic-php80-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    elif [ "$php_ver" = "8.1" ]
    then
        echo -e "\nCleaning up files"
        rm -rf newrelic-php80-agent-arm newrelic-php81-agent-arm.tar.gz
        echo -e "\e[0;32mDONE!!!!\e[0m"
    fi
    agent_running=$(ps aux | grep newrelic | awk 'FNR != 3 {print $11}' | wc -l)
    if [[ $agent_running -ge 2 ]]
    then
        newrelic_ini=/etc/php/$php_ver/mods-available/newrelic.ini
        licensep=$(cat $newrelic_ini | grep 'newrelic.license = "REPLACE_WITH_REAL_KEY"')
        appnamep=$(cat $newrelic_ini | grep 'newrelic.appname = "PHP Application"')
        echo -e "\n\e[1;33mPress ENTER to Skip Prompts\e[0m"
        while true;
        do
            echo -ne "\nEnter New Relic License: "
            read license
            if [ -z $license ]
            then
                while true;
                do
                    echo -ne "\n\e[0;33mDo you want to add the license later?\e[0m" ""
                    read answer
                    if [ "${answer,,}" = "yes" ] || [ "${answer,,}" = "y" ]
                    then
                        echo -e "\e[1;33mLicense will be updated later.\e[0m"
                    elif [ -z $answer ]
                    then
                        continue
                    elif [ "${answer,,}" != "yes" ] && [ "${answer,,}" != "no" ]  && [ "${answer,,}" != "y" ] && [ "${answer,,}" != "n" ] 
                    then
                        echo -e "\n\e[1;31mPlease select yes or no.\e[0m"
                        continue
                    fi
                break
                done
                if [ "${answer,,}" = "no" ] || [ "${answer,,}" = "n" ]
                then
                    continue
                fi
            fi
        break
        done
        if [ -z $license ]
        then
            echo -e "\e[1;33mNo changes have been made.\e[0m"
        elif [ -n $license ]
        then
            echo $licensep | sed -i "s/REPLACE_WITH_REAL_KEY/$license/" $newrelic_ini
        fi
        while true;
        do
            echo -ne "\nEnter New Relic Application Name: "
            read appname
            if [ -z $appname ]
            then
                while true;
                do
                    echo -ne "\n\e[0;33mDo you want to add the Application name later?\e[0m" ""
                    read answer
                        if [ "${answer,,}" = "yes" ]
                        then
                            echo -e "\e[1;33mApplication name will be updated later.\e[0m"
                        elif [ -z ${answer} ]
                        then
                            continue
                    elif [ "${answer,,}" != "yes" ] && [ "${answer,,}" != "no" ]
                    then
                        echo -e "\n\e[1;31mPlease select yes or no.\e[0m"
                        continue
                    fi
                break
                done
                if [ "${answer,,}" = "no" ]
                then
                    continue
                fi
            fi
        break
        done
        if [ -z $appname ]
        then
            echo -e "\e[1;33mNo changes have been made.\e[0m"
        elif [ -n $appname ]
        then
            echo $appnamep | sed -i "s/PHP Application/$appname/" $newrelic_ini
        fi
        systemctl restart php$php_ver-fpm.service
        echo -e "\n\e[0;32mNewrelic PHP Agent Installed Successfully\e[0m\n"
    fi
}

function uninstall {
    MOD_DIR=$(php -i | grep ^extension_dir | cut -d " " -f 5)
    PHPv=$(php -v | grep -oP '(?<=PHP )[0-9]\.[0-9]')
    if [[ -f $MOD_DIR/newrelic.so ]]
    then
        echo -e "\nYou have New Relic installed for \e[0;32mPHP $PHPv\e[0m"
        while true;
        do
            echo -n "Do you want to uninstall it?" ""
            read answer
            if [ "${answer,,}" = "yes" ] || [ "${answer,,}" = "y" ]
            then
                echo "Uninstalling New Relic....."
                killall newrelic-daemon
                phpdismod newrelic &> /dev/null
                rm -rf /usr/bin/newrelic-daemon /etc/php/$PHPv/mods-available/newrelic.ini $MOD_DIR/newrelic.so /var/log/newrelic/
                systemctl restart php$PHPv-fpm.service
                echo -e "\n\e[0;32mUninstalled\e[0m\n"
            elif [ "${answer,,}" = "no" ] || [ "${answer,,}" = "n" ]
            then
                echo -e "New Relic has not been removed\n"
            else
                echo -e "\e[1;33mPlease select Yes or No to proceed.\e[0m\n"
                continue
            fi
        break
        done
    else
        echo -e "\n\e[1;31mNew Relic is not installed.\e[0m"
    fi
}

if [[ $install == true && ! -f /usr/bin/newrelic-daemon ]]
then
    input
    check_kernel
    fetch
    extract
    install
elif [[ $uninstall == true ]]
then
    if [ ! -f  /usr/bin/newrelic-daemon ]
    then
        echo -e "\n\e[1;33mNew Relic is not installed in this server.\e[0m\n"
        exit 1
    fi
    uninstall
elif [[ $install == true && -f /usr/bin/newrelic-daemon ]]
then
    echo -e "\e[0;32mNewrelic Exists\e[0m"
else
    echo "Usage: cmd [-i] to install [-u] to uninstall"
fi
