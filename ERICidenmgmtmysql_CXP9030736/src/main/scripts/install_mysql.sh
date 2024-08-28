#!/bin/sh
###############################################################################
# Copyright (c) 2014 Ericsson Canada, Inc. All Rights Reserved.
# This script creates the Idenmgmt MYSQL database instance
# Author: Simo Elmajdoubi
# Version 1.0
#
#####################################################################################

MKDIR=/bin/mkdir
GREP=/bin/grep
CUT=/bin/cut
CHOWN=/bin/chown
CHMOD=/bin/chmod
TOUCH=/bin/touch
CHGRP=/bin/chgrp
RM=/bin/rm
TAR=/bin/tar
SED=/bin/sed
CP=/bin/cp
CHKCONFIG=/sbin/chkconfig
PS=/bin/ps

# directory definitions
TMP_DIR=/tmp
ETC_DIR=/etc
OPT_DIR=/opt
CMW_DIR=/etc/cluster/nodes/

# IDENMGMT deployment paths
IDENMGMT_DIR=/opt/ericsson/com.ericsson.oss.security/idenmgmt
IDENMGMT_BIN_DIR=$IDENMGMT_DIR/bin
IDENMGMT_MYSQL_BIN_DIR=$IDENMGMT_DIR/mysql/bin
IDENMGMT_CONFIG_DIR=$IDENMGMT_DIR/config

# MYSQL BINARY
MYSQL_BINARY=$IDENMGMT_DIR/mysql/pkg/mysql.tar.gz
MYSQL_UNCOMPRESSED_DIR=mysql-5.5.35-linux2.6-x86_64

# MYSQL directories
MYSQL_HOME=/opt/mysql
MYSQL_BIN_DIR=$MYSQL_HOME/bin
MYSQL_SCRIPTS_DIR=$MYSQL_HOME/scripts
MYSQL_SUPPORT_FILES_DIR=$MYSQL_HOME/support-files
MY_CNF_FILE=$ETC_DIR/mysql/my.cnf
#MYSQL_DATA_DIR=$IDENMGMT_DIR/mysql/data
MYSQL_DATA_DIR=/ericsson/mysql/data

# MYSQL executables
MYSQLD=$MYSQL_BIN_DIR/mysqld
MYSQLADMIN=$MYSQL_BIN_DIR/mysqladmin
MYSQLD_SAFE=$MYSQL_BIN_DIR/mysqld_safe
MYSQL=$MYSQL_BIN_DIR/mysql
MYSQL_SECURE_INSTALLATION=$MYSQL_BIN_DIR/mysql_secure_installation
MYSQL_SERVER=$MYSQL_SUPPOERT_FILES/mysql.server
MYSQL_INSTALL_DB=$MYSQL_SCRIPTS_DIR/mysql_install_db

# MYSQL Constants Definition
MYSQL_USER=idmmysql
MYSQL_GROUP=idmmysql
MYSQL_ROOT_USER=root

OPENIDM_SQL_FILE=$IDENMGMT_DIR/mysql/config/openidm.sql

# setup log file
LOG_DIR=/var/log/mysql
LOG_FILE="$LOG_DIR/install_mysql-`/bin/date "+%F:%H:%M:%S%:z"`.log"
TIME=`/bin/date "+%F:%H:%M:%S%:z"`



# setup SELINUX Policy for non default dir ($DATADIR)
MYSQL_LINUX_POLICY=$IDENMGMT_DIR/mysql/bin/mysqleric.pp
SEMODULE=/usr/sbin/semodule



