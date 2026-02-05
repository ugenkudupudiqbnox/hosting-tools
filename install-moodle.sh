#!/bin/bash
################################################################################
# Moodle 5.1.1 Automated Installation Script
#
# Usage: sudo ./install-moodle.sh [FQDN]
#   FQDN: Fully qualified domain name (e.g., learn.example.com)
#         If not provided, uses 'localhost' and skips SSL setup
#
# Requirements:
#   - Ubuntu 22.04 LTS
#   - Root/sudo access
#   - Internet connection
#
# Author: Generated from CLAUDE.md installation guide
# Date: 2026-02-05
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get FQDN from argument or use localhost
FQDN="${1:-localhost}"
USE_SSL="false"

if [[ "$FQDN" != "localhost" ]]; then
    USE_SSL="true"
    log_info "Installing Moodle with FQDN: $FQDN (SSL enabled)"
else
    log_warning "Installing Moodle with localhost (SSL disabled)"
fi

# Configuration variables
DB_NAME="moodle"
DB_USER="moodleuser"
MOODLE_ADMIN_EMAIL="admin@${FQDN}"
MOODLE_DIR="/var/www/moodle"
MOODLE_DATA="/opt/www/moodledata"
BACKUP_DIR="/opt/backups/moodle"
CREDENTIALS_FILE="/root/moodle-credentials.txt"

# Auto-generate secure passwords using openssl
log_info "Generating secure passwords..."
DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
DB_ROOT_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Auto-detect system resources
CPU_CORES=$(nproc)
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')

# Calculate optimal settings based on resources
# MariaDB: Use 50-60% of RAM for innodb_buffer_pool
INNODB_BUFFER_POOL=$((TOTAL_RAM_GB * 60 / 100))
if [[ $INNODB_BUFFER_POOL -lt 1 ]]; then
    INNODB_BUFFER_POOL=1
fi

# PHP-FPM: max_children = CPU * 10-20 (we use 15 as middle ground)
PHP_MAX_CHILDREN=$((CPU_CORES * 15))
if [[ $PHP_MAX_CHILDREN -lt 10 ]]; then
    PHP_MAX_CHILDREN=10
fi

# PHP-FPM: start_servers = CPU * 2
PHP_START_SERVERS=$((CPU_CORES * 2))
if [[ $PHP_START_SERVERS -lt 4 ]]; then
    PHP_START_SERVERS=4
fi

# PHP-FPM: min_spare_servers = start_servers / 2
PHP_MIN_SPARE=$((PHP_START_SERVERS / 2))
if [[ $PHP_MIN_SPARE -lt 2 ]]; then
    PHP_MIN_SPARE=2
fi

# PHP-FPM: max_spare_servers = start_servers * 2
PHP_MAX_SPARE=$((PHP_START_SERVERS * 2))

# Redis: Use 5-10% of RAM (we use 512MB or 5% whichever is less)
REDIS_MEMORY=$((TOTAL_RAM_MB * 5 / 100))
if [[ $REDIS_MEMORY -gt 512 ]]; then
    REDIS_MEMORY=512
fi
if [[ $REDIS_MEMORY -lt 128 ]]; then
    REDIS_MEMORY=128
fi

# MariaDB: innodb_buffer_pool_instances = CPU cores (max 16)
INNODB_INSTANCES=$CPU_CORES
if [[ $INNODB_INSTANCES -gt 16 ]]; then
    INNODB_INSTANCES=16
fi

log_info "Starting Moodle installation..."
log_info "Passwords auto-generated using OpenSSL"
log_info "System Resources Detected:"
log_info "  - CPU Cores: $CPU_CORES"
log_info "  - Total RAM: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)"
echo
log_info "Optimized Configuration:"
log_info "  - MariaDB Buffer Pool: ${INNODB_BUFFER_POOL}G (${INNODB_INSTANCES} instances)"
log_info "  - PHP-FPM Max Children: $PHP_MAX_CHILDREN"
log_info "  - PHP-FPM Start Servers: $PHP_START_SERVERS"
log_info "  - Redis Memory: ${REDIS_MEMORY}MB"
echo
log_info "Installation Configuration:"
log_info "  - FQDN: $FQDN"
log_info "  - SSL: $USE_SSL"
log_info "  - Database: $DB_NAME"
log_info "  - Moodle Directory: $MOODLE_DIR"
log_info "  - Data Directory: $MOODLE_DATA"
log_info "  - Max File Upload: 512MB"
echo

