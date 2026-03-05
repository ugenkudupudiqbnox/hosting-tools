#!/bin/bash

# ------------------------------------------------
# Pressbooks / Bedrock Backup Script
# ------------------------------------------------

# SETTINGS
SITE_NAME="pressbooks.qbnox.com"
BEDROCK_PATH="/var/www/pressbooksoss-bedrock"        # root of bedrock project
UPLOADS_PATH="$BEDROCK_PATH/web/app/uploads"
APP_PATH="$BEDROCK_PATH/web/app"
ENV_FILE="$BEDROCK_PATH/.env"

BACKUP_DIR="/opt/backups/pressbooks"
DATE=$(date +"%Y-%m-%d_%H-%M")

# DB Credentials (read from .env if possible)
DB_NAME=$(grep DB_NAME $ENV_FILE | cut -d '=' -f2)
DB_USER=$(grep DB_USER $ENV_FILE | cut -d '=' -f2)
DB_PASSWORD=$(grep DB_PASSWORD $ENV_FILE | cut -d '=' -f2)
DB_HOST=$(grep DB_HOST $ENV_FILE | cut -d '=' -f2)

# Create backup directories
mkdir -p $BACKUP_DIR/database
mkdir -p $BACKUP_DIR/files

echo "Starting Pressbooks backup: $DATE"

# ------------------------------------------------
# DATABASE BACKUP
# ------------------------------------------------
echo "Backing up database..."

mysqldump \
  -h $DB_HOST \
  -u $DB_USER \
  -p$DB_PASSWORD \
  $DB_NAME \
  --single-transaction \
  --quick \
  --lock-tables=false \
  > $BACKUP_DIR/database/${SITE_NAME}_db_$DATE.sql

gzip $BACKUP_DIR/database/${SITE_NAME}_db_$DATE.sql

# ------------------------------------------------
# FILE BACKUP
# ------------------------------------------------
echo "Backing up files..."

tar -czf $BACKUP_DIR/files/${SITE_NAME}_files_$DATE.tar.gz \
    $UPLOADS_PATH \
    $APP_PATH/plugins \
    $APP_PATH/themes \
    $ENV_FILE \
    $BEDROCK_PATH/composer.json \
    $BEDROCK_PATH/composer.lock

# ------------------------------------------------
# OPTIONAL: BACKUP COMPLETE PROJECT
# ------------------------------------------------
# Uncomment if you want full backup
# tar -czf $BACKUP_DIR/${SITE_NAME}_full_$DATE.tar.gz $BEDROCK_PATH


# ------------------------------------------------
# CLEAN OLD BACKUPS (30 days)
# ------------------------------------------------
echo "Cleaning old backups..."

find $BACKUP_DIR -type f -mtime +30 -delete

# ------------------------------------------------
# DONE
# ------------------------------------------------
echo "Backup completed successfully: $DATE"
