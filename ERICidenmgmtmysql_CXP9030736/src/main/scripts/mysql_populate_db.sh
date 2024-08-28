#!/bin/bash

LOG_FILE=mysql_populate_db.log

DB=openidm

INSTALL_PATH=/var/log/mysql

MYSQL_SLEEP_INT=5
MYSQL_NUM_TRIES=6

TMP_DIR=/tmp

# IDENMGMT deployment paths
IDENMGMT_DIR=/opt/ericsson/com.ericsson.oss.security/idenmgmt
IDENMGMT_BIN_DIR=$IDENMGMT_DIR/bin
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
MYSQL_OPENIDM_PWD=unknown

# OpenIDM Constants Definition
OPENSSL=/usr/bin/openssl
IDMMYSQL_PASSKEY=/ericsson/tor/data/idenmgmt/idmmysql_passkey
OPENIDM_SQL_FILE=$IDENMGMT_DIR/mysql/config/openidm.sql

# settings in global.properties
GLOBAL_PROPERTY_FILE=/ericsson/tor/data/global.properties

ACCESS_DENIED_SUFFIX="Access denied for user 'root'@'localhost' (using password: NO)"
SQL_ACCESS_DENIED_ERROR="ERROR 1045 (28000): ${ACCESS_DENIED_SUFFIX}"
SHOW_ACCESS_DENIED_ERROR="/opt/mysql/bin/mysqlshow: ${ACCESS_DENIED_SUFFIX}"

#*Functions*
log1(){
  msg=$1
  logger -s ${LOG_FILE} ${msg}
  echo "`date +[%D-%T]` $msg" &>>${INSTALL_PATH}/${LOG_FILE}
}

function logRotate() {
if [ -f ${INSTALL_PATH}/${LOG_FILE} ]
then
  LDATE=`date +[%m%d%Y%T]`
  mv ${INSTALL_PATH}/${LOG_FILE} ${INSTALL_PATH}/${LOG_FILE}.${LDATE}
  touch  ${INSTALL_PATH}/${LOG_FILE}
  chmod a+w ${INSTALL_PATH}/${LOG_FILE}
else
  touch  ${INSTALL_PATH}/${LOG_FILE}
  chmod a+w ${INSTALL_PATH}/${LOG_FILE}
fi
}

function serviceCheck(){
  hostname=`hostname`
  is_running=$(service mysql status | grep -i "running" | wc -l 2>${INSTALL_PATH}/${LOG_FILE})
  if [[ ${is_running} == 0 ]]; then
    log1 "MySQL is not running on $hostname we cannot install $DB Objects at this time"
    exit 1
  else
    log1 "MySQL is running on $hostname , we can now deploy $DB objects!"
  fi
}

function isDbCreated() {
   sqlOut=$TMP_DIR/dbCreatedCheck.out.$$

   /opt/mysql/bin/mysqlshow ${DB} > $sqlOut 2>&1
   if [ "$?" -ne 0 ] && [ "`cat $sqlOut`" == "${SHOW_ACCESS_DENIED_ERROR}" ]; then
     /opt/mysql/bin/mysqlshow -u$MYSQL_ROOT_USER -p${MYSQL_OPENIDM_PWD} ${DB} > $sqlOut 2>&1
   fi

   return "$?"
#  dbExists=$(psql -U postgres -c '\l' | grep ${DB_ROLE})
#  if [ -z "$dbExists" ]; then
#    return 1;# DB not present
#  else
#    return 0;# DB resent
#  fi
}

function db_test(){
  log1  "Database Validation for $DB"
  isDbCreated
  if [ $? -eq  1 ]; then
    log1 "There is currently no $DB on this server wait for ${MYSQL_SLEEP_INT} seconds!!! "
    for (( retry=0 ; retry < $MYSQL_NUM_TRIES ; retry ++ )); do
      isDbCreated
      if [ $? -eq  0 ]; then
        log1 "Database $DB now present. Can now Continue..."
        break
      fi
    sleep $MYSQL_SLEEP_INT
    done
  fi
}