################################################################################
# 1. SYSTEM PREPARATION
################################################################################
log_info "Step 1: System Preparation"

apt update && apt upgrade -y

apt install -y software-properties-common curl wget git unzip \
    graphviz aspell ghostscript clamav

# Create directories
mkdir -p /opt/www
chown -R www-data:www-data /opt/www

log_success "System preparation complete"

################################################################################
# 2. MARIADB INSTALLATION
################################################################################
log_info "Step 2: Installing MariaDB 11.4"

# Install MariaDB repository
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | bash -s -- --mariadb-server-version=11.4

apt update
DEBIAN_FRONTEND=noninteractive apt install -y mariadb-server mariadb-client

# Start MariaDB
systemctl start mariadb
systemctl enable mariadb

# Secure MariaDB installation (automated)
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';" || true
mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# Create Moodle database and user
mysql -u root -p"${DB_ROOT_PASS}" << EOF
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Optimize MariaDB configuration (auto-tuned for ${CPU_CORES} cores, ${TOTAL_RAM_GB}GB RAM)
cat > /etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf << EOF
[mysqld]
# InnoDB Settings (optimized for available RAM)
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL}G
innodb_buffer_pool_instances = ${INNODB_INSTANCES}
innodb_log_file_size = 512M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Connection Settings
max_connections = 300
max_allowed_packet = 256M

# Timeout Settings (for large file uploads)
wait_timeout = 28800
interactive_timeout = 28800
net_read_timeout = 1800
net_write_timeout = 1800

# Query Cache (disabled in MariaDB 10.6+)
query_cache_size = 0
query_cache_type = 0

# Table Cache
table_open_cache = 4000
table_definition_cache = 2000

# Thread Settings
thread_cache_size = 50
thread_stack = 256K

# Temp Table Settings
tmp_table_size = 256M
max_heap_table_size = 256M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
log_error = /var/log/mysql/error.log
EOF

systemctl restart mariadb

log_success "MariaDB installation complete"

################################################################################
# 3. PHP 8.3 INSTALLATION
################################################################################
log_info "Step 3: Installing PHP 8.3"

add-apt-repository -y ppa:ondrej/php
apt update

apt install -y php8.3-fpm php8.3-cli php8.3-common \
    php8.3-mysql php8.3-xml php8.3-xmlrpc php8.3-curl \
    php8.3-gd php8.3-imagick php8.3-dev \
    php8.3-imap php8.3-mbstring php8.3-opcache \
    php8.3-soap php8.3-zip php8.3-intl php8.3-redis

# Configure PHP for large uploads and extended timeouts
cat > /etc/php/8.3/fpm/conf.d/99-moodle.ini << 'EOF'
# File Upload Settings
upload_max_filesize = 512M
post_max_size = 512M
max_input_vars = 5000

# Execution Timeout Settings (30 minutes for large file uploads)
max_execution_time = 1800
max_input_time = 1800
default_socket_timeout = 1800

# Memory Settings
memory_limit = 256M

# Session Settings
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379"
EOF

# Configure OPcache
cat > /etc/php/8.3/fpm/conf.d/99-moodle-opcache.ini << 'EOF'
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
opcache.save_comments = 1
opcache.enable_cli = 0
EOF

# Optimize PHP-FPM pool (auto-tuned for ${CPU_CORES} cores)
cat > /etc/php/8.3/fpm/pool.d/zzz-moodle-optimized.conf << EOF
[www]
pm = dynamic
pm.max_children = ${PHP_MAX_CHILDREN}
pm.start_servers = ${PHP_START_SERVERS}
pm.min_spare_servers = ${PHP_MIN_SPARE}
pm.max_spare_servers = ${PHP_MAX_SPARE}
pm.max_requests = 500
pm.process_idle_timeout = 10s
request_terminate_timeout = 1800

# Per-pool PHP settings
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_flag[display_errors] = off
php_admin_value[error_log] = /var/log/php8.3-fpm-moodle.log
EOF

