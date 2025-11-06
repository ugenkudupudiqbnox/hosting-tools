MYSQL_ROOT_USER=''
MYSQL_ROOT_PWD='yourpass'
DB_NAME='pressbook'
DB_USER='wpuser'
DB_USER_PWD='yourpass'

TMP_MY_CNF="/root/.my.cnf.clean_install"
cat > "$TMP_MY_CNF" <<EOF
[client]
user=$MYSQL_ROOT_USER
password=$MYSQL_ROOT_PWD
EOF
chmod 600 "$TMP_MY_CNF"

mysql --defaults-file="$TMP_MY_CNF" -e "
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_USER_PWD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
SHOW DATABASES LIKE '$DB_NAME';
