#!/bin/sh
###############################################################################
# Copyright (c) 2014 Ericsson Canada, Inc. All Rights Reserved.
# This script uninstalls the Idenmgmt MySQL server
# Author: Simo Elmajdoubi
# Version 1.0
#
###############################################################################

if [ "$1" = "0" ]; then

    # Uninstall

    /sbin/chkconfig --del mysql
    
    for i in `/bin/ps -ef |/bin/grep mysqld |/bin/grep -v grep |/bin/awk '{print $2}'`;
    do
         /bin/kill -9 $i;
    done
    /bin/rm -rf /opt/ericsson/com.ericsson.oss.security/idenmgmt/mysql
    /bin/rm -rf /opt/mysql
    /bin/rm -rf /opt/mysql-5.5.35-linux2.6-x86_64

elif [ "$1" = "1" ]; then

    # Upgrade
    :

fi

exit 0