#####################################################################################
# This functions sets the default log file.
# # Returns:
#       0       Success
#       1       Errors
# Globals:
#       LOG_FILE        log file
#       LOG_DIR         log directory
#####################################################################################
SetLogFile()
{
   # Create the log directory if it does not already exist
   if [ ! -d $LOG_DIR ] ; then
      mkdir -p $LOG_DIR
      if [ $? != 0 ] ; then
          echo "ERROR: Failed to create $LOG_DIR"
          return 1
      fi
   fi

   # Create LOG_ FILE
   $TOUCH $LOG_FILE > /dev/null 2>&1
   if [ $? != 0 ] ; then
      echo "ERROR: Failed to create $LOG_FILE"
      return 1
   fi
   # change permission on log file to rw to all
   $CHMOD 666 $LOG_FILE > /dev/null 2>&1
   if [ $? != 0 ] ; then
      echo "ERROR: Failed to change permissions for $LOG_FILE"
      return 1
   fi
   # change owner to mysql
   $CHOWN $MYSQL_USER:$MYSQL_GROUP $LOG_FILE
   if [ $? != 0 ] ; then
      echo "ERROR: Failed to change ownership of $LOG_FILE"
      return 1
   fi

   return 0
}


#####################################################################################
# This function stops mysql server
#
# Parameters:
#        none
# # Returns:
#       0       Success
#       1       Errors
#
#####################################################################################
ShutdownMysqlServer()
{
   LogMessage "ShutdownMysqlServer request has been received, process request..."
   /etc/init.d/mysql stop > /dev/null 2>&1
   if [ $? != 0 ] ; then
      for i in `ps -ef |grep mysqld |grep -v grep |awk '{print $2}'`;
      do
         kill -9 $i;
         if [ $? != 0 ] ; then
            LogMessage "ERROR: Failed to shutdown mysql server."
            return 1
         fi
      done
      return 1
   fi
   LogMessage "ShutdownMysqlServer completed successfully"
   return 0
}

#####################################################################################
# This function logs the given message to the default log file as defined by the
# LOG_FILE variable. The log message is proceeded with the current time stamp.
#
# Parameters:
#       1- Message string
#
# Globals:
#       LOG_FILE        default log file
#####################################################################################
LogMessage()
{
   if [ -w $LOG_FILE ] ; then
      msg="[`date '+%B %d %Y %T'`]: $1"
      echo $msg
      echo $msg >> $LOG_FILE

   fi
}