function harden_mysql()
{
   log1 "HardenMYSQL request has been received, processing request..."
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
       log1 "ERROR: Failed to create temporary SQL script: [$sqlScript]."
       return 1
   fi

   $MYSQL -u$MYSQL_ROOT_USER < $sqlScript > $sqlOut 2>&1
   if [ "$?" -ne 0 ] && [ "`cat $sqlOut`" == "${SQL_ACCESS_DENIED_ERROR}" ]; then
      $MYSQL -u$MYSQL_ROOT_USER -p${MYSQL_OPENIDM_PWD} < $sqlScript > $sqlOut 2>&1
   fi

   if [ "$?" -ne 0 ] ; then
       log1 "WARNING: Failed to execute the temporary SQL script: [$sqlScript]."
       cat $sqlOut >> ${INSTALL_PATH}/${LOG_FILE}
       return 1
   fi

   grep "ERROR" $sqlOut > /dev/null 2>&1
   if [ "$?" -eq 0 ] ; then
       log1 "WARNING: Failed to drop users and default database in database."
       cat $sqlOut >> ${INSTALL_PATH}/${LOG_FILE}
       return 1
   fi

   log1 "harden_mysql completed successfully."
   return 0

}

function get_openidm_password()
{
   # we need access to the global.properties file and to the idmmysql passkey
   if [ ! -r "${GLOBAL_PROPERTY_FILE}" ]; then
     log1 "ERROR: Cannot read ${GLOBAL_PROPERTY_FILE}"
     exit 1
   fi
   if [ ! -r "${IDMMYSQL_PASSKEY}" ]; then
     log1 "ERROR: Cannot read ${IDMMYSQL_PASSKEY}"
     exit 1
   fi

   # get encrypted openidm mysql password
   idm_mysql_admin_password=`grep "idm_mysql_admin_password=" ${GLOBAL_PROPERTY_FILE} | sed "s/idm_mysql_admin_password=//"`

   if [ -z "${idm_mysql_admin_password}" ]; then
     log1 "ERROR: idm_mysql_admin_password is not set in ${GLOBAL_PROPERTY_FILE}"
     return 1
   fi

   # decrypt the openidm mysql password
   MYSQL_OPENIDM_PWD=`echo ${idm_mysql_admin_password} | ${OPENSSL} enc -a -d -aes-128-cbc -salt -kfile ${IDMMYSQL_PASSKEY}`
}

function prime_openidm_data()
{
   log1 "PrimeOpenidmData request has been received, processing request..."
   sqlOut=$TMP_DIR/primeOpenidmData.out.$$

   $MYSQL -u$MYSQL_ROOT_USER < $OPENIDM_SQL_FILE > $sqlOut 2>&1
   if [ "$?" -ne 0 ] && [ "`cat $sqlOut`" == "${SQL_ACCESS_DENIED_ERROR}" ]; then
      $MYSQL -u$MYSQL_ROOT_USER -p${MYSQL_OPENIDM_PWD} < $OPENIDM_SQL_FILE > $sqlOut 2>&1
   fi

   if [ "$?" -ne 0 ] ; then
     log1 "ERROR: Failed to execute the SQL script: [$OPENIDM_SQL_FILE]."
     cat $sqlOut >> ${INSTALL_PATH}/${LOG_FILE}
     return 1
   fi

   GRANT_ROOT_PRIVILEGES="GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '${MYSQL_OPENIDM_PWD}' WITH GRANT OPTION; FLUSH PRIVILEGES;"
   $MYSQL -u$MYSQL_ROOT_USER -e "$GRANT_ROOT_PRIVILEGES" > $sqlOut 2>&1
   if [ "$?" -ne 0 ] && [ "`cat $sqlOut`" == "${SQL_ACCESS_DENIED_ERROR}" ]; then
     $MYSQL -u$MYSQL_ROOT_USER -p${MYSQL_OPENIDM_PWD} -e "$GRANT_ROOT_PRIVILEGES" > $sqlOut 2>&1
   fi

   if [ "$?" -ne 0 ] ; then
     log1 "ERROR: Failed to execute the SQL command to update the MySQL root password."
     cat $sqlOut >> ${INSTALL_PATH}/${LOG_FILE}
     return 1
   fi

   grep "ERROR" $sqlOut > /dev/null 2>&1
   if [ "$?" -eq 0 ] ; then
     log1 "ERROR: Failed to prime Openidm data."
     cat $sqlOut >> ${INSTALL_PATH}/${LOG_FILE}
     return 1
   fi

   log1 "PrimeOpenidmData completed successfully."
   return 0

}

#*Main*
logRotate
serviceCheck
get_openidm_password
db_test
harden_mysql
prime_openidm_data
