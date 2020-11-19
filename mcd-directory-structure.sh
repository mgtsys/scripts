#!/bin/bash
#Ver 1.0.2

if [[ $# -eq 0 ]] ; then
    echo 'You should put the domain root directory'
    exit 0
fi

DOMAIN_ROOT_DIR=$1;
MOUNTED_NFS=$(mount -l -t nfs4)

cd /home/cloudpanel/htdocs;

if [ ! -d $DOMAIN_ROOT_DIR ]; then
   echo "Directory does not exist";
   exit 0
fi

if [ -d $DOMAIN_ROOT_DIR/releases ]; then
   echo "Directory MCD Structure already exist";
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

##Working with VAR dir
if [ -d ../current/var ]; then
   cd ../current/var;
else
   mkdir -p ../current/var;
   cd ../current/var;
fi

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

###Working with PUB directory if is exist
if [ ! -d ../pub ]; then

   echo "Magento 1";
   cd ../
   if [[ ! $MOUNTED_NFS ]]; then
      mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/;
      ln -s ../../../shared/media media
   else
      mkdir -p /data/$DOMAIN_ROOT_DIR;
      mv media /data/$DOMAIN_ROOT_DIR/;
      ln -s /data/$DOMAIN_ROOT_DIR/media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/media;
   fi

   exit 0

fi

cd ../pub;

if [[ ! $MOUNTED_NFS ]]; then
   mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/;
   ln -s ../../../shared/pub/media media
else
   mkdir -p /data/$DOMAIN_ROOT_DIR/pub;
   mv media /data/$DOMAIN_ROOT_DIR/pub/;
   ln -s /data/$DOMAIN_ROOT_DIR/pub/media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/media;
fi


if [ -d static/ ]; then
   cd static/;
else
   mkdir -p static;
   cd static/;
fi

if [ -d _cache ]; then
   mv _cache /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache;
else
   mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache;
fi

if [[ $MOUNTED_NFS ]]; then
   mkdir -p /data/$DOMAIN_ROOT_DIR/pub/static;
   mv /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache /data/$DOMAIN_ROOT_DIR/pub/static/;
   ln -s /data/$DOMAIN_ROOT_DIR/pub/static/_cache /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache;
fi

ln -s ../../../../shared/pub/static/_cache _cache
