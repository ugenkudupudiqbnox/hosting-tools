#!/bin/bash

# ------------------------------------------------
# Pressbooks Bedrock Restore Script
# Ubuntu Server
# ------------------------------------------------

SITE_NAME="pressbooks"

BEDROCK_PATH="/var/www/pressbooks"
BACKUP_DIR="/var/backups/pressbooks"

DB_NAME="pressbooks"
DB_USER="pressbooksuser"
DB_PASSWORD="strongpassword"
DB_HOST="localhost"

LATEST_DB=$(ls -t $BACKUP_DIR/database/*.sql.gz | head -1)
LATEST_FILES=$(ls -t $BACKUP_DIR/files/*.tar.gz | head -1)

echo "======================================="
echo "Pressbooks Restore Starting"
echo "Using DB: $LATEST_DB"
echo "Using Files: $LATEST_FILES"
echo "======================================="

# ------------------------------------------------
# INSTALL REQUIRED PACKAGES
# ------------------------------------------------

sudo apt update

sudo apt install -y \
    nginx \
    mysql-server \
    php-fpm \
    php-mysql \
    php-curl \
    php-xml \
    php-mbstring \
    php-zip \
    php-gd \
    php-cli \
    unzip \
    composer

# ------------------------------------------------
# CREATE DATABASE
# ------------------------------------------------

echo "Creating database..."

mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# ------------------------------------------------
# RESTORE FILES
# ------------------------------------------------

echo "Restoring files..."

mkdir -p $BEDROCK_PATH

tar -xzf $LATEST_FILES -C /

# if archive extracted incorrectly
# tar -xzf $LATEST_FILES -C $BEDROCK_PATH

# ------------------------------------------------
# RESTORE DATABASE
# ------------------------------------------------

echo "Restoring database..."

gunzip < $LATEST_DB | mysql -u $DB_USER -p$DB_PASSWORD $DB_NAME

# ------------------------------------------------
# FIX PERMISSIONS
# ------------------------------------------------

echo "Setting permissions..."

chown -R www-data:www-data $BEDROCK_PATH

find $BEDROCK_PATH -type d -exec chmod 755 {} \;
find $BEDROCK_PATH -type f -exec chmod 644 {} \;

# uploads writable
chmod -R 775 $BEDROCK_PATH/web/app/uploads

# ------------------------------------------------
# COMPOSER INSTALL
# ------------------------------------------------

echo "Installing Bedrock dependencies..."

cd $BEDROCK_PATH

composer install --no-dev --optimize-autoloader

# ------------------------------------------------
# RELOAD SERVICES
# ------------------------------------------------

systemctl restart php*-fpm
systemctl restart nginx
systemctl restart mysql

echo "======================================="
echo "Pressbooks Restore Completed"
echo "Site root: $BEDROCK_PATH/web"
echo "======================================="