#####################################################################################
# Function:  UncompressMYSQLBinary
# Description: unzip and unstar MYSQL binary
# Parameters:  nothing
# Returns:    0  success
#             1  fail
#####################################################################################
UncompressMYSQLBinary()
{
  LogMessage "UncompressMYSQLBinary request has been received, process request..."

  $RM -rf $MYSQL_HOME  > /dev/null 2>&1
  $TAR --no-same-owner -zxf $MYSQL_BINARY -C $OPT_DIR
  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to expand mysql.tar.gz"
    return 1
  fi

  #create a symbolic link to mysql directory
  ln -s ${OPT_DIR}/${MYSQL_UNCOMPRESSED_DIR} $OPT_DIR/mysql
  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to create a symbolic link to mysql"
    return 1
  fi

  #change group and ownwrship of mysql home dir
  $CHOWN -R $MYSQL_USER:$MYSQL_GROUP $MYSQL_HOME
  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to change ownership of mysql home dir"
    return 1
  fi

  #change group and ownership of mysql data dir
  $CHOWN -R $MYSQL_USER:$MYSQL_GROUP $IDENMGMT_DIR/mysql
  if [ $? -ne 0 ]; then
    LogMessage "ERROR: failed to change ownership of mysql data dir"
    return 1
  fi

  #change group and ownership of mysql logs and pid test
  if [ -d /var/run/mysqld ]; then
    $CHOWN -R $MYSQL_USER:$MYSQL_GROUP /var/run/mysqld
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to change ownership of /var/run/mysqld"
      return 1
    fi    
  fi
  if [ -d /var/log/mysql ]; then
    $CHOWN -R $MYSQL_USER:$MYSQL_GROUP /var/log/mysql
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to change ownership of /var/log/mysql"
      return 1
    fi    
  fi


  if [ -f $MYSQL_BIN_DIR/mysqld_safe ]; then
    mv $MYSQL_BIN_DIR/mysqld_safe $MYSQL_BIN_DIR/mysqld_safe.$TIME
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to move mysqld_safe"
      return 1
    fi
    LogMessage "Original $MYSQL_BIN_DIR mysql_safe being backed up"
  fi

  if [ -f $IDENMGMT_MYSQL_BIN_DIR/mysqld_safe ]; then
    cp $IDENMGMT_MYSQL_BIN_DIR/mysqld_safe $MYSQL_BIN_DIR/mysqld_safe
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to copy mysqld_safe"
      return 1
    fi
    LogMessage "$MYSQL_BIN_DIR mysql_safe being replaced"

    $CHOWN -R $MYSQL_USER:$MYSQL_GROUP $MYSQL_BIN_DIR/mysqld_safe
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to chown mysqld_safe"
      return 1
    fi
  fi

  if [ -f $IDENMGMT_MYSQL_BIN_DIR/mysql_monitor ]; then
    if [ -f $MYSQL_BIN_DIR/mysql_monitor ]; then
      mv $MYSQL_BIN_DIR/mysql_monitor $MYSQL_BIN_DIR/mysql_monitor.$TIME
    fi

    cp $IDENMGMT_MYSQL_BIN_DIR/mysql_monitor $MYSQL_BIN_DIR/mysql_monitor
    if [ $? -ne 0 ]; then
      LogMessage "ERROR: failed to copy mysql_monitor"
      return 1
    fi
    LogMessage "$MYSQL_BIN_DIR mysql_monitor being copied"
  fi

### Make local MySQL dir ###
  mkdir -p /usr/local/mysql
  ln -s ${OPT_DIR}/${MYSQL_UNCOMPRESSED_DIR}/bin /usr/local/mysql/
  if [ $? -ne 0 ]; then
    LogMessage "WARNING: failed to create a symbolic link to mysql/bin"
    #TODO : ln would probably fail: ln: creating symbolic link `/usr/local/mysql/bin': File exists
    # we can log this as WARNING, or ad -p option to ln, or sth else?
  fi

  LogMessage "UncompressMYSQLBinary completed successfully"
  return 0
}

#######################################################################
# Function: CreateGrantTables
# Description: Creates the necessary users permissions tables
# Return Values:
#    0   Success
#    1   Failure
########################################################################
CreateGrantTables()
{
   LogMessage "CreateGrantTables request has been received, processing request..."
   $MYSQL_INSTALL_DB --defaults-file=/etc/mysql/my.cnf --user=$MYSQL_USER --basedir=$MYSQL_HOME --datadir=$MYSQL_DATA_DIR
   if [ "$?" -ne 0 ] ; then
       LogMessage "ERROR: Failed to create grant tables."
       return 1
   fi
   LogMessage "CreateGrantTables completed successfully..."
   return 0

}

