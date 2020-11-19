#!/bin/bash
#Ver 1.0.0

if [[ $# -eq 0 ]] ; then
    echo 'You should put the domain root directory'
    exit 0
fi

DOMAIN_ROOT_DIR=$1;

cd /home/cloudpanel/htdocs;

if [ ! -d $DOMAIN_ROOT_DIR ]; then
   echo "Directory does not exist";
   exit 0
fi

mv $DOMAIN_ROOT_DIR release1;
mkdir -p $DOMAIN_ROOT_DIR/releases;
mv release1 $DOMAIN_ROOT_DIR/releases/;
cd $DOMAIN_ROOT_DIR;
mkdir shared;
ln -s /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/releases/release1 current;
cd shared;
mkdir var pub;
mkdir -p pub/static;

cd ../current/var;

if [ -d report ]; then
   mv report /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/;
else
   mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/report;
fi

ln -s ../../../shared/var/report report;

if [ -d log ]; then
   mv log /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/;
else
   mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/log;
fi

ln -s ../../../shared/var/log log;


if [ ! -d ../pub ]; then

   echo "Magento 1";
   cd ../
   mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/;
   ln -s ../../../shared/media media
   exit 0
   
fi


cd ../pub;
mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/;
ln -s ../../../shared/pub/media media

cd static/

if [ -d _cache ]; then
   mv _cache /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache;
else
   mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache;
fi

ln -s ../../../../shared/pub/static/_cache _cache
