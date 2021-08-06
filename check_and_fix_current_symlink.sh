#!/bin/bash
sleep 5s
NOW=$(date "+%F %T %Z")
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
WEBMASTER_INSTANCE_ID="WEBMASTER_INSTANCE_ID_XXXXX"
ADMIN_INSTANCE_IP="ADMIN_INSTANCE_IP_XXXXX"
DOCUMENT_ROOT="/home/cloudpanel/htdocs/CUSTOMER_DOMAIN_XXXXX"
FILE_OWNER="CUSTOMER_SSH_USER_XXXXX"
if [ "$INSTANCE_ID" != "$WEBMASTER_INSTANCE_ID" ]; then
  if pgrep -c nginx 1>/dev/null 2>/dev/null; then
    ADMIN_CURRENT_SYMLINK=$(ssh -i /root/.ssh/sync_files root@$ADMIN_INSTANCE_IP 'readlink '$DOCUMENT_ROOT'/current')
    CURRENT_SYMLINK=$(readlink $DOCUMENT_ROOT/current)
    if [ ! -z "$ADMIN_CURRENT_SYMLINK" ]; then
      if [ "$CURRENT_SYMLINK" != "$ADMIN_CURRENT_SYMLINK" ] || [ ! -d $CURRENT_SYMLINK ]; then
        rsync --delete --owner --group --exclude '/shared'  -lave "ssh -i /root/.ssh/sync_files" root@$ADMIN_INSTANCE_IP:$DOCUMENT_ROOT/ $DOCUMENT_ROOT/
        su -c "ln -sfn $ADMIN_CURRENT_SYMLINK $DOCUMENT_ROOT/current" $FILE_OWNER
        LOG_MESSAGE="$NOW - current symlink: '$CURRENT_SYMLINK' is not equal with admin server OR does not exist: '$ADMIN_CURRENT_SYMLINK' - rsync from admin"
        echo $LOG_MESSAGE >> /root/scripts/check_and_fix_current_symlink.log
        /etc/init.d/php7.4-fpm reload
      else
       echo "Nothing to do"
      fi
    fi
  fi
fi