#######################################################################
# Function: HardenMYSQL
# Description: Drops the unnecessary users in MYSQL database that are created
#              during MYSQL tar ball creation and default database.
# Return Values:
#    0   Success
#    1   Failure
########################################################################
HardenMYSQL()
{
   LogMessage "HardenMYSQL request has been received, processing request..."
   sqlScript=$TMP_DIR/dropUsers.sql.$$
   sqlOut=$TMP_DIR/dropUsers.out.$$

   cat << EOF > $sqlScript
set AUTOCOMMIT=0;
SET SESSION sql_log_off = 1;
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
SET SESSION sql_log_off = 0;
FLUSH PRIVILEGES;
commit;
quit
EOF

   if [ "$?" -ne 0 ] ; then
      LogMessage "ERROR: Failed to create temporary SQL script: [$sqlScript]."
      return 1
   fi

   $MYSQL -u$MYSQL_ROOT_USER < $sqlScript > $sqlOut 2>&1
   if [ "$?" -ne 0 ] ; then
       LogMessage "WARNING: Failed to execute the temporary SQL script: [$sqlScript]."
       cat $sqlOut >> $LOG_FILE
       return 1
   fi

   grep "ERROR" $sqlOut > /dev/null 2>&1
   if [ "$?" -eq 0 ] ; then
      LogMessage "WARNING: Failed to drop users and default database in database."
      cat $sqlOut >> $LOG_FILE
      return 1
   fi

   LogMessage "HardenMYSQL completed successfully."
   return 0

}
#######################################################################
# Function: PrimeOpenidmData
# Description: Creates the necessary tables and data used by openidm
# Return Values:
#    0   Success
#    1   Failure
########################################################################
PrimeOpenidmData()
{
   LogMessage "PrimeOpenidmData request has been received, processing request..."
   sqlOut=$TMP_DIR/primeOpenidmData.out.$$

   $MYSQL -u$MYSQL_ROOT_USER < $OPENIDM_SQL_FILE > $sqlOut 2>&1
   if [ "$?" -ne 0 ] ; then
       LogMessage "ERROR: Failed to execute the SQL script: [$OPENIDM_SQL_FILE]."
       cat $sqlOut >> $LOG_FILE
       return 1
   fi

   grep "ERROR" $sqlOut > /dev/null 2>&1
   if [ "$?" -eq 0 ] ; then
      LogMessage "ERROR: Failed to prime Openidm data."
      cat $sqlOut >> $LOG_FILE
      return 1
   fi

   LogMessage "PrimeOpenidmData completed successfully."
   return 0

}
#####################################################################################
#####################################################################################
# This function is called as a result of receiving a termination signal. The function
# performs all the necessary cleanup and then exits with an error.
#####################################################################################
CleanupAndExit()
{
   # Disable any traps while executing the cleanup function, this is to prevent trap recursion.
   trap "" 1 2 3 15

   LogMessage "Cleanup And Exit request has been received, process request..."
   exitCode=0
   if [ "$1" != "" ] ; then
      exitCode=$1
   fi

   # delete temporary files if any exists
   ls $TMP_DIR/*.$$ > /dev/null 2>&1
   if [ $? = 0 ] ; then
      LogMessage "Delete temporary files..."
      rm -f $TMP_DIR/*.$$
      if [ $? != 0 ] ; then
         LogMessage "ERROR: Failed to remove temporary files from $TMP_DIR at cleanup."
      fi
   fi

   if [ $exitCode = 0 ] ; then
      LogMessage "$MOD_NAME completed successfully!!!..."
   elif [ $exitCode = 1 ] ; then
      LogMessage "$MOD_NAME completed with errors!!!..."
   fi

   LogMessage "Please refer to the log file $LOG_FILE for more details ."
   exit $exitCode
}

##################################################################################
# Function: StartMYSQLServer
# Description: This function starts MYSQL server during Install
#              Once the daemon is started it checks if the MYSQL server is reachable
#              or not.
# Return Values:
#    0   Success
#    1   Failure
########################################################################
StartMYSQLServer()
{
   LogMessage "StartMYSQLServer request has been received, processing request..."

   $MYSQLD_SAFE --defaults-file=/etc/mysql/my.cnf --user=$MYSQL_USER --basedir=$MYSQL_HOME --datadir=$MYSQL_DATA_DIR --ledir=$MYSQL_HOME/bin & > $TMP_DIR/startMYSQL.out.$$ 2>&1
   if [ $? != 0 ] ; then
      LogMessage "ERROR: Starting MYSQL server has failed."
      cat $TMP_DIR/startMYSQL.out.$$ >> $LOG_FILE
      return 1
   fi

   loop_count=12
   retry_counter=0
   sleep_time=5

   while [ "$loop_count" -gt 0 ]
   do
      sleep $sleep_time
      # Ping the MYSQL server
      $MYSQLADMIN ping > $TMP_DIR/ping_out.$$ 2>&1
      if [ $? != 0 ] ; then
         loop_count=`expr $loop_count - 1`
         retry_counter=`expr $retry_counter + 1`
         LogMessage "WARNING: MYSQL is not alive in `expr $retry_counter \* $sleep_time` seconds."
         cat $TMP_DIR/ping_out.$$ >> $LOG_FILE
      else
         loop_count=0
         retry_counter=`expr $retry_counter + 1`
         LogMessage "MySQL server is alive"
         return 0
      fi
   done
   LogMessage "ERROR: MySQL failed to start."
   return 1
}


##################################################################################
# Function: StopMYSQLServer
# Description: This function stops MYSQL server after hardening
# Return Values:
#    0   Success
#    1   Failure
########################################################################
StopMYSQLServer()
{
   LogMessage "Start stoping mysql"
   pid=`ps aux | grep -v "install_mysql.sh" | grep -v "ERICidenmgmtmysql_CXP9030736" | grep "[m]ysql" | awk '{print $2}'`
   countpids=`echo $pid | wc -w`

   if test $countpids -gt 0; then
    kill $pid

    loop_count=20
    sleep_time=1

    while [ "$loop_count" -gt 0 ]
    do
      sleep $sleep_time
      pid=`ps aux | grep -v "install_mysql.sh" | grep -v "ERICidenmgmtmysql_CXP9030736" | grep "[m]ysql" | awk '{print $2}'`
      countpids=`echo $pid | wc -w`
      if test $countpids -eq 0; then
        LogMessage "MySQL stopped successfully"
        loop_count=0
        return 0;
      else
        loop_count=`expr $loop_count - 1`
        LogMessage "MySQL server is still alive"
      fi
    done
   fi

   return 1

}


##################################################################################
# Function: ConfigureMYSQLServer
# Description: This function performs the necessary steps to configure MYSQL server
# Following steps are performed to configure the MYSQL Server:-
# 1. Sets the configuration file (my.cnf).
# 2. Starts the MySQL server.
# 3. Hardens MySQL (drops the root and anonymous database users).
# 4.
# Return Values:
#    0   Success
#    1   Failure
##################################################################################
ConfigureMYSQLServer()
{

  LogMessage "ConfigureMYSQLServer request has been received, processing request..."
  CreateGrantTables
  if [ "$?" -ne 0 ] ; then
     LogMessage "ERROR: Failed to create grant tables."
     return 1
  fi

  LogMessage "ConfigureMYSQLServer completed successfully."
  return 0
}


#Set Predefined SELINUX Policy for $MYSQL_DATA_DIR###
set_mysql_selinux(){

        if [ ! -d $MYSQL_DATA_DIR ]
        then
                LogMessage " $MYSQL_DATA_DIR does NOT exist"
                mkdir -p $MYSQL_DATA_DIR
                RETVAL=$?
                if [ $RETVAL -ne 0 ]
                then
                        LogMessage "Failed to make  $MYSQL_DATA_DIR "
                        return 1
                fi
        else
                LogMessage "$MYSQL_DATA_DIR is already created, installation proceeded"
        fi

        $CHOWN -R $MYSQL_USER:$MYSQL_GROUP $MYSQL_DATA_DIR
        RETVAL=$?
        if [ $RETVAL -ne 0 ]
        then
                LogMessage "Failed to chown directory $MYSQL_DATA_DIR"
                return 3
        fi


        $SEMODULE -i $MYSQL_LINUX_POLICY
        RETVAL=$?
        if [ $RETVAL -ne 0 ]
        then
                LogMessage "Failed to execute SELINUX Policy for Mysql"
                return 3
        else
                LogMessage "SELINUX Policy set using $MYSQL_LINUX_POLICY - deployment proceeded"
        fi

}


####################################################
# Main Program
# Parameters: None
####################################################
SetLogFile
if [ $? != 0 ] ; then
   echo "ERROR: SetLogFile failed"
#   exit 1
fi
LogMessage "MySQL installation logging started..."

if [ ! -r "$MYSQL_BINARY" ]; then
    LogMessage "ERROR: $MYSQL_BINARY not found or is not an readable"
    exit 1
fi


set_mysql_selinux

UncompressMYSQLBinary

CleanupAndExit 0