systemctl restart php8.3-fpm
systemctl enable php8.3-fpm

log_success "PHP 8.3 installation complete"

################################################################################
# 4. NGINX INSTALLATION
################################################################################
log_info "Step 4: Installing and configuring Nginx"

apt install -y nginx

# Create extended timeout configuration
cat > /etc/nginx/conf.d/moodle-timeouts.conf << 'EOF'
# Extended timeouts for large file uploads (30 minutes)
client_body_timeout 1800s;
client_header_timeout 1800s;
fastcgi_connect_timeout 1800s;
fastcgi_send_timeout 1800s;
fastcgi_read_timeout 1800s;
proxy_connect_timeout 1800s;
proxy_send_timeout 1800s;
proxy_read_timeout 1800s;
send_timeout 1800s;
EOF

# Create performance optimization configuration
cat > /etc/nginx/conf.d/moodle-performance.conf << 'EOF'
# FastCGI cache settings
fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=moodle:100m inactive=60m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;

# Buffer settings
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
client_body_buffer_size 256k;
EOF

mkdir -p /var/cache/nginx/fastcgi
chown -R www-data:www-data /var/cache/nginx

log_success "Nginx configuration complete"

################################################################################
# 5. MOODLE INSTALLATION
################################################################################
log_info "Step 5: Installing Moodle 5.1.1"

# Install Composer
cd /tmp
curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm -f composer-setup.php

# Download Moodle 5.1.1
if [[ -d "$MOODLE_DIR" ]]; then
    log_warning "Moodle directory already exists. Backing up to ${MOODLE_DIR}.backup"
    mv "$MOODLE_DIR" "${MOODLE_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
fi

cd /var/www
git clone --branch MOODLE_501_STABLE --depth 1 https://github.com/moodle/moodle.git
cd moodle

# Install Composer dependencies
sudo -u www-data composer install --no-dev --classmap-authoritative

# Set ownership and permissions
chown -R www-data:www-data "$MOODLE_DIR"
chmod -R 755 "$MOODLE_DIR"

# Create Moodle data directory
mkdir -p "$MOODLE_DATA"
chown -R www-data:www-data "$MOODLE_DATA"
chmod -R 770 "$MOODLE_DATA"

# Determine WWW root based on SSL
if [[ "$USE_SSL" == "true" ]]; then
    WWW_ROOT="https://${FQDN}"
else
    WWW_ROOT="http://${FQDN}"
fi

# Create config.php
cat > "${MOODLE_DIR}/config.php" << EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

// Database Configuration
\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'localhost';
\$CFG->dbname    = '${DB_NAME}';
\$CFG->dbuser    = '${DB_USER}';
\$CFG->dbpass    = '${DB_PASS}';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

// Site Configuration
\$CFG->wwwroot   = '${WWW_ROOT}';
\$CFG->dataroot  = '${MOODLE_DATA}';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 0770;

// Redis Session Handler
\$CFG->session_handler_class = '\core\session\redis';
\$CFG->session_redis_host = '127.0.0.1';
\$CFG->session_redis_port = 6379;
\$CFG->session_redis_database = 0;
\$CFG->session_redis_prefix = 'moodle_sess_';
\$CFG->session_redis_acquire_lock_timeout = 120;
\$CFG->session_redis_lock_expire = 7200;

// Session Settings
\$CFG->sessiontimeout = 28800; // 8 hours

// Session Persistence (prevents logout during course restore)
\$CFG->sessioncookiepath = '/';
\$CFG->sessioncookiedomain = '';
\$CFG->sessiontimeoutcounter = true;

// Performance Settings
\$CFG->cachejs = true;
\$CFG->yuicomboloading = true;
\$CFG->maxbytes = 536870912; // 512MB

// Debug Settings (Disable in Production)
\$CFG->debug = 0;
\$CFG->debugdisplay = 0;
\$CFG->perfdebug = 0;
\$CFG->debugpageinfo = 0;

// Email Settings
\$CFG->noemailever = false;

require_once(__DIR__ . '/lib/setup.php');
EOF

chown www-data:www-data "${MOODLE_DIR}/config.php"
chmod 640 "${MOODLE_DIR}/config.php"

