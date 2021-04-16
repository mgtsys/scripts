#!/bin/bash
#Ver 1.0.2

if [[ $# -eq 0 ]]; then
  echo 'You should put the domain root directory name only'
  exit 0
fi

DOMAIN_ROOT_DIR=$1
MOUNTED_NFS=$(mount -l -t nfs4)

cd /home/cloudpanel/htdocs || exit

if [ ! -d $DOMAIN_ROOT_DIR ]; then
  echo "Directory does not exist"
  exit 0
fi

if [ -d $DOMAIN_ROOT_DIR/releases ]; then
  echo "Directory MCD Structure already exist"
  exit 0
fi

mv $DOMAIN_ROOT_DIR release1
mkdir -p $DOMAIN_ROOT_DIR/releases
mv release1 $DOMAIN_ROOT_DIR/releases/
cd $DOMAIN_ROOT_DIR || exit
mkdir shared
ln -s /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/releases/release1 current
cd shared || exit
mkdir var pub
mkdir -p pub/static

##Working with VAR dir
if [ -d ../current/var ]; then
  cd ../current/var || exit
else
  mkdir -p ../current/var
  cd ../current/var || exit
fi

if [ -d report ]; then
  mv report /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/
else
  mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/report
fi

ln -s ../../../shared/var/report report

if [ -d log ]; then
  mv log /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/
else
  mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/var/log
fi

ln -s ../../../shared/var/log log

###Working with PUB directory if is exist
if [ ! -d ../pub ]; then

  echo "Magento 1"
  cd ../
  if [[ ! $MOUNTED_NFS ]]; then
    mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/
  else
    mkdir -p /data/$DOMAIN_ROOT_DIR
    if [ -d /data/$DOMAIN_ROOT_DIR/media ]; then
      mv media media_backup
      echo "Media direcotry already exists, the media is moved to media_backup not Shared"
    else
      mv media /data/$DOMAIN_ROOT_DIR/
    fi
    ln -s /data/$DOMAIN_ROOT_DIR/media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/media
  fi
  ln -s ../../../shared/media media
  exit 0

fi

cd ../pub || exit

if [[ ! $MOUNTED_NFS ]]; then
  mv media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/
else
  mkdir -p /data/$DOMAIN_ROOT_DIR/pub
  if [ -d /data/$DOMAIN_ROOT_DIR/pub/media ]; then
    mv media media_backup
    echo "Media direcotry already exists, the media is moved to media_backup not Shared"
  else
    mv media /data/$DOMAIN_ROOT_DIR/pub/
  fi
  ln -s /data/$DOMAIN_ROOT_DIR/pub/media /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/media
fi

ln -s ../../../shared/pub/media media

if [ -d static/ ]; then
  cd static/ || exit
else
  mkdir -p static
  cd static/ || exit
fi

if [ -d _cache ]; then
  mv _cache /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache
else
  mkdir -p /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache
fi

if [[ $MOUNTED_NFS ]]; then
  mkdir -p /data/$DOMAIN_ROOT_DIR/pub/static
  mv /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache /data/$DOMAIN_ROOT_DIR/pub/static/
  ln -s /data/$DOMAIN_ROOT_DIR/pub/static/_cache /home/cloudpanel/htdocs/$DOMAIN_ROOT_DIR/shared/pub/static/_cache
fi

ln -s ../../../../shared/pub/static/_cache _cache
