MYSQL_ROOT_USER='root'
MYSQL_ROOT_PWD='4hyaKaeFUXPhw/oOwsY9aMEM'
DB_NAME='pressbook'
DB_USER='wpuser'
DB_USER_PWD='4hyaKaeFUXPhw/oOwsY9aMEM'

# 1) Full backup of all databases
BACKUP_PATH="/root/all-databases-backup-$(date +%F_%s).sql"
info "Backing up all databases to $BACKUP_PATH (this may take some time)..."
mysqldump --defaults-file="$TMP_MY_CNF" --all-databases --add-drop-database > "$BACKUP_PATH"
info "Backup complete."

info "Dropping all non-system databases (keeping mysql,information_schema,performance_schema,sys)..."
mysql --defaults-file="$TMP_MY_CNF" -e "
SET FOREIGN_KEY_CHECKS=0;
SET @dbs = (
  SELECT GROUP_CONCAT(SCHEMA_NAME)
  FROM INFORMATION_SCHEMA.SCHEMATA
  WHERE SCHEMA_NAME NOT IN ('mysql','information_schema','performance_schema','sys')
);
SET @q = CONCAT('DROP DATABASE IF EXISTS ', REPLACE(@dbs, ',', ', DROP DATABASE IF EXISTS '), ';');
PREPARE stmt FROM @q;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
SET FOREIGN_KEY_CHECKS=1;
SHOW DATABASES;
"