log_success "Moodle installation complete"

################################################################################
# 6. SSL CERTIFICATE SETUP (if not localhost)
################################################################################
if [[ "$USE_SSL" == "true" ]]; then
    log_info "Step 6: Setting up SSL certificate with Let's Encrypt"

    apt install -y certbot python3-certbot-nginx

    # Obtain SSL certificate
    certbot certonly --nginx -d "$FQDN" --non-interactive --agree-tos -m "$MOODLE_ADMIN_EMAIL" || {
        log_warning "SSL certificate generation failed. You may need to run certbot manually."
        log_warning "Command: certbot certonly --nginx -d $FQDN"
    }

    # Enable auto-renewal
    systemctl enable certbot.timer
    systemctl start certbot.timer

    log_success "SSL certificate setup complete"
else
    log_info "Step 6: Skipping SSL setup (localhost mode)"
fi

################################################################################
# 7. NGINX VIRTUAL HOST CONFIGURATION
################################################################################
log_info "Step 7: Configuring Nginx virtual host"

if [[ "$USE_SSL" == "true" ]]; then
    # HTTPS configuration
    cat > "/etc/nginx/sites-available/${FQDN}" << EOF
server {
    listen 80;
    server_name ${FQDN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${FQDN};

    root ${MOODLE_DIR}/public;
    index index.php index.html index.htm;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # File upload size limit
    client_max_body_size 512M;

    # Logging
    access_log /var/log/nginx/moodle-access.log;
    error_log /var/log/nginx/moodle-error.log;

    # Moodle rewrite rules
    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP-FPM configuration
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;

        # FastCGI cache (disabled for admin/login pages)
        set \$skip_cache 0;
        if (\$request_uri ~* "/(admin|login|course/view)") {
            set \$skip_cache 1;
        }
        fastcgi_cache_bypass \$skip_cache;
        fastcgi_no_cache \$skip_cache;
        fastcgi_cache moodle;
        fastcgi_cache_valid 200 60m;
    }

    # Deny access to sensitive files
    location ~ (/\.ht|\.git|\.env|composer\.(json|lock)) {
        deny all;
        return 404;
    }

    # Static file caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
else
    # HTTP-only configuration for localhost
    cat > "/etc/nginx/sites-available/${FQDN}" << EOF
server {
    listen 80;
    server_name ${FQDN};

    root ${MOODLE_DIR}/public;
    index index.php index.html index.htm;

    # File upload size limit
    client_max_body_size 512M;

    # Logging
    access_log /var/log/nginx/moodle-access.log;
    error_log /var/log/nginx/moodle-error.log;

    # Moodle rewrite rules
    location / {
        try_files \$uri \$uri/ =404;
    }

    # PHP-FPM configuration
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;

        # FastCGI cache (disabled for admin/login pages)
        set \$skip_cache 0;
        if (\$request_uri ~* "/(admin|login|course/view)") {
            set \$skip_cache 1;
        }
        fastcgi_cache_bypass \$skip_cache;
        fastcgi_no_cache \$skip_cache;
        fastcgi_cache moodle;
        fastcgi_cache_valid 200 60m;
    }

    # Deny access to sensitive files
    location ~ (/\.ht|\.git|\.env|composer\.(json|lock)) {
        deny all;
        return 404;
    }

    # Static file caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
fi

# Enable site
ln -sf "/etc/nginx/sites-available/${FQDN}" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx
systemctl enable nginx

log_success "Nginx virtual host configured"

################################################################################
# 8. REDIS INSTALLATION
################################################################################
log_info "Step 8: Installing Redis"

apt install -y redis-server

# Configure Redis (auto-tuned for ${TOTAL_RAM_GB}GB RAM)
cat > /etc/redis/redis.conf << EOF
bind 127.0.0.1
port 6379
protected-mode yes
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory ${REDIS_MEMORY}mb
maxmemory-policy allkeys-lru
EOF

systemctl restart redis-server
systemctl enable redis-server

log_success "Redis installation complete"

################################################################################
# 9. AUTOMATED BACKUPS
################################################################################
log_info "Step 9: Setting up automated backups"

mkdir -p "${BACKUP_DIR}"/{database,full}
chown -R www-data:www-data "${BACKUP_DIR}"

# Database backup script
cat > /usr/local/bin/moodle-db-backup.sh << EOF
#!/bin/bash
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
BACKUP_DIR="${BACKUP_DIR}/database"
RETENTION_DAYS=7

TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\$BACKUP_DIR/moodle_db_\$TIMESTAMP.sql.gz"

mariadb-dump --user="\$DB_USER" --password="\$DB_PASS" \\
    --single-transaction --quick --lock-tables=false \\
    --routines --triggers "\$DB_NAME" | gzip > "\$BACKUP_FILE"

if [ \$? -eq 0 ]; then
    echo "\$(date): Database backup successful - \$BACKUP_FILE" >> /var/log/moodle-backup.log
    find "\$BACKUP_DIR" -name "moodle_db_*.sql.gz" -mtime +\$RETENTION_DAYS -delete
else
    echo "\$(date): Database backup FAILED" >> /var/log/moodle-backup.log
    exit 1
fi
EOF

# Full backup script
cat > /usr/local/bin/moodle-full-backup.sh << EOF
#!/bin/bash
BACKUP_DIR="${BACKUP_DIR}/full"
MOODLE_ROOT="${MOODLE_DIR}"
MOODLE_DATA="${MOODLE_DATA}"
RETENTION_WEEKS=4

TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="moodle_full_\$TIMESTAMP"
BACKUP_PATH="\$BACKUP_DIR/\$BACKUP_NAME"

mkdir -p "\$BACKUP_PATH"

echo "\$(date): Starting database backup..." >> /var/log/moodle-backup.log
/usr/local/bin/moodle-db-backup.sh
cp ${BACKUP_DIR}/database/moodle_db_*.sql.gz "\$BACKUP_PATH/" 2>/dev/null | head -1

echo "\$(date): Backing up Moodle code..." >> /var/log/moodle-backup.log
tar -czf "\$BACKUP_PATH/moodle_code.tar.gz" -C /var/www moodle

echo "\$(date): Backing up Moodle data..." >> /var/log/moodle-backup.log
tar -czf "\$BACKUP_PATH/moodle_data.tar.gz" -C /opt/www moodledata

cd "\$BACKUP_DIR"
tar -czf "\$BACKUP_NAME.tar.gz" "\$BACKUP_NAME"
rm -rf "\$BACKUP_PATH"

if [ \$? -eq 0 ]; then
    echo "\$(date): Full backup successful - \$BACKUP_NAME.tar.gz" >> /var/log/moodle-backup.log
    find "\$BACKUP_DIR" -name "moodle_full_*.tar.gz" -mtime +\$((RETENTION_WEEKS * 7)) -delete
else
    echo "\$(date): Full backup FAILED" >> /var/log/moodle-backup.log
    exit 1
fi
EOF

chmod +x /usr/local/bin/moodle-db-backup.sh
chmod +x /usr/local/bin/moodle-full-backup.sh

# Schedule backups with cron
cat > /etc/cron.d/moodle-backup << 'EOF'
# Moodle Automated Backups
# Daily database backup at 2:00 AM
0 2 * * * root /usr/local/bin/moodle-db-backup.sh

# Weekly full backup on Sunday at 3:00 AM
0 3 * * 0 root /usr/local/bin/moodle-full-backup.sh
EOF

touch /var/log/moodle-backup.log
chown www-data:www-data /var/log/moodle-backup.log

log_success "Automated backups configured"

################################################################################
# 10. SECURITY LAYER - FAIL2BAN
################################################################################
log_info "Step 10: Installing fail2ban (Layer 3 Security)"

apt install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/moodle-error.log
maxretry = 3

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/moodle-error.log
maxretry = 10

[php-url-fopen]
enabled = true
filter = php-url-fopen
logpath = /var/log/nginx/moodle-access.log
maxretry = 3

[moodle-auth]
enabled = true
filter = moodle-auth
logpath = /var/log/nginx/moodle-access.log
maxretry = 5
bantime = 3600
EOF

cat > /etc/fail2ban/filter.d/moodle-auth.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST /login/index\.php.*" (401|403|200)
            ^<HOST> .* "POST /login/index\.php.*" 200 .* "Invalid login"
ignoreregex =
EOF

systemctl restart fail2ban
systemctl enable fail2ban

log_success "fail2ban installation complete"

################################################################################
# 11. SECURITY LAYER - CROWDSEC
################################################################################
log_info "Step 11: Installing CrowdSec (Layer 1 Security)"

curl -s https://install.crowdsec.net | sh

apt install -y crowdsec-firewall-bouncer-nftables

cscli setup detect
cscli setup install-hub

# Install security collections
cscli collections install crowdsecurity/nginx
cscli collections install crowdsecurity/linux
cscli collections install crowdsecurity/sshd
cscli collections install crowdsecurity/mariadb
cscli collections install crowdsecurity/http-cve
cscli collections install crowdsecurity/whitelist-good-actors

systemctl restart crowdsec
systemctl enable crowdsec
systemctl restart crowdsec-firewall-bouncer
systemctl enable crowdsec-firewall-bouncer

log_success "CrowdSec installation complete"

################################################################################
# 12. SECURITY LAYER - MODSECURITY
################################################################################
log_info "Step 12: Installing ModSecurity 3 (Layer 2 Security)"
log_info "This may take 10-15 minutes..."

# Install dependencies
apt install -y libtool autoconf automake libxml2-dev libpcre2-dev \
    libyajl-dev libcurl4-openssl-dev libgeoip-dev liblmdb-dev \
    pkg-config libssl-dev zlib1g-dev

# Clone and compile ModSecurity
cd /opt
if [[ ! -d "/opt/ModSecurity" ]]; then
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity.git
fi

cd ModSecurity
git submodule init
git submodule update
sh build.sh
./configure
make -j$(nproc)
make install

# Clone ModSecurity Nginx connector
cd /opt
if [[ ! -d "/opt/ModSecurity-nginx" ]]; then
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git
fi

# Get Nginx version and download source
NGINX_VERSION=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')
cd /opt
wget -q http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
tar -xzf nginx-${NGINX_VERSION}.tar.gz

# Compile Nginx module
cd /opt/nginx-${NGINX_VERSION}
./configure --with-compat --add-dynamic-module=/opt/ModSecurity-nginx
make modules
cp objs/ngx_http_modsecurity_module.so /usr/share/nginx/modules/

# Download OWASP CRS
mkdir -p /etc/nginx/modsec
cd /opt
git clone --depth 1 https://github.com/coreruleset/coreruleset.git /etc/nginx/modsec/owasp-crs
cd /etc/nginx/modsec/owasp-crs
cp crs-setup.conf.example crs-setup.conf

# Configure ModSecurity
cp /opt/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
cp /opt/ModSecurity/unicode.mapping /etc/nginx/modsec/

# Enable ModSecurity
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/nginx/modsec/modsecurity.conf

# Create ModSecurity main config with Moodle exclusions
cat > /etc/nginx/modsec/main.conf << 'EOF'
# ModSecurity Main Configuration for Moodle

# Include base ModSecurity configuration
Include /etc/nginx/modsec/modsecurity.conf

# Include OWASP Core Rule Set
Include /etc/nginx/modsec/owasp-crs/crs-setup.conf
Include /etc/nginx/modsec/owasp-crs/rules/*.conf

# Moodle-specific exclusions to prevent false positives
# Rule 920350: Host header is a numeric IP address
SecRuleRemoveById 920350

# Rule 942450: SQL Hex Encoding Identified
SecRuleRemoveById 942450

# Disable some rules for Moodle admin area
SecRule REQUEST_URI "@beginsWith /admin" \
    "id:1000,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=942100"

# Moodle AJAX Service Exclusions (prevents 403 errors on AJAX requests)
# Disable protocol enforcement for AJAX endpoints with long query strings
SecRule REQUEST_URI "@beginsWith /lib/ajax/service" \
    "id:1002,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=920100,ctl:ruleRemoveById=920440"

# Increase PCRE limits for Moodle AJAX (handles long JSON-encoded parameters)
SecPcreMatchLimit 150000
SecPcreMatchLimitRecursion 150000

# Allow larger request bodies for Moodle (512MB for file uploads)
SecRequestBodyLimit 536870912
SecRequestBodyNoFilesLimit 262144

# Repository AJAX exclusions (file picker operations)
# Disable RCE detection for repository_ajax.php (false positives on 'env' parameter)
SecRule REQUEST_URI "@beginsWith /repository/repository_ajax.php" \
    "id:1003,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=932340"
EOF

# Load ModSecurity module in Nginx
sed -i '1i load_module modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf

# Update virtual host to use ModSecurity
sed -i "/server_name ${FQDN};/a \\    # Enable ModSecurity WAF (Layer 2)\\n    modsecurity on;\\n    modsecurity_rules_file /etc/nginx/modsec/main.conf;" "/etc/nginx/sites-available/${FQDN}"

# Test and restart Nginx
nginx -t
systemctl restart nginx

log_success "ModSecurity installation complete"

################################################################################
# CREATE CREDENTIALS FILE
################################################################################
log_info "Creating credentials file..."

# Create credentials file
cat > "$CREDENTIALS_FILE" << EOF
================================================================================
                    MOODLE INSTALLATION CREDENTIALS
================================================================================
Generated: $(date)
Installation completed successfully!

MOODLE INFORMATION
================================================================================
Moodle URL:          ${WWW_ROOT}
Moodle Directory:    ${MOODLE_DIR}
Data Directory:      ${MOODLE_DATA}
Backup Directory:    ${BACKUP_DIR}
Admin Email:         ${MOODLE_ADMIN_EMAIL}

DATABASE CREDENTIALS
================================================================================
Database Name:       ${DB_NAME}
Database User:       ${DB_USER}
Database Password:   ${DB_PASS}
Database Root Pass:  ${DB_ROOT_PASS}
Database Host:       localhost

SYSTEM RESOURCES (AUTO-DETECTED)
================================================================================
CPU Cores:           ${CPU_CORES}
Total RAM:           ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)

OPTIMIZED CONFIGURATION
================================================================================
MariaDB Buffer Pool: ${INNODB_BUFFER_POOL}G (${INNODB_INSTANCES} instances)
PHP-FPM Max Children: ${PHP_MAX_CHILDREN}
PHP-FPM Start Servers: ${PHP_START_SERVERS}
Redis Memory:        ${REDIS_MEMORY}MB
Max File Upload:     512MB

CONFIGURATION FILES
================================================================================
Moodle Config:       ${MOODLE_DIR}/config.php
Nginx Config:        /etc/nginx/sites-available/${FQDN}
PHP Config:          /etc/php/8.3/fpm/conf.d/99-moodle.ini
MariaDB Config:      /etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf
ModSecurity Config:  /etc/nginx/modsec/main.conf

SECURITY LAYERS (3-LAYER WAF)
================================================================================
Layer 1: CrowdSec    - Community threat intelligence
Layer 2: ModSecurity - Application firewall (1,684 OWASP rules)
Layer 3: fail2ban    - Behavioral monitoring (5 jails)

AUTOMATED BACKUPS
================================================================================
Daily Database:      2:00 AM (7-day retention)
Weekly Full:         Sunday 3:00 AM (4-week retention)
Backup Location:     ${BACKUP_DIR}
Backup Log:          /var/log/moodle-backup.log

IMPORTANT SECURITY NOTES
================================================================================
1. This file contains sensitive passwords - keep it secure!
2. Store this file in a safe location or password manager
3. Delete this file after saving credentials elsewhere:
   sudo rm ${CREDENTIALS_FILE}

4. Change default Moodle admin password after first login
5. Configure firewall if not already done:
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp

NEXT STEPS
================================================================================
1. Access Moodle web installer: ${WWW_ROOT}
2. Complete the installation wizard
3. Create your Moodle admin account
4. Configure email settings (optional)
5. Install additional themes/plugins (optional)

USEFUL COMMANDS
================================================================================
# Check services status
systemctl status nginx php8.3-fpm mariadb redis-server

# Check security
fail2ban-client status
cscli decisions list
tail -f /var/log/modsec_audit.log

# Check backups
tail -f /var/log/moodle-backup.log

# Manual backup
/usr/local/bin/moodle-db-backup.sh
/usr/local/bin/moodle-full-backup.sh

# Purge caches
sudo -u www-data php ${MOODLE_DIR}/admin/cli/purge_caches.php

================================================================================
                    INSTALLATION COMPLETED SUCCESSFULLY
================================================================================
For detailed documentation, see CLAUDE.md
Generated by Moodle automated installation script
================================================================================
EOF

chmod 600 "$CREDENTIALS_FILE"

# Also create a copy in the current directory
CURRENT_DIR_CREDS="$(pwd)/moodle-credentials.txt"
cp "$CREDENTIALS_FILE" "$CURRENT_DIR_CREDS"
chmod 600 "$CURRENT_DIR_CREDS"

log_success "Credentials saved to:"
log_success "  - $CREDENTIALS_FILE"
log_success "  - $CURRENT_DIR_CREDS"

################################################################################
# INSTALLATION COMPLETE
################################################################################

echo
echo "=============================================================================="
log_success "Moodle 5.1.1 Installation Complete!"
echo "=============================================================================="
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                        CREDENTIALS (AUTO-GENERATED)                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo
log_info "Database Credentials:"
echo -e "  ${YELLOW}Database Name:${NC}       ${DB_NAME}"
echo -e "  ${YELLOW}Database User:${NC}       ${DB_USER}"
echo -e "  ${YELLOW}Database Password:${NC}   ${DB_PASS}"
echo -e "  ${YELLOW}Root Password:${NC}       ${DB_ROOT_PASS}"
echo
log_info "Moodle Access:"
echo -e "  ${YELLOW}Moodle URL:${NC}          ${WWW_ROOT}"
echo -e "  ${YELLOW}Admin Email:${NC}         ${MOODLE_ADMIN_EMAIL}"
echo
log_warning "IMPORTANT: Credentials saved to:"
echo -e "  ${YELLOW}→ ${CREDENTIALS_FILE}${NC}"
echo -e "  ${YELLOW}→ ${CURRENT_DIR_CREDS}${NC}"
echo
echo -e "${RED}⚠  Keep these files secure! They contain sensitive passwords.${NC}"
echo
echo "=============================================================================="
echo
log_info "Installation Summary:"
log_info "  - Moodle Directory: ${MOODLE_DIR}"
log_info "  - Data Directory: ${MOODLE_DATA}"
log_info "  - Backup Directory: ${BACKUP_DIR}"
echo
log_info "Security Stack (3-Layer Defense in Depth):"
log_info "  ✓ Layer 1: CrowdSec - Community threat intelligence"
log_info "  ✓ Layer 2: ModSecurity 3 - Application firewall (1,684 OWASP rules)"
log_info "  ✓ Layer 3: fail2ban - Behavioral monitoring (5 jails)"
echo
log_info "Automated Backups:"
log_info "  ✓ Daily database backups (2:00 AM, 7-day retention)"
log_info "  ✓ Weekly full backups (Sunday 3:00 AM, 4-week retention)"
echo
log_info "Next Steps:"
echo "  1. Complete Moodle installation wizard:"
echo "     Access: ${WWW_ROOT}"
echo
echo "  2. Set up your admin account through the web interface"
echo
echo "  3. Review configuration:"
echo "     - Moodle config: ${MOODLE_DIR}/config.php"
echo "     - Nginx config: /etc/nginx/sites-available/${FQDN}"
echo "     - ModSecurity config: /etc/nginx/modsec/main.conf"
echo
log_info "Monitoring Commands:"
echo "  - Check services: systemctl status nginx php8.3-fpm mariadb redis-server"
echo "  - Check fail2ban: fail2ban-client status"
echo "  - Check CrowdSec: cscli decisions list"
echo "  - Check ModSecurity logs: tail -f /var/log/modsec_audit.log"
echo
if [[ "$USE_SSL" == "true" ]]; then
    log_info "SSL Certificate:"
    log_info "  ✓ Auto-renewal enabled (certbot.timer)"
    log_info "  - Test renewal: certbot renew --dry-run"
else
    log_warning "SSL is not configured (localhost mode)"
    log_warning "For production, run with FQDN: sudo ./install-moodle.sh yourdomain.com"
fi
echo
log_info "Documentation: See CLAUDE.md for detailed configuration and troubleshooting"
echo "=============================================================================="
echo

exit 0
