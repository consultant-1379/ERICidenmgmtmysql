#!/bin/bash

MYSQL_GROUP=idmmysql
MYSQL_USER=idmmysql
_LOGGER=/bin/logger
SCRIPT_NAME="ERICidenmgmtmysql_CXP9030736_RPM_PreInstall"


#//////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    $_LOGGER -t mysql -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    $_LOGGER -t mysql -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}


###Check if idmmysql Group Exists and if not create it###
check_mysql_group(){
        if grep -q -w $MYSQL_GROUP /etc/group
        then
                info "mysql <idmmysql> group exists, installation proceeded"
                return 0
        else
                info "mysql group does not exist, group $MYSQL_GROUP going to be created"
                groupadd -f -g 301 $MYSQL_GROUP
                RETVAL=$?
                if [ $RETVAL -ne 0 ]
                then
                        error "Failed to create group $MYSQL_GROUP"
                        return 3
                fi
        fi

}

###Check if idmmysql User  Exists and if not create it
check_mysql_user(){
        if id -u $MYSQL_USER >/dev/null 2>&1
        then
                info "MYSQL user exists, installation proceeded"
                return 0
        else
                info "MYSQL user does not exist, user $MYSQL_USER going to be created"

                useradd $MYSQL_USER -u 301 -g $MYSQL_GROUP
                RETVAL=$?
                if [ $RETVAL -ne 0 ]
                then
                        error "Failed to create user $MYSQL_USER"
                        return 4
                fi
        fi
}

check_mysql_group
check_mysql_user
