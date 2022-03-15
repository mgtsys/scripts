#!/bin/bash

INSTALL_DIR="/usr/local/yakpro-po"
YAK_CONF="$INSTALL_DIR/yakpro-po.cnf"

if [[ -n $(which yakpro-po) ]]
then
        if [[ -d $INSTALL_DIR ]]
        then
                sed -i 60s/true/false/ $YAK_CONF
                sed -i 61s/true/false/ $YAK_CONF
                sed -i 62s/true/false/ $YAK_CONF
                sed -i 65s/true/false/ $YAK_CONF
                sed -i 67s/true/false/ $YAK_CONF
                sed -i 68s/true/false/ $YAK_CONF
                while true;
                do
                        echo -n "Enter the Source path of your module/code(Path must be absolute): "
                        read path
                        if [[ -n $path ]];
                        then
                                sed -i 86s%"'.*';"%"'$path';"% $YAK_CONF; sed -i 86s%"null;"%"'$path';"% $YAK_CONF
                        else
                                echo -e "\e[0;33mPress 'Ctrl-C' to exit the script, or enter the correct path.\e[0m"
                                continue
                        fi
                        echo -n "Enter the Output path for your obfuscated code(Path must be absolute): "
                        read path2
                        if [[ -n $path2 ]]
                        then
                                sed -i 87s%"'.*';"%"'$path2';"% $YAK_CONF; sed -i 87s%"null;"%"'$path2';"% $YAK_CONF
                        else
                                echo -e "\e[0;33mPress 'Ctrl-C' to exit the script, or enter the correct path.\e[0m"
                                continue
                        fi
                        break
                done
                conf_comment=$(grep '^#' /usr/local/yakpro-po/include/classes/config.php)
                if [[ -z $conf_comment ]]
                then
                        sed -i '105, 113 s/^/#/' /usr/local/yakpro-po/include/classes/config.php
                fi
               	num=1
                echo -e "\nEnter the files or directories that needs to be excluded: "
                exclude=()
                while IFS= read -r -p "Item $num (end with an empty line): " line;
                do
                        [[ $line ]] || break
                        exclude+=("'$line',")
                        num=$((num+1))
                done
                if [[ ${#exclude[0]} != 0 ]];
                then
                        sed -i "89s%\(null;\|array(.*);\)%array(${exclude[*]});%" $YAK_CONF
                else
                        sed -i "89s%\(null;\|array(.*);\)%null;%" $YAK_CONF
                fi
                echo -e "\n\e[0;32mYakpro configuration has been modified.\e[0m\n"
        fi
else
        git clone https://github.com/pk-fr/yakpro-po.git $INSTALL_DIR
        cd $INSTALL_DIR
        git clone https://github.com/nikic/PHP-Parser.git
        chmod a+x yakpro-po.php
        ln -s $INSTALL_DIR/yakpro-po.php /usr/local/bin/yakpro-po
        echo -e "\e[0;32mRe-run the Script\e[0m"
fi