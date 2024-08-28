#!/bin/bash

GLOBAL_PROPERTY_FILE=/ericsson/tor/data/global.properties
source ${GLOBAL_PROPERTY_FILE}
OPENSSL=/usr/bin/openssl
MYSQL=/opt/mysql/bin/mysql
mysqlPasskey=/ericsson/tor/data/idenmgmt/idmmysql_passkey

TMP_SQL_SCRIPT=./remove.sql
SQL_OUT=./sql.out

ARRAY=`cat /etc/hosts | grep "db-"| awk '{print $1}'`
declare -a ARRAYNAME
count=0
for i in ${ARRAY[@]}; do
        NAME=`cat /etc/hosts  | grep -w ${i}| awk '{print $2}'`
        for j in ${NAME[@]}; do
                ARRAYNAME[count]=${j}
                count=$(( $count + 1 ))
        done
done

declare -a STRINGA
count=0
for j in ${ARRAYNAME[@]}; do
STRINGA[count]="INSERT INTO mysql.user VALUES ('${j}','openidm',@variable1,'N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','N','','','','',1000,1000,1000,1000,'',NULL),
('${j}','root',@variable1,'Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','Y','','','','',1000,1000,1000,1000,'',NULL);"
count=$(( $count + 1 ))
done

cat << EOF > $TMP_SQL_SCRIPT
SET @variable1 = (select password from mysql.user where user='root' and host='%');
UPDATE mysql.user SET host='mysql' WHERE host='%';
UPDATE mysql.user SET max_questions=1000, max_updates=1000, max_connections=1000,  max_user_connections=1000  WHERE user='root' or user='openidm';
${STRINGA[@]}
quit
EOF

eval "MYSQL_OPENIDM_PWD"="$(echo "$idm_mysql_admin_password" | "$OPENSSL" enc -a -d -aes-128-cbc -salt -kfile "$mysqlPasskey")"
$( $MYSQL --user=root --password=$MYSQL_OPENIDM_PWD --host=localhost < $TMP_SQL_SCRIPT > $SQL_OUT 2>&1 )
if [ $? != 0 ] ; then
    echo "ERROR: Failed to harden mysql"
else
    echo "Succeeded to harden mysql"
fi

echo "Restarting mysql service ..."
service mysql restart
